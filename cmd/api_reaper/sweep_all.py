#!/usr/bin/env python3
"""Sweep ALL test-created resources from the SCP account via the Open API.

Deletes every resource whose NAME matches our test prefixes, in dependency order
(children before parents). terraform bootstrap names: rpv (vpc), rps/rpsg
(subnet/sg), rpkp (keypair), rpfs (filestorage), IGW_/FW_IGW_ (gateway/firewall);
scenario names: regr*, rske (ske), rlb (loadbalancer), rtgw (transit gateway).

Scoped strictly to those prefixes so a pre-existing non-test resource is never
touched. Requires SCP_ALLOW_MUTATIONS=true and SCP_ALLOW_DESTRUCTIVE=true.
Reuses the kyle-agent/api-test-automation framework (HMAC client) on PYTHONPATH.
Prints everything it finds (= inventory) and what it deleted (= leak audit).
"""
from __future__ import annotations

import datetime as _dt
import os
import time

from _client import ApiClient, MutationBlocked, settings

PREFIXES = ("regr", "rpv", "rps", "rpkp", "rpfs", "rske", "rlb", "rtgw", "igw_", "fw_igw")

# TTL safety net: when >0, only reap resources at least this many hours old, so a
# scheduled sweep can't delete a resource an in-flight run is still using. On-demand
# sweeps leave this at 0 (reap immediately). Set via SWEEP_MIN_AGE_HOURS.
MIN_AGE_HOURS = float(os.environ.get("SWEEP_MIN_AGE_HOURS", "0") or "0")

# SWEEP_ALL=1: this is a dedicated single-tenant test account with no production
# resources, so reap EVERYTHING (ignore the name-prefix allowlist) — still gated by the
# TTL above. Off by default so the prefix allowlist protects shared accounts.
SWEEP_ALL = os.environ.get("SWEEP_ALL", "0") == "1"

# Safety guard for SWEEP_ALL: the account is decided by the access-key SECRET, not by
# any variable, so a misconfigured secret could point the full-account nuke at the WRONG
# account. EXPECTED_ACCOUNT_ID (= the configured account id) must match the LIVE account
# (read from a real resource) or SWEEP_ALL is downgraded to safe prefix-only.
EXPECTED_ACCOUNT_ID = os.environ.get("EXPECTED_ACCOUNT_ID", "").strip()


def is_test(name) -> bool:
    if SWEEP_ALL:
        return True
    n = str(name or "").lower()
    return any(n.startswith(p) for p in PREFIXES)


def _created_at(it):
    for k in ("created_at", "created", "create_at", "createdAt"):
        v = it.get(k) if isinstance(it, dict) else None
        if v:
            try:
                return _dt.datetime.fromisoformat(str(v).replace("Z", "+00:00"))
            except ValueError:
                return None
    return None


def old_enough(it) -> bool:
    if MIN_AGE_HOURS <= 0:
        return True
    ts = _created_at(it)
    if ts is None:
        return True  # unknown age -> don't block reaping (still prefix-scoped)
    if ts.tzinfo is None:
        ts = ts.replace(tzinfo=_dt.timezone.utc)
    age_h = (_dt.datetime.now(_dt.timezone.utc) - ts).total_seconds() / 3600.0
    return age_h >= MIN_AGE_HOURS


def items(body):
    if isinstance(body, dict):
        for v in body.values():
            if isinstance(v, list) and (not v or isinstance(v[0], dict)):
                return v
    return body if isinstance(body, list) else []


def name_of(it):
    for k in ("name", "volume_name", "cluster_name", "registry_name"):
        if isinstance(it, dict) and it.get(k):
            return str(it[k])
    return ""


def lst(c, svc, path):
    try:
        r = c.get(path, service=svc)
    except Exception as exc:
        print(f"  list {svc}{path} error: {exc}"); return []
    if not getattr(r, "ok", False):
        print(f"  list {svc}{path} -> {r.status}"); return []
    return [it for it in items(r.body)
            if isinstance(it, dict) and is_test(name_of(it)) and old_enough(it)]


def delete(c, svc, path, json=None):
    try:
        r = c.delete(path, service=svc, json=json)
        print(f"  DELETE {svc}{path} -> {r.status}")
        return r.status
    except MutationBlocked as exc:
        print(f"  blocked: {exc}"); return None
    except Exception as exc:
        print(f"  delete {svc}{path} error: {exc}"); return None


def wait_gone(c, svc, path, timeout=300, interval=15):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            if c.get(path, service=svc).status == 404:
                return True
        except Exception:
            return True
        time.sleep(interval)
    return False


def reap_tgw(c, tgwid, name):
    print(f"  TGW {name} ({tgwid}) full teardown")
    for sub in ("routing-rules", "uplink-routing-rules"):
        for r in items(c.get(f"/v1/transit-gateways/{tgwid}/{sub}", service="vpc").body):
            if r.get("id"):
                delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/{sub}/{r['id']}")
    for fw in items(c.get(f"/v1/transit-gateways/{tgwid}/firewalls", service="vpc").body):
        if fw.get("id"):
            delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/firewalls/{fw['id']}")
    for conn in items(c.get(f"/v1/transit-gateways/{tgwid}/vpc-connections", service="vpc").body):
        if conn.get("id"):
            delete(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}")
            wait_gone(c, "vpc", f"/v1/transit-gateways/{tgwid}/vpc-connections/{conn['id']}", 240, 15)
    for _ in range(6):
        st = delete(c, "vpc", f"/v1/transit-gateways/{tgwid}")
        if st in (200, 202, 204, 404):
            wait_gone(c, "vpc", f"/v1/transit-gateways/{tgwid}", 240, 15); return
        if st == 409:
            time.sleep(15); continue
        return


def vid_field(it):
    return str(it.get("vpc_id") or "")


def main() -> int:
    global SWEEP_ALL
    settings.require_credentials()
    c = ApiClient(settings)
    n = 0

    # Determine the LIVE account (whatever the access-key secret belongs to) by reading
    # account_id off any real resource, then enforce the SWEEP_ALL account guard.
    live_account = ""
    for svc, path in (("vpc", "/v1/vpcs"), ("vpc", "/v1/subnets"),
                      ("virtualserver", "/v1/servers"), ("security-group", "/v1/security-groups")):
        try:
            for it in items(c.get(path, service=svc).body):
                if isinstance(it, dict) and it.get("account_id"):
                    live_account = it["account_id"]; break
        except Exception:
            pass
        if live_account:
            break
    print(f"live account (from access-key secret) = {live_account or 'unknown/empty'}; "
          f"EXPECTED_ACCOUNT_ID = {EXPECTED_ACCOUNT_ID or 'unset'}; SWEEP_ALL requested = {SWEEP_ALL}")
    if SWEEP_ALL:
        if not EXPECTED_ACCOUNT_ID:
            print("  GUARD: SWEEP_ALL requested but EXPECTED_ACCOUNT_ID is unset -> "
                  "downgrading to prefix-only (set it to the dedicated account id to allow).")
            SWEEP_ALL = False
        elif live_account and live_account != EXPECTED_ACCOUNT_ID:
            print(f"  GUARD: live account {live_account} != EXPECTED {EXPECTED_ACCOUNT_ID} -> "
                  "the secret points at a DIFFERENT account than configured; downgrading to "
                  "prefix-only so we never mass-delete the wrong account.")
            SWEEP_ALL = False
        else:
            print(f"  GUARD ok: full-account SWEEP_ALL on {live_account or EXPECTED_ACCOUNT_ID}.")

    print(f"region={settings.region} env={settings.env_code} — "
          + ("FULL SWEEP (all resources)" if SWEEP_ALL else f"sweeping test prefixes {PREFIXES}")
          + (f" (min age {MIN_AGE_HOURS}h)" if MIN_AGE_HOURS > 0 else ""))

    # 1. virtualserver: servers (free subnet/sg), then keypairs, snapshots, volumes
    for it in lst(c, "virtualserver", "/v1/servers"):
        if it.get("id") and delete(c, "virtualserver", f"/v1/servers/{it['id']}"):
            n += 1; wait_gone(c, "virtualserver", f"/v1/servers/{it['id']}", 300, 15)
    # 2. ske clusters: nodepools then cluster
    for it in lst(c, "ske", "/v1/clusters"):
        cid = it.get("id")
        for np in items(c.get(f"/v1/clusters/{cid}/nodepools", service="ske").body):
            if np.get("id"):
                delete(c, "ske", f"/v1/nodepools/{np['id']}"); wait_gone(c, "ske", f"/v1/nodepools/{np['id']}", 600, 30)
        for _ in range(8):
            st = delete(c, "ske", f"/v1/clusters/{cid}")
            if st in (200, 202, 204, 404):
                n += 1; wait_gone(c, "ske", f"/v1/clusters/{cid}", 600, 30); break
            if st in (409, 500):
                time.sleep(30); continue
            break
    # 3. dbaas clusters (per engine host) + searchengine
    for svc in ("mysql", "postgresql", "mariadb", "sqlserver", "epas", "cachestore", "searchengine"):
        for it in lst(c, svc, "/v1/clusters"):
            if it.get("id") and delete(c, svc, f"/v1/clusters/{it['id']}"):
                n += 1
    # 4. loadbalancers — an LB won't delete (409) while it has listeners / server
    # groups / health checks, so tear those down first, then the LB with retries.
    for coll in ("lb-listeners", "lb-server-groups", "lb-health-checks"):
        for it in lst(c, "loadbalancer", f"/v1/{coll}"):
            if it.get("id"):
                delete(c, "loadbalancer", f"/v1/{coll}/{it['id']}")
    for it in lst(c, "loadbalancer", "/v1/loadbalancers"):
        lbid = it.get("id")
        if not lbid:
            continue
        for _ in range(6):
            st = delete(c, "loadbalancer", f"/v1/loadbalancers/{lbid}")
            if st in (200, 202, 204, 404):
                n += 1; wait_gone(c, "loadbalancer", f"/v1/loadbalancers/{lbid}", 240, 15); break
            if st == 409:
                time.sleep(20); continue
            break
    # 5. transit gateways — full teardown (rules -> connections -> tgw)
    for it in lst(c, "vpc", "/v1/transit-gateways"):
        if it.get("id"):
            reap_tgw(c, it["id"], name_of(it)); n += 1
    # 5b. vpc-peerings (rules->peering), vpc-endpoints, private-nats (+nat-ips) —
    # these pin a VPC and were the missing child types causing 409 on vpc delete.
    for it in lst(c, "vpc", "/v1/vpc-peerings"):
        pid = it.get("id")
        if not pid:
            continue
        for r in items(c.get(f"/v1/vpc-peerings/{pid}/routing-rules", service="vpc").body):
            if r.get("id"):
                delete(c, "vpc", f"/v1/vpc-peerings/{pid}/routing-rules/{r['id']}")
        if delete(c, "vpc", f"/v1/vpc-peerings/{pid}"):
            n += 1; wait_gone(c, "vpc", f"/v1/vpc-peerings/{pid}", 180, 10)
    for it in lst(c, "vpc", "/v1/vpc-endpoints"):
        if it.get("id") and delete(c, "vpc", f"/v1/vpc-endpoints/{it['id']}"):
            n += 1; wait_gone(c, "vpc", f"/v1/vpc-endpoints/{it['id']}", 180, 10)
    for it in lst(c, "vpc", "/v1/private-nats"):
        pid = it.get("id")
        if not pid:
            continue
        for ip in items(c.get(f"/v1/private-nats/{pid}/private-nat-ips", service="vpc").body):
            if ip.get("id"):
                delete(c, "vpc", f"/v1/private-nats/{pid}/private-nat-ips/{ip['id']}")
        if delete(c, "vpc", f"/v1/private-nats/{pid}"):
            n += 1
    # 5c. vpn gateways/tunnels — leaked regr* VPN gateways accumulate (1 gateway
    # per VPC limit) and cause name collisions on re-create. Tunnels terminate on
    # a gateway, so delete tunnels first, then the gateways. Both also pin a VPC,
    # so they must go before the vpc teardown below.
    for it in lst(c, "vpn", "/v1/vpn-tunnels"):
        if it.get("id") and delete(c, "vpn", f"/v1/vpn-tunnels/{it['id']}"):
            n += 1
            wait_gone(c, "vpn", f"/v1/vpn-tunnels/{it['id']}", 240, 15)
    for it in lst(c, "vpn", "/v1/vpn-gateways"):
        gid = it.get("id")
        if not gid:
            continue
        for _ in range(6):
            st = delete(c, "vpn", f"/v1/vpn-gateways/{gid}")
            if st in (200, 202, 204, 404):
                n += 1
                wait_gone(c, "vpn", f"/v1/vpn-gateways/{gid}", 240, 15)
                break
            if st == 409:
                time.sleep(15)
                continue
            break
    # 6. vpc children that block vpc delete
    for it in lst(c, "vpc", "/v1/nat-gateways"):
        if it.get("id") and delete(c, "vpc", f"/v1/nat-gateways/{it['id']}"):
            n += 1
    for it in lst(c, "vpc", "/v1/ports"):
        if it.get("id") and delete(c, "vpc", f"/v1/ports/{it['id']}"):
            n += 1
    for it in lst(c, "vpc", "/v1/publicips"):
        if it.get("id") and delete(c, "vpc", f"/v1/publicips/{it['id']}"):
            n += 1
    # 7. independent compute/storage
    for it in lst(c, "virtualserver", "/v1/keypairs"):
        if it.get("name") and delete(c, "virtualserver", f"/v1/keypairs/{it['name']}"):
            n += 1
    for it in lst(c, "security-group", "/v1/security-groups"):
        if it.get("id") and delete(c, "security-group", f"/v1/security-groups/{it['id']}"):
            n += 1
    for it in lst(c, "filestorage", "/v1/volumes"):
        vid = it.get("volume_id") or it.get("id")
        if vid and delete(c, "filestorage", f"/v1/volumes/{vid}"):
            n += 1
    # 8. DNS: private-dns (deletable only when ACTIVE), public-domain (NO delete API)
    for it in lst(c, "dns", "/v1/private-dns"):
        if it.get("id"):
            if str(it.get("state", "")).upper() in ("ACTIVE", ""):
                if delete(c, "dns", f"/v1/private-dns/{it['id']}"):
                    n += 1; wait_gone(c, "dns", f"/v1/private-dns/{it['id']}", 240, 15)
            else:
                print(f"  SKIP private-dns {name_of(it)} ({it['id']}) state={it.get('state')} — not deletable until ACTIVE")
    for it in lst(c, "dns", "/v1/public-domain-names"):
        print(f"  MANUAL public-domain {name_of(it)} ({it.get('id')}) — no DELETE API; release via console")
    # 9. subnets -> internet-gateways -> vpcs
    sids = []
    for it in lst(c, "vpc", "/v1/subnets"):
        sid = it.get("id")
        if not sid:
            continue
        # subnet VIPs: a vip is pinned by its static_nat (the vpc_subnet_vip_nat_ip
        # leak, #84) and any connected ports. The list sub-endpoints (.../static-nat-ips,
        # .../connected-ports) 403 with "Action definition is not found" — that LIST
        # action isn't registered — but the vip SHOW response embeds both, and the
        # DELETE-by-id action IS defined (the provider's CreateSubnetVIPNATIp /
        # DeleteSubnetVIPNATIp). So read the ids from the vip body and delete by id.
        for vip in items(c.get(f"/v1/subnets/{sid}/vips", service="vpc").body):
            vipid = vip.get("id")
            if not vipid:
                continue
            vbody = c.get(f"/v1/subnets/{sid}/vips/{vipid}", service="vpc").body
            sv = vbody.get("subnet_vip", vbody) if isinstance(vbody, dict) else {}
            sv = sv if isinstance(sv, dict) else {}
            sn = sv.get("static_nat") or {}
            if isinstance(sn, dict) and sn.get("id"):
                delete(c, "vpc", f"/v1/subnets/{sid}/vips/{vipid}/static-nat-ips/{sn['id']}")
            for cp in sv.get("connected_ports") or []:
                if isinstance(cp, dict) and cp.get("id"):
                    delete(c, "vpc", f"/v1/subnets/{sid}/vips/{vipid}/connected-ports/{cp['id']}")
            if delete(c, "vpc", f"/v1/subnets/{sid}/vips/{vipid}") == 409:
                vd = c.get(f"/v1/subnets/{sid}/vips/{vipid}", service="vpc")
                print(f"  DIAG vip {vipid} still 409 after clearing static_nat/ports: {vd.body}")
        # A subnet in CREATING can't be deleted (409) until it settles to ACTIVE;
        # retry a few times, then dump its state so a truly-stuck one is visible.
        st = None
        for _ in range(6):
            st = delete(c, "vpc", f"/v1/subnets/{sid}")
            if st in (200, 202, 204, 404):
                n += 1; sids.append(sid); break
            if st == 409:
                time.sleep(20); continue
            break
        if st == 409:
            sd = c.get(f"/v1/subnets/{sid}", service="vpc")
            print(f"  DIAG subnet {sid} still 409: {sd.body}")
    for sid in sids:
        wait_gone(c, "vpc", f"/v1/subnets/{sid}")
    for it in lst(c, "vpc", "/v1/internet-gateways"):
        if it.get("id") and delete(c, "vpc", f"/v1/internet-gateways/{it['id']}"):
            n += 1; wait_gone(c, "vpc", f"/v1/internet-gateways/{it['id']}", 240, 15)
    for it in lst(c, "vpc", "/v1/vpcs"):
        vidx = it.get("id")
        for _ in range(6):
            st = delete(c, "vpc", f"/v1/vpcs/{vidx}")
            if st in (200, 202, 204, 404):
                n += 1; wait_gone(c, "vpc", f"/v1/vpcs/{vidx}"); break
            if st == 409:
                time.sleep(15); continue
            break
        else:
            # exhausted retries on 409: enumerate everything still pinned to this VPC
            # so the blocking child type (not yet handled above) is visible.
            print(f"  DIAG vpc {vidx} still 409 — remaining children:")
            for coll in ("/v1/subnets", "/v1/ports", "/v1/nat-gateways",
                         "/v1/internet-gateways", "/v1/private-nats", "/v1/vpc-endpoints"):
                for ch in items(c.get(coll, service="vpc").body):
                    if isinstance(ch, dict) and ch.get("vpc_id") == vidx:
                        print(f"  DIAG   {coll}: id={ch.get('id')} name={name_of(ch)} state={ch.get('state')}")
    # 9b. publicips again — deleting a vip's static_nat / an IGW frees its publicip,
    # which only becomes deletable now. (publicips have no name, so this only does
    # something under SWEEP_ALL; ATTACHED ones still in use are skipped by the API.)
    for it in lst(c, "vpc", "/v1/publicips"):
        if it.get("id") and delete(c, "vpc", f"/v1/publicips/{it['id']}"):
            n += 1
    # 10. resource groups + certs
    for it in lst(c, "resourcemanager", "/v1/resource-groups"):
        if it.get("id") and delete(c, "resourcemanager", f"/v1/resource-groups/{it['id']}"):
            n += 1
    for it in lst(c, "certificatemanager", "/v1/certificatemanager"):
        if it.get("id") and delete(c, "certificatemanager", f"/v1/certificatemanager/{it['id']}"):
            n += 1
    print(f"sweep_all done: {n} resource(s) deleted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# sweep 2026-06-05T02:44:20Z: clean leftover ske cluster rske472910 + verify leak-0 after pool runs

# sweep 2026-06-05T07:39:42Z: clear leftover bootstrap VPCs (pool sweep hit 5-VPC quota: "number(5) of VPCs exceeded")

# sweep 2026-06-05T07:54:06Z: second pass to clear the 409-blocked leftover VPC (free quota for 4-engine pool re-run)

# sweep 2026-06-05T18:26:09Z: clear bootstrap VPCs leaked by cancelled run #12 (cancel-in-progress now off)

# confirm 2026-06-05T19:07:46Z: post-#14 leak-0 verification sweep (expect "0 deleted")

# confirm 2026-06-05T19:13:55Z: second leak-0 verification pass (expect 0)

# confirm 2026-06-05T19:19:16Z: final leak-0 pass (8->7->5->2, expect 0)

# sweep 2026-06-06T08:32:07Z: clear leaked VPCs (peering 409 pairs) — 5-VPC quota exhausted

# retry 2026-06-06T08:41:09Z: transient framework-import failure on prior run

# converge 2026-06-06T08:57:57Z: 1 VPC still 409 (peering partner now freed) — second pass

# sweep 2026-06-06T09:33:36Z: clear peering leak from final discovery (issue #84)

# sweep 2026-06-07T09:32Z: 2nd pass after static_nat fix freed the #84 vip/igw/publicip
# and zznet LBs deleted async — clear the now-unblocked subnets + vpcs (e404e9e1, fa91b5, a5f229).
