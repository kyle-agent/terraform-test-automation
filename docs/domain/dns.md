# DNS domain knowledge (private DNS, hosted zones, records)

Companion prose for `coverage/domain.yaml › services.dns`. Source of truth for schemas:
`api-test-automation/data/api_docs.json` endpoints `networking/dns/*`. Behavioural
facts cite the run/issue that proved them.

> Maintained by Domain-Knowledge-Curator; human-owned. Confidence: schemas = confirmed
> (scraped Open API ref); lifecycle gotchas = confirmed (run evidence, issue #79).

## 1. Resource lifecycle & ordering

```
private_dns  (POST /v1/private-dns)                 ← binds to VPCs via connected_vpc_ids
  └─ hosted_zone (POST /v1/hosted-zones)            ← type=private references private_dns_id
        └─ record  (POST /v1/hosted-zones/{id}/records)
```
Destroy in reverse: record → hosted_zone → private_dns. **A private_dns that is still
bound to a VPC (`connected_vpc_ids` non-empty) blocks the VPC delete** — see §4.

## 2. Create / delete request schemas

### private_dns — `POST /v1/private-dns` (model `PrivateDnsCreateRequest`)
| field | req | type | notes |
|---|---|---|---|
| `name` | **REQ** | string | Pattern `^[a-zA-Z0-9-]*$`, len 3–20 |
| `connected_vpc_ids` | opt | array[string] | VPC IDs to bind at create; may be `[]` |
| `description` | opt | string\|null | |
| `tags` | opt | array[Tag] | |

- Activation is a separate call: `POST /v1/private-dns/activate` body
  `{ "name": "<name>" }` (model `PrivateDnsActivateRequest`).
- Update VPC binding: `PUT /v1/private-dns/{id}` (`PrivateDnsSetRequest` =
  `connected_vpc_ids`, `description`). **This is the disassociation step** — to unbind
  before delete, PUT `connected_vpc_ids: []`.
- Delete: `DELETE /v1/private-dns/{private_dns_id}` (no body).

### hosted_zone — `POST /v1/hosted-zones` (model `HostedZoneCreateRequestV1Dot3`)
| field | req | type | notes |
|---|---|---|---|
| `name` | **REQ** | string | e.g. `my-zone.com` |
| `type` | **REQ** | enum `(public, private)` | |
| `private_dns_id` | opt | string\|null | **required when `type=private`** — links the zone to a private DNS |
| `description` | opt | string\|null | |
| `tags` | opt | array[Tag] | |

Delete: `DELETE /v1/hosted-zones/{hosted_zone_id}`.

### record — `POST /v1/hosted-zones/{hosted_zone_id}/records` (model `RecordCreateRequest`)
| field | req | type | notes |
|---|---|---|---|
| `name` | **REQ** | string | e.g. `test.app` |
| `type` | **REQ** | string | record type, e.g. `A`, `CNAME`, `NS` |
| `records` | **REQ** | array[object] | the record data list (target values) |
| `ttl` | opt | integer\|null | e.g. `3600` |
| `description` | opt | string\|null | |

Delete: `DELETE /v1/hosted-zones/{hosted_zone_id}/records/{record_id}`.

## 3. State machine
Private DNS is created then **activated** (two-step). Hosted zone / record creates
return synchronously. There is no long async CREATING-trap like DBaaS.

## 4. Gotchas the suite already proved
- **#79 — private_dns destroy 409 (LEAK):** the provider destroy does not unbind the
  private_dns from its VPC first, so the private_dns stays bound and the **VPC delete
  409s**. The api-test-automation fix is to **PUT `connected_vpc_ids: []` (the
  disassociation step) before `DELETE /v1/private-dns/{id}`**. Lifecycle agents must
  encode this disassociate-then-delete order (mirrors the registry note on
  `dns_private_dns` / `dns_hosted_zone`).
- **public-domain-name has NO delete API** → console/release only; create 500 leaves an
  orphan (#82). Out of scope for clean teardown.
- DNS is a **`none`-lane** family (no VPC needed for hosted zones with `type=public`);
  private DNS + its VPC binding is what pulls it into VPC-dependency cleanup.
