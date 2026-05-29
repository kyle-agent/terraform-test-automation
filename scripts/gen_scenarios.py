#!/usr/bin/env python3
"""Generate minimal, schema-valid scenarios for not-yet-covered provider
resources, then validate each against the real provider. Only scenarios that
pass `terraform validate` are kept.

Capabilities:
  - scalar required attrs (string/number/bool/map/list-of-string)
  - required NESTED blocks (single/list/set), filled recursively
  - learns enum values from `terraform validate -json` errors ("must be one
    of ...") and retries, so resources guarded by OneOf validators are covered
  - a few name-based heuristics (version/cidr/ip)

Resources that still fail after the retry budget (e.g. opaque regex validators
or cross-field rules) are skipped — never committed broken.

Requires a terraform binary on /tmp and a provider filesystem mirror configured
via TF_CLI_CONFIG_FILE (see docs/dynamic-workflow.md). The committed artifacts
are the validated scenarios, not this dev-time script."""
import json, os, re, subprocess, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = "/tmp/schema.json"
SCEN = os.path.join(ROOT, "scenarios")
TF = "/tmp/terraform"

HDR = '''terraform {
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
# tests/schema validate sweep; extend with integration assertions to promote.
'''

def short(r):
    return r[len("samsungcloudplatformv2_"):]

def scalar(name, t, overrides):
    if name in overrides:
        v = overrides[name]
        return f'"{v}"' if isinstance(v, str) else str(v)
    if t == "bool":
        return "false"
    if t == "number":
        return "1"
    if isinstance(t, list):
        kind = t[0]
        if kind == "map":
            return '{ tf = "terraform" }'
        if kind in ("list", "set"):
            if t[1] == "string":
                if re.search(r"ip|cidr|address", name):
                    return '["10.0.0.0/24"]'
                return '["regr"]'
            return None
        return None
    if t == "string":
        if "version" in name:
            return '"v1.30.1"'
        if name.endswith("_id") or name == "id":
            return '"00000000-0000-0000-0000-000000000000"'
        if "cidr" in name:
            return '"10.0.0.0/24"'
        if re.search(r"ip|address", name):
            return '"10.0.0.10"'
        return '"regr"'
    return None

def render_attr(name, spec, overrides, indent):
    """Return HCL literal for one attribute, or None if unrepresentable."""
    pad = "  " * indent
    if spec.get("nested_type"):
        nt = spec["nested_type"]
        mode = nt.get("nesting_mode", "single")
        inner = render_object(nt["attributes"], overrides, indent + 1)
        if inner is None:
            return None
        if mode in ("list", "set"):
            return "[\n" + "  " * (indent + 1) + inner + "\n" + pad + "]"
        return inner
    return scalar(name, spec.get("type"), overrides)

def render_object(attrs, overrides, indent):
    """Render a {{...}} object containing all REQUIRED attributes."""
    pad = "  " * indent
    lines = []
    for k, v in attrs.items():
        if not v.get("required"):
            continue
        lit = render_attr(k, v, overrides, indent)
        if lit is None:
            return None
        lines.append(f"{pad}  {k} = {lit}")
    body = "\n".join(lines)
    return "{\n" + body + "\n" + pad + "}" if body else "{}"

def gen(rtype, attrs, overrides):
    lines = []
    for k, v in attrs.items():
        if not v.get("required"):
            continue
        lit = render_attr(k, v, overrides, 1)
        if lit is None:
            return None
        lines.append(f"  {k} = {lit}")
    return f'{HDR}\nresource "{rtype}" "regr" {{\n' + "\n".join(lines) + "\n}\n"

ENUM_RE = re.compile(r'must be one of[:\s]+\[([^\]]+)\]', re.I)
ATTR_RE = re.compile(r'Attribute\s+"?([a-z0-9_]+)"?', re.I)

def learn_enums(diags, overrides):
    """Update overrides from OneOf validator errors. Returns True if learned."""
    learned = False
    for d in diags:
        text = (d.get("summary", "") + " " + d.get("detail", ""))
        m = ENUM_RE.search(text)
        if not m:
            continue
        vals = re.findall(r'"([^"]+)"', m.group(1)) or \
               [x.strip() for x in m.group(1).split() if x.strip()]
        if not vals:
            continue
        # attribute name: prefer the diagnostic address tail, else "Attribute X"
        attr = None
        am = ATTR_RE.search(text)
        if am:
            attr = am.group(1)
        elif d.get("address"):
            attr = d["address"].split(".")[-1]
        if attr and attr not in overrides:
            overrides[attr] = vals[0]
            learned = True
    return learned

def clean(dirpath):
    for d in (".terraform", ".terraform.lock.hcl"):
        p = os.path.join(dirpath, d)
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        elif os.path.exists(p):
            os.remove(p)

def validate(dirpath):
    env = dict(os.environ, PATH="/tmp:" + os.environ["PATH"],
               TF_CLI_CONFIG_FILE="/tmp/.terraformrc")
    clean(dirpath)
    i = subprocess.run([TF, "init", "-backend=false", "-no-color", "-input=false"],
                       cwd=dirpath, env=env, capture_output=True, text=True)
    if i.returncode != 0:
        return False, [], i.stdout + i.stderr
    v = subprocess.run([TF, "validate", "-no-color", "-json"],
                       cwd=dirpath, env=env, capture_output=True, text=True)
    try:
        j = json.loads(v.stdout)
    except Exception:
        return False, [], v.stdout + v.stderr
    return j.get("valid", False) and j.get("error_count", 0) == 0, j.get("diagnostics", []), v.stdout

def main():
    schema = json.load(open(SCHEMA))
    res = next(iter(schema["provider_schemas"].values()))["resource_schemas"]
    covered = set()
    decl = re.compile(r'resource\s+"(samsungcloudplatformv2_[a-z0-9_]+)"')
    for d in os.listdir(SCEN):
        p = os.path.join(SCEN, d)
        if os.path.isdir(p):
            for f in os.listdir(p):
                if f.endswith(".tf"):
                    covered.update(decl.findall(open(os.path.join(p, f)).read()))
    kept, skipped, failed = [], [], []
    for rtype in sorted(res):
        if rtype in covered:
            continue
        attrs = res[rtype]["block"]["attributes"]
        overrides, ok, log = {}, False, ""
        name = short(rtype)
        dirpath = os.path.join(SCEN, name)
        for _ in range(8):  # retry budget for enum learning
            hcl = gen(rtype, attrs, overrides)
            if hcl is None:
                skipped.append(rtype)
                break
            os.makedirs(dirpath, exist_ok=True)
            open(os.path.join(dirpath, "main.tf"), "w").write(hcl)
            ok, diags, log = validate(dirpath)
            if ok:
                break
            if not learn_enums(diags, overrides):
                break  # no further progress possible
        clean(dirpath)
        if hcl is None:
            continue
        if ok:
            kept.append(rtype)
        else:
            last = ""
            for ln in log.strip().splitlines()[::-1]:
                if ln.strip():
                    last = ln.strip()[:120]
                    break
            failed.append((rtype, last))
            shutil.rmtree(dirpath, ignore_errors=True)
    print(f"KEPT ({len(kept)}): " + ", ".join(short(x) for x in kept))
    print(f"SKIPPED unrepresentable ({len(skipped)}): " + ", ".join(short(x) for x in skipped))
    print(f"FAILED validate ({len(failed)}):")
    for r, why in failed:
        print(f"  {short(r)}: {why}")

if __name__ == "__main__":
    main()
