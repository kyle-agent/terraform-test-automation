#!/usr/bin/env python3
"""Generate minimal, schema-valid scenarios for not-yet-covered provider
resources, then validate each against the real provider. Only scenarios that
pass `terraform validate` are kept. Resources with required *nested* blocks are
skipped (too complex to auto-generate safely)."""
import json, os, re, subprocess, sys, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = "/tmp/schema.json"
SCEN = os.path.join(ROOT, "scenarios")

PROVIDER_HDR = '''terraform {
  required_version = ">= 1.6"
  required_providers {
    samsungcloudplatformv2 = {
      source  = "SamsungSDSCloud/samsungcloudplatformv2"
      version = ">= 0.0.1"
    }
  }
}

provider "samsungcloudplatformv2" {}

# AUTO-GENERATED minimal coverage fixture (scripts/gen_scenarios.py).
# Validated against the real provider schema. Exercised in dry-run by the
# tests/schema validate sweep; extend with integration assertions as needed.
'''

def short(rtype):  # samsungcloudplatformv2_vpc_internet_gateway -> vpc_internet_gateway
    return rtype[len("samsungcloudplatformv2_"):]

def placeholder(name, t):
    """Return an HCL literal for a required attribute of scalar/simple type."""
    if t == "bool":
        return "false"
    if t == "number":
        return "100"
    if isinstance(t, list):
        kind = t[0]
        if kind == "map":
            return '{ tf = "terraform" }'
        if kind in ("list", "set"):
            inner = t[1]
            if inner == "string":
                # cidr-ish guess for ip/cidr/address fields
                if re.search(r"ip|cidr|address", name):
                    return '["10.0.0.0/24"]'
                return '["regr"]'
            return None  # nested list of objects -> too complex
        return None
    if t == "string":
        if name.endswith("_id") or name == "id":
            return '"00000000-0000-0000-0000-000000000000"'
        if "cidr" in name:
            return '"10.0.0.0/24"'
        if re.search(r"ip|address", name):
            return '"10.0.0.10"'
        return '"regr"'
    return None

def gen(rtype, attrs):
    lines = []
    for k, v in attrs.items():
        if not v.get("required"):
            continue
        if v.get("nested_type"):
            return None  # required nested block -> skip resource
        lit = placeholder(k, v.get("type"))
        if lit is None:
            return None  # can't represent -> skip
        lines.append(f"  {k} = {lit}")
    body = "\n".join(lines)
    return f'{PROVIDER_HDR}\nresource "{rtype}" "regr" {{\n{body}\n}}\n'

def validate(dirpath):
    env = dict(os.environ, PATH="/tmp:" + os.environ["PATH"],
               TF_CLI_CONFIG_FILE="/tmp/.terraformrc")
    for d in (".terraform", ".terraform.lock.hcl"):
        p = os.path.join(dirpath, d)
        shutil.rmtree(p, ignore_errors=True) if os.path.isdir(p) else (os.path.exists(p) and os.remove(p))
    i = subprocess.run(["/tmp/terraform","init","-backend=false","-no-color","-input=false"],
                       cwd=dirpath, env=env, capture_output=True, text=True)
    if i.returncode != 0:
        return False, i.stdout + i.stderr
    v = subprocess.run(["/tmp/terraform","validate","-no-color"],
                       cwd=dirpath, env=env, capture_output=True, text=True)
    return v.returncode == 0, v.stdout + v.stderr

def main():
    schema = json.load(open(SCHEMA))
    res = next(iter(schema["provider_schemas"].values()))["resource_schemas"]
    covered = set()
    decl = re.compile(r'resource\s+"(samsungcloudplatformv2_[a-z0-9_]+)"')
    for d in os.listdir(SCEN):
        p = os.path.join(SCEN, d)
        if not os.path.isdir(p):
            continue
        for f in os.listdir(p):
            if f.endswith(".tf"):
                covered.update(decl.findall(open(os.path.join(p, f)).read()))
    kept, skipped, failed = [], [], []
    for rtype in sorted(res):
        if rtype in covered:
            continue
        hcl = gen(rtype, res[rtype]["block"]["attributes"])
        if hcl is None:
            skipped.append(rtype); continue
        name = short(rtype)
        dirpath = os.path.join(SCEN, name)
        os.makedirs(dirpath, exist_ok=True)
        open(os.path.join(dirpath, "main.tf"), "w").write(hcl)
        ok, log = validate(dirpath)
        if ok:
            kept.append(rtype)
        else:
            failed.append((rtype, log.strip().splitlines()[-1] if log.strip() else "?"))
            shutil.rmtree(dirpath, ignore_errors=True)
        # tidy terraform working files in kept dirs
        for d in (".terraform", ".terraform.lock.hcl"):
            pp = os.path.join(dirpath, d)
            if os.path.isdir(pp): shutil.rmtree(pp, ignore_errors=True)
            elif os.path.exists(pp): os.remove(pp)
    print(f"KEPT ({len(kept)}): " + ", ".join(short(x) for x in kept))
    print(f"SKIPPED nested/complex ({len(skipped)})")
    print(f"FAILED validate ({len(failed)}):")
    for r, why in failed:
        print(f"  {short(r)}: {why}")

if __name__ == "__main__":
    main()
