package common

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"
)

// SCP Open API HMAC GET helper, used by the capability harness' optional
// "destroy_verify" stage to confirm a resource is really gone after destroy.
// Mirrors the auth proven by .claude/skills/scp-api/scp_api.py and the
// api-test-automation framework:
//   signing string = METHOD + encodeURI(url) + ts_ms + accessKey + clientType
//   signature      = base64(HMAC_SHA256(secretKey, signing_string))
// Credentials come from the same env the provider uses (SCP_TF_ACCESS_KEY/
// SECRET_KEY are the HMAC keys); region from SCP_DEFAULT_REGION, env from SCP_ENV.

var globalServices = map[string]bool{
	"iam": true, "product": true, "billing": true, "resourcemanager": true,
	"organization": true, "quota": true, "pricing": true,
}

func apiEnvCode() string {
	if v := os.Getenv("SCP_ENV"); v != "" {
		return v
	}
	return "e"
}

func apiRegion() string {
	for _, k := range []string{"SCP_REGION", "SCP_DEFAULT_REGION", "SCP_TF_DEFAULT_REGION"} {
		if v := os.Getenv(k); v != "" {
			return v
		}
	}
	return "kr-west1"
}

func apiHost(service string) string {
	if globalServices[service] {
		return fmt.Sprintf("https://%s.%s.samsungsdscloud.com", service, apiEnvCode())
	}
	return fmt.Sprintf("https://%s.%s.%s.samsungsdscloud.com", service, apiRegion(), apiEnvCode())
}

// encodeURI replicates JS encodeURI(): escape everything except unreserved chars
// and the reserved set encodeURI leaves intact. Our paths are simple (alnum, '/',
// '-'), so this is effectively identity, but we implement it for correctness.
func encodeURI(s string) string {
	const safe = "!#$&'()*+,-./:;=?@_~"
	var b strings.Builder
	for _, r := range []byte(s) {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') ||
			strings.IndexByte(safe, r) >= 0 {
			b.WriteByte(r)
		} else {
			b.WriteString(fmt.Sprintf("%%%02X", r))
		}
	}
	return b.String()
}

// APICredsAvailable reports whether the HMAC keys are present.
func APICredsAvailable() bool {
	return os.Getenv("SCP_TF_ACCESS_KEY") != "" && os.Getenv("SCP_TF_SECRET_KEY") != ""
}

// APIStatus performs an HMAC-signed GET against service+path and returns the HTTP
// status (0 on transport error). Used to check existence: 2xx = exists, 404 = gone.
func APIStatus(service, path string) (int, error) {
	ak := os.Getenv("SCP_TF_ACCESS_KEY")
	sk := os.Getenv("SCP_TF_SECRET_KEY")
	if ak == "" || sk == "" {
		return 0, fmt.Errorf("no SCP HMAC credentials in env")
	}
	const clientType = "Openapi"
	url := apiHost(service) + path
	ts := fmt.Sprintf("%d", time.Now().UnixMilli())
	msg := "GET" + encodeURI(url) + ts + ak + clientType
	mac := hmac.New(sha256.New, []byte(sk))
	mac.Write([]byte(msg))
	sig := base64.StdEncoding.EncodeToString(mac.Sum(nil))

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Scp-Accesskey", ak)
	req.Header.Set("Scp-Signature", sig)
	req.Header.Set("Scp-Timestamp", ts)
	req.Header.Set("Scp-ClientType", clientType)
	req.Header.Set("Accept-Language", "en-US")
	req.Header.Set("Accept", "application/json")

	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()
	return resp.StatusCode, nil
}
