# Transit Gateway & Private NAT domain knowledge

Companion prose for `coverage/domain.yaml › services.transit_gateway` /
`services.private_nat`. Schema source: `api_docs.json` endpoints
`networking/vpc/*transitgateway*`, `networking/vpc/*privatenat*`,
`networking/firewall/*`. Behavioural facts cite the run/issue.

> Confidence: schemas + state enums = confirmed (Open API ref); Connectable / ACTIVE
> preconditions = confirmed (runs 27243446403 / 27244474565 / 27399112864).

## 1. The dependency chain (deeper than it looks)
```
transit_gateway (POST /v1/transit-gateways)            state ∈ {CREATING,ACTIVE,EDITING,DELETING,DELETED,ERROR}
  ├─ vpc_connection (POST .../vpc-connections)         state ∈ {CREATING,ACTIVE,DELETING,DELETED,ERROR}
  ├─ firewall (POST .../firewalls)        ⟵ requires the firewall CONNECTION ACTIVE first
  ├─ firewall_connection (POST .../firewall-connections)   ⟵ must reach ACTIVE before firewall/rules
  ├─ rule (POST .../routing-rules)
  └─ uplink_rule (POST .../uplink-routing-rules)        ⟵ requires firewall connection ACTIVE
private_nat (POST /v1/private-nats)  service_type=TRANSIT_GATEWAY ⟵ requires TGW "Connectable"
  └─ private_nat_ip (POST .../private-nat-ips)
```
**Max 3 transit gateways per account** (TGW quota = 3; registry/domain constraint).
Destroy order (children first): `routing-rules + uplink-rules → firewalls →
vpc-connections → transit_gateway`. Rules/connections block the TGW delete.

## 2. Create bodies

| resource | endpoint | model | required body |
|---|---|---|---|
| transit_gateway | `POST /v1/transit-gateways` | `TransitGatewayCreateRequest` | `name` (`^[a-zA-Z0-9-]*$`, 3–20). `description`, `tags` opt |
| vpc_connection | `POST /v1/transit-gateways/{id}/vpc-connections` | `TransitGatewayVpcConnectionCreateRequest` | `vpc_id` |
| firewall | `POST /v1/transit-gateways/{id}/firewalls` | `TransitGatewayFirewallCreateRequest` | `product_type` enum `(TGW_IGW, TGW_GGW, TGW_DGW, TGW_BM)` |
| firewall_connection | `POST /v1/transit-gateways/{id}/firewall-connections` | (no body model — path-only `transit_gateway_id`) | — |
| rule | `POST /v1/transit-gateways/{id}/routing-rules` | `TransitGatewayRuleCreateRequest` | `destination_cidr`, `destination_type` enum `(VPC, TGW)`, `tgw_connection_vpc_id`. `description` opt |
| uplink_rule | `POST /v1/transit-gateways/{id}/uplink-routing-rules` | `TransitGatewayUplinkRuleCreateRequest` | `destination_cidr`, `destination_type` enum `(TGW, ON_PREMISE)`. `description` opt |
| private_nat | `POST /v1/private-nats` | `PrivateNatCreateRequestV1Dot2` | `name`, `cidr`, `service_resource_id`, `service_type` enum `(DIRECT_CONNECT, TRANSIT_GATEWAY)`. (v1.0 model used `direct_connect_id` instead) |
| private_nat_ip | `POST /v1/private-nats/{id}/private-nat-ips` | `PrivateNatIpCreateRequest` | `ip_address` (len 7–15; blank ⇒ auto-assign) |

## 3. Server-set fields (DO NOT send on create) — `created_at` trap
The response models (`TransitGateway`, `TransitGatewayVpcConnection`,
`TransitGatewayVpcRule`, `PrivateNatV1Dot2`, `Firewall`) all carry `created_at`,
`created_by`, `modified_at`, `modified_by`, `id`, `state`, `account_id` — these are
**server-set, response-only**. The create request schemas above do **not** include them.

- **#— rule create 400 `"no value given for required property created_at / Invalid
  error data"` (run 27241816399):** the provider's TGW *rule* create wrongly treats the
  server-set `created_at` as a required request field (same class of bug as the peering
  `approver_vpc_name` mismatch, #61). api_docs.json confirms `created_at` is response-only.

## 4. The "Connectable" / ACTIVE-connection precondition (the big one)
Several creates fail with platform 400s because the TGW firewall **connection** is not
yet `ACTIVE`:
- `private_nat` / `private_nat_ip` (service_type TGW) → 400 **"Cannot find the Transit
  Gateway in Connectable state"** even with an in-line `vpc_connection` + `depends_on`
  (runs 27244474565, 27399112864). **"Connectable" is NOT satisfied by a merely-created
  connection** — it requires an **ACTIVE TGW firewall connection** (firewall_connection
  reached state ACTIVE, propagated).
- `transit_gateway_firewall` and `transit_gateway_firewall_connection` create → 400
  **"Transit Gateway Firewall connection state is not Active (INACTIVE)"** (run
  27243446403): creating the firewall needs the firewall *connection* ACTIVE first.
- `transit_gateway_uplink_rule` → same 400 (run 27244474565).

**Net rule for lifecycle agents:** the TGW firewall chain must be driven to ACTIVE
(create connection → wait state=ACTIVE) **before** firewall / uplink_rule / private_nat
creates. An in-line `depends_on` is insufficient; you need a state-wait on the firewall
connection becoming ACTIVE. The platform exposes no single "Connectable" flag — it is
the firewall connection's ACTIVE state.

## 5. State machine enums (from response models)
- `TransitGateway.state`: `CREATING, ACTIVE, DELETING, DELETED, ERROR, EDITING`.
- `TransitGatewayVpcConnection.state` / `PrivateNatV1Dot2.state` /
  `TransitGatewayVpcRule.state` / `TransitGatewayUplinkRule.state`:
  `CREATING, ACTIVE, DELETING, DELETED, ERROR`.
- `Firewall.state`: `CREATING, ACTIVE, DELETING, DELETED, EDITING, ERROR, DEPLOYING`;
  `Firewall.status`: `ENABLE | DISABLE`; `Firewall.product_type` incl.
  `TGW_IGW, TGW_GGW, TGW_DGW, TGW_SIGW, TGW_BM`.
- **Destroy-ordering trap:** tgw vpc-connection delete 400 `"state not Active (EDITING)"`
  when a rule add/remove left the TGW in EDITING (run 27241816399) — wait ACTIVE before
  deleting the connection.

## 6. Cross-refs
- Provider issue **#76** (vpc/TGW status-waiter infinite hang) — `vpc_connection` is
  green only with the patched waiter.
- `vpc_transit_gateway` and `vpc_transit_gateway_vpc_connection` are GREEN; the
  firewall / rule / uplink_rule / private_nat scenarios are blocked on the ACTIVE
  firewall-connection precondition above, not on schema errors.
