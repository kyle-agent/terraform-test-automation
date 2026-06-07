package capability

import (
	"encoding/json"
	"testing"

	"github.com/kyle-agent/terraform-test-automation/tests/common"
)

// apiEndpoint maps a terraform resource TYPE to the Open API (service, path
// template) that GETs it by id, for the optional destroy_verify stage. Only
// high-confidence mappings are listed; unmapped types are skipped (never reported
// as a leak on a guessed endpoint). Expand this table as coverage grows.
type apiEndpoint struct {
	service string
	path    string // %s = resource id
}

var resourceEndpoints = map[string]apiEndpoint{
	// DBaaS clusters — each engine is its own service host, all /v1/clusters/{id}.
	"samsungcloudplatformv2_mysql_cluster":        {"mysql", "/v1/clusters/%s"},
	"samsungcloudplatformv2_postgresql_cluster":   {"postgresql", "/v1/clusters/%s"},
	"samsungcloudplatformv2_mariadb_cluster":      {"mariadb", "/v1/clusters/%s"},
	"samsungcloudplatformv2_sqlserver_cluster":    {"sqlserver", "/v1/clusters/%s"},
	"samsungcloudplatformv2_epas_cluster":         {"epas", "/v1/clusters/%s"},
	"samsungcloudplatformv2_cachestore_cluster":   {"cachestore", "/v1/clusters/%s"},
	"samsungcloudplatformv2_searchengine_cluster": {"searchengine", "/v1/clusters/%s"},
	"samsungcloudplatformv2_eventstreams_cluster": {"eventstreams", "/v1/clusters/%s"},
	"samsungcloudplatformv2_ske_cluster":          {"ske", "/v1/clusters/%s"},
	// VPC family (vpc service host).
	"samsungcloudplatformv2_vpc_vpc":              {"vpc", "/v1/vpcs/%s"},
	"samsungcloudplatformv2_vpc_subnet":           {"vpc", "/v1/subnets/%s"},
	"samsungcloudplatformv2_vpc_internet_gateway": {"vpc", "/v1/internet-gateways/%s"},
	"samsungcloudplatformv2_vpc_publicip":         {"vpc", "/v1/publicips/%s"},
	"samsungcloudplatformv2_vpc_port":             {"vpc", "/v1/ports/%s"},
	"samsungcloudplatformv2_vpc_nat_gateway":      {"vpc", "/v1/nat-gateways/%s"},
	"samsungcloudplatformv2_vpc_transit_gateway":  {"vpc", "/v1/transit-gateways/%s"},
	// Compute / storage.
	"samsungcloudplatformv2_virtualserver_server": {"virtualserver", "/v1/servers/%s"},
	"samsungcloudplatformv2_filestorage_volume":   {"filestorage", "/v1/volumes/%s"},
}

// managedResource is a (type,id) pair pulled from terraform state.
type managedResource struct {
	Type string
	ID   string
}

// collectManagedResources reads `terraform show -json` and returns every managed
// resource's type + id (must be called while state still exists, i.e. before
// destroy).
func collectManagedResources(t *testing.T, dir string) []managedResource {
	showOut, err := common.TFRun(t, dir, "show", "-json")
	if err != nil {
		return nil
	}
	var state struct {
		Values struct {
			RootModule struct {
				Resources []struct {
					Type   string                     `json:"type"`
					Mode   string                     `json:"mode"`
					Values map[string]json.RawMessage `json:"values"`
				} `json:"resources"`
			} `json:"root_module"`
		} `json:"values"`
	}
	if err := json.Unmarshal([]byte(showOut), &state); err != nil {
		return nil
	}
	var out []managedResource
	for _, r := range state.Values.RootModule.Resources {
		if r.Mode != "managed" {
			continue
		}
		var id string
		if raw, ok := r.Values["id"]; ok {
			_ = json.Unmarshal([]byte(raw), &id)
		}
		if id != "" {
			out = append(out, managedResource{Type: r.Type, ID: id})
		}
	}
	return out
}
