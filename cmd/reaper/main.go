// Command reaper deletes leaked SamsungCloudPlatform v2 resources by id using
// the provider's own SDK client wrappers.
//
// Background: these resources cannot be removed through Terraform because the
// provider implements no ImportState anywhere, so import+destroy is impossible
// (see issue #81). The provider client wrappers, however, expose Delete*(ctx,id)
// methods that delete purely by id, so we call them directly here.
//
// The target list is hard-coded on purpose. No wildcards, no discovery.
package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strings"

	scpclient "github.com/SamsungSDSCloud/terraform-provider-samsungcloudplatformv2/v3/samsungcloudplatform/client"
	provdns "github.com/SamsungSDSCloud/terraform-provider-samsungcloudplatformv2/v3/samsungcloudplatform/client/dns"
	"github.com/SamsungSDSCloud/terraform-provider-samsungcloudplatformv2/v3/samsungcloudplatform/config"

	sdkdns "github.com/SamsungSDSCloud/terraform-sdk-samsungcloudplatformv2/v3/library/dns/1.3"
	"github.com/hashicorp/terraform-plugin-framework/types"
)

// target describes one resource to delete.
type target struct {
	kind string
	id   string
	note string
	del  func(ctx context.Context, c *scpclient.SCPClient, dnsAPI *sdkdns.APIClient) error
}

// targets are deleted in the listed order. Targets 1-2 (transit gateway plumbing)
// must go before the VPCs they attach to. private_dns is removed before its VPC.
//
// DO NOT add anything else here, especially not the live VPCs
// (19cfe1fc.../58c850e2.../rpv269469061xxx).
var targets = []target{
	{
		kind: "transit_gateway_vpc_connection",
		id:   "39ceadf32552426eb1929507823698cd",
		del: func(ctx context.Context, c *scpclient.SCPClient, _ *sdkdns.APIClient) error {
			// DeleteTransitGatewayVpcConnection needs both the transit gateway id
			// and the connection id.
			return c.Vpc.DeleteTransitGatewayVpcConnection(ctx, transitGatewayID, "39ceadf32552426eb1929507823698cd")
		},
	},
	{
		kind: "transit_gateway",
		id:   transitGatewayID,
		del: func(ctx context.Context, c *scpclient.SCPClient, _ *sdkdns.APIClient) error {
			return c.Vpc.DeleteTransitGateway(ctx, transitGatewayID)
		},
	},
	{
		kind: "vpc",
		id:   "02bbf96c66d14dd297d3fe8a5fe1cb72",
		note: "rpv269430906961",
		del: func(ctx context.Context, c *scpclient.SCPClient, _ *sdkdns.APIClient) error {
			return c.Vpc.DeleteVpc(ctx, "02bbf96c66d14dd297d3fe8a5fe1cb72")
		},
	},
	{
		kind: "private_dns",
		id:   "42339727233a425eba6675d6428c90ff",
		del: func(ctx context.Context, c *scpclient.SCPClient, _ *sdkdns.APIClient) error {
			return c.Dns.DeletePrivateDns(ctx, "42339727233a425eba6675d6428c90ff")
		},
	},
	{
		kind: "vpc",
		id:   "8df00c61800d4ad9914cffb74d9a2149",
		note: "rpv269430906962",
		del: func(ctx context.Context, c *scpclient.SCPClient, _ *sdkdns.APIClient) error {
			return c.Vpc.DeleteVpc(ctx, "8df00c61800d4ad9914cffb74d9a2149")
		},
	},
	{
		kind: "public_domain_name",
		id:   "0ee424a4d97b4ff3b4a37691f7e245dd",
		del: func(ctx context.Context, _ *scpclient.SCPClient, dnsAPI *sdkdns.APIClient) error {
			return deletePublicDomain(ctx, dnsAPI, "0ee424a4d97b4ff3b4a37691f7e245dd")
		},
	},
	{
		kind: "public_domain_name",
		id:   "70b84eeaf98349d18bbb8d5141e09e07",
		del: func(ctx context.Context, _ *scpclient.SCPClient, dnsAPI *sdkdns.APIClient) error {
			return deletePublicDomain(ctx, dnsAPI, "70b84eeaf98349d18bbb8d5141e09e07")
		},
	},
}

const transitGatewayID = "12af6b7e1d634e1aa574975c4090c43f"

// deletePublicDomain deletes a public domain name by id. The provider client
// exposes no exported Delete wrapper for public domains, so we call the SDK API
// directly (same SDK the provider uses).
func deletePublicDomain(ctx context.Context, dnsAPI *sdkdns.APIClient, id string) error {
	req := dnsAPI.DnsV1PublicDomainNameApiAPI.DeletePublicDomain(ctx, id)
	_, err := req.Execute()
	return err
}

func main() {
	providerConfig := buildProviderConfig()

	c, err := scpclient.NewSCPClient(providerConfig)
	if err != nil {
		fmt.Printf("FATAL could not build SCP client: %v\n", err)
		os.Exit(0)
	}

	// Build a raw DNS SDK API client for the public-domain deletes, reusing the
	// provider's own default config builder so auth/endpoint handling matches.
	dnsAPI := sdkdns.NewAPIClient(scpclient.NewDefaultConfig(providerConfig, provdns.ServiceType))

	ctx := context.Background()

	for i, t := range targets {
		label := fmt.Sprintf("[%d/%d] %s %s", i+1, len(targets), t.kind, t.id)
		if t.note != "" {
			label += " (" + t.note + ")"
		}

		err := t.del(ctx, c, dnsAPI)
		switch {
		case err == nil:
			fmt.Printf("%s -> OK\n", label)
		case isNotFound(err):
			fmt.Printf("%s -> ALREADY-GONE\n", label)
		default:
			fmt.Printf("%s -> ERROR %s\n", label, err.Error())
		}
	}

	// Always exit 0 so the full report is visible even when some deletes failed.
	os.Exit(0)
}

// buildProviderConfig constructs a ProviderConfig straight from the SCP_TF_* env
// vars by setting the tfsdk fields directly (no Terraform plumbing needed).
func buildProviderConfig() *config.ProviderConfig {
	return &config.ProviderConfig{
		AuthUrl:       types.StringValue(os.Getenv("SCP_TF_AUTH_URL")),
		DefaultRegion: types.StringValue(os.Getenv("SCP_TF_DEFAULT_REGION")),
		AccessKey:     types.StringValue(os.Getenv("SCP_TF_ACCESS_KEY")),
		SecretKey:     types.StringValue(os.Getenv("SCP_TF_SECRET_KEY")),
	}
}

// isNotFound treats 404 / not-found responses as "already gone" successes.
func isNotFound(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "404") ||
		strings.Contains(msg, "not found") ||
		strings.Contains(msg, "not_found") ||
		strings.Contains(msg, "notfound") ||
		strings.Contains(msg, "does not exist") ||
		statusFromErr(err) == http.StatusNotFound
}

// statusFromErr tries to pull an HTTP status code out of an SDK error if present.
func statusFromErr(err error) int {
	type statuser interface{ StatusCode() int }
	var s statuser
	if errors.As(err, &s) {
		return s.StatusCode()
	}
	return 0
}
