# virtualserver_image: registering a custom image via OBS

Scenario: `scenarios/virtualserver_image/main.tf`
Resource: `samsungcloudplatformv2_virtualserver_image`
Registry status at time of writing: **broken** -- "invalid OBS image URL (needs real image file)".

## What the fixture does

The fixture registers a custom VM image from a URL. In the provider, the
url-based create path is selected when `instance_id` is unset: `CreateImage`
asks the platform to **fetch the file at `url` itself** and import it as a
custom image (disk_format `qcow2`, container_format `bare`, os_distro `ubuntu`).
The provider then polls the new image until `Status` becomes `active`.

Schema facts (from `image.go` in the provider):
- Only `name` is **Required**.
- `url`, `disk_format`, `container_format`, `os_distro`, `min_disk`, `min_ram`,
  `visibility`, `protected`, `instance_id`, `tags` are **Optional**
  (most are Optional+Computed).
- There are **no client-side enum validators** on `disk_format` /
  `container_format` / `os_distro` / `visibility`; values are validated
  **server-side at create time**. So `terraform validate` passes regardless of
  the values, but a bad/unreachable `url` only fails at `apply`.
- `url` and `instance_id` are the two mutually exclusive create modes; this
  fixture leaves `instance_id` unset to use the url path.

## Approach

```
local/remote qcow2  --upload-->  OBS bucket (public-read object)
                                        |
                                        v
                        public object URL  ==> TF_VAR_image_url
                                        |
                                        v
        provider CreateImage(url=...) fetches the file and imports the image
```

1. Stage the image file in OBS (S3-compatible SCP Object Storage).
2. Make the object publicly readable so the platform's image-import service can
   GET it without OBS credentials.
3. Pass the resulting object URL as `TF_VAR_image_url`.
4. `terraform apply` registers the image; the provider polls to `active`.

`scripts/upload_image_to_obs.py` automates steps 1-3.

## Running the upload helper

Auth/endpoint follow the same env contract as `scripts/obs_bucket.py` (the SCP
access/secret key pair). Nothing is hardcoded:

- `TF_VAR_obs_access_key` / `OBS_ACCESS_KEY`
- `TF_VAR_obs_secret_key` / `OBS_SECRET_KEY`
- `TF_VAR_obs_endpoint` / `OBS_ENDPOINT` (default
  `https://object-store.kr-west1.e.samsungsdscloud.com`)

Download-and-upload an Ubuntu cloud image, capturing the URL:

```bash
export TF_VAR_image_url="$(python3 scripts/upload_image_to_obs.py \
    --source-url https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img \
    --bucket regr-vsimage \
    --key ubuntu-22.04.qcow2)"
```

Or upload a file already on disk:

```bash
export TF_VAR_image_url="$(python3 scripts/upload_image_to_obs.py \
    --image ./ubuntu-22.04.qcow2 --bucket regr-vsimage)"
```

The helper prints **only the public URL to stdout** (status/progress goes to
stderr), so it is safe to capture into `TF_VAR_image_url`. It creates the bucket
if absent, multipart-uploads large files, and sets a `public-read` ACL. If
object ACLs are disallowed it warns and continues -- a bucket policy or a
pre-signed URL is the fallback.

Then validate/apply the scenario:

```bash
cd scenarios/virtualserver_image
terraform init -input=false
terraform validate          # passes offline with the dummy default too
terraform apply -auto-approve
```

## The ~600MB vs tiny-image tradeoff (the real blocker)

A real Ubuntu cloud qcow2 is **~600MB**. That means:

- A heavy upload to OBS and a non-trivial platform-side import (download +
  validation + conversion) on every test run -- slow and not free.
- Storage and image-registration costs accumulate if runs are frequent.

The tempting shortcut is a **tiny synthetic qcow2** (a few KB/MB created with
`qemu-img create`). The risk:

- The platform's image-import validation may **reject** a synthetic/empty qcow2
  (no valid filesystem / partition table / bootable contents), or accept it but
  leave it unusable. The exact validation behaviour is **not documented** and
  must be probed empirically.

So there is no confirmed cheap path yet: the only known-good image is the big
real one, and the cheap synthetic image is unproven and may be rejected.

## Recommendation

**Keep this scenario blocked-with-findings for now; do not flip it to untested.**

The fixture itself is now clean and fully schema-valid (validates offline with a
dummy URL), and the upload tooling is ready. But flipping to *untested* (meaning
"applies cleanly in CI") requires a **real apply against the platform**, which
in turn requires either the ~600MB upload or proof that a tiny image is
accepted. Neither has been exercised here.

Concrete next step, **timeboxed** (suggest ~1-2h in a CI integration job):

1. Run `scripts/upload_image_to_obs.py` with a small synthetic qcow2
   (`qemu-img create -f qcow2 tiny.qcow2 1G`) into OBS; set `TF_VAR_image_url`;
   `terraform apply`.
2. If the platform accepts it and reaches `active` -> flip to untested using the
   tiny image (cheap, fast, repeatable).
3. If the platform **rejects** small/synthetic images, fall back to a single
   real cloud-image upload to confirm the path works end-to-end, then decide
   whether the per-run cost is acceptable.
4. If neither is viable within the timebox, **mark the scenario blocked** and
   record the specific rejection error here so the next attempt starts from the
   known failure mode rather than re-discovering it.
