# Switching the SCP test account

When integration testing moves to a different Samsung Cloud Platform (SCP) account,
update the GitHub secrets the workflows read. **No code changes are required** — the
workflows read auth URL, region, account id, and credentials entirely from secrets
(nothing account-specific is hardcoded in the workflow YAML).

All SCP-touching jobs declare `environment: scp-integration`, so set these as
**Environment secrets**: repo **Settings → Environments → `scp-integration` →
Environment secrets**. (Repo-level secrets of the same name also resolve, but the
environment is where this project keeps them.)

## 1. Required — provider credentials (used by every lane)

| Secret | Meaning | Replace when switching account? |
|---|---|---|
| `SCP_TF_ACCESS_KEY` | new account access key | ✅ always |
| `SCP_TF_SECRET_KEY` | new account secret key | ✅ always |
| `SCP_ACCOUNT_ID` | new account id | ✅ always |
| `SCP_TF_AUTH_URL` | IAM auth endpoint, e.g. `https://iam.x.samsungsdscloud.com/v1` | only if the new account uses a different environment/endpoint |
| `SCP_DEFAULT_REGION` | region, e.g. `kr-west1` | only if the new account is in a different region |

> The workflows export `SCP_TF_DEFAULT_REGION` (the name the provider reads) from the
> same `SCP_DEFAULT_REGION` secret, so you only set the region once.

## 2. Optional — pre-existing resource ids (`TEST_*`)

Used **only** by the standalone `capability-matrix.yml` (scheduled / manual dispatch)
and `dynamic-regression.yml`, for scenarios that bind to a resource that already
exists in the account. These are account-specific ids — repoint them at equivalents
in the new account, or leave them unset to skip those scenarios.

| Secret | Points at |
|---|---|
| `TEST_VPC_ID` | a pre-existing VPC |
| `TEST_SUBNET_ID` | a pre-existing subnet |
| `TEST_SECURITY_GROUP_ID` | a pre-existing security group |
| `TEST_DBAAS_ENGINE_VERSION_ID` | a DBaaS engine version id |
| `TEST_SERVER_TYPE_NAME` | a server-type name/code |
| `TEST_GPUNODE_ID` | a GPU node id |

> The **dependent-probe** and **cost-tiered regression** lanes do NOT need `TEST_*` —
> they bootstrap their own VPC / subnet / security group each run and tear it down.
> So the day-to-day lanes work with just section 1.

## 3. Leave as-is (not account-related)

- `GITHUB_TOKEN` — auto-provided by Actions.
- `PROVIDER_REPO_GH_TOKEN` — a GitHub PAT used to fetch the provider repo for the
  local provider mirror; unrelated to the SCP account.

## 4. After updating

- `scripts/setup_provider_mirror.sh` and the bootstrap image / server-type lookups are
  account-independent (public catalog) — no change needed.
- `cleanup_destroy/main.tf` still lists **old-account** leaked VPC ids; they simply
  no-op against the new account. Clear them when convenient.
- **Verify** with a cheap run: push a trivial change under `cleanup/**` to run the
  read-only `cleanup.yml` inventory (lists VPCs in the new account), or let the nightly
  `regression.yml` (cost-tiered, green+cheap) run — a green regression confirms the new
  account + secrets work end to end.

## Quick checklist

- [ ] `SCP_TF_ACCESS_KEY` (new)
- [ ] `SCP_TF_SECRET_KEY` (new)
- [ ] `SCP_ACCOUNT_ID` (new)
- [ ] `SCP_TF_AUTH_URL` (only if endpoint differs)
- [ ] `SCP_DEFAULT_REGION` (only if region differs)
- [ ] `TEST_*` (only if you run capability-matrix / dynamic-regression; otherwise skip)
- [ ] trigger read-only `cleanup.yml` or `regression.yml` to verify
