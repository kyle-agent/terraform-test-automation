#!/usr/bin/env python3
"""upload_image_to_obs.py -- stage a VM image in OBS and print its public URL.

The samsungcloudplatformv2_virtualserver_image resource registers a custom image
by fetching a URL (its `url` attribute). The platform's image-import service must
be able to GET that URL itself, so the image file has to live somewhere reachable
-- OBS (SCP Object Storage, S3-compatible) is the natural home.

This helper:
  1. resolves a local image file (or downloads one from --source-url),
  2. ensures an OBS bucket exists,
  3. uploads the image object,
  4. makes the object public-read (so the import service can fetch it
     unauthenticated), and
  5. prints the resulting public object URL.

Feed that URL to the fixture as TF_VAR_image_url:

    export TF_VAR_image_url="$(python3 scripts/upload_image_to_obs.py)"

With no flags it downloads the default tiny CirrOS qcow2 (a few MB), uploads it
to the default test bucket, and prints the public URL. Override any of
--source-url / --bucket / --key as needed.

Auth + endpoint reuse the same env contract as scripts/obs_bucket.py (the SCP
access/secret key pair). NOTHING is hardcoded:
  TF_VAR_obs_access_key / OBS_ACCESS_KEY
  TF_VAR_obs_secret_key / OBS_SECRET_KEY
  TF_VAR_obs_endpoint   / OBS_ENDPOINT   (default object-store.kr-west1.e...)

This is best-effort and meant to run in CI where OBS creds exist. See
docs/findings/virtualserver-image-obs.md for the tiny-image rationale.

The default image is a CirrOS qcow2 (a few MB), chosen because SCP is
OpenStack-based and CirrOS is the canonical tiny OpenStack-compatible test image
-- so it is the highest-probability accepted upload while keeping the download +
upload fast. This script does NOT run as part of `terraform validate`; it is
invoked explicitly in an integration job.
"""
import argparse
import os
import sys
import tempfile
import urllib.parse
import urllib.request

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

# Mirror obs_bucket.py so both scripts share one endpoint/region contract.
DEFAULT_ENDPOINT = "https://object-store.kr-west1.e.samsungsdscloud.com"

# CirrOS: the canonical tiny OpenStack test image (a few MB). SCP is
# OpenStack-based, so this is the highest-probability accepted import.
DEFAULT_SOURCE_URL = "https://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
# Test-prefixed bucket name so the existing OBS sweep (prefix "regr-obs-") can
# reclaim it; idempotently created if absent.
DEFAULT_BUCKET = "regr-obs-image"


def _env(*names, default=None):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    return default


def client():
    """Build the OBS S3 client. Same auth/region quirks as obs_bucket.py:
    region MUST be us-east-1 so boto3 omits CreateBucketConfiguration's
    LocationConstraint (OBS rejects any constraint); OBS ignores the signing
    region anyway. Path-style addressing avoids vhost DNS for the bucket."""
    ak = _env("TF_VAR_obs_access_key", "OBS_ACCESS_KEY")
    sk = _env("TF_VAR_obs_secret_key", "OBS_SECRET_KEY")
    ep = _env("TF_VAR_obs_endpoint", "OBS_ENDPOINT", default=DEFAULT_ENDPOINT)
    if not ak or not sk:
        sys.exit("upload_image_to_obs: missing OBS access/secret key in environment")
    return boto3.client(
        "s3",
        endpoint_url=ep,
        aws_access_key_id=ak,
        aws_secret_access_key=sk,
        region_name="us-east-1",
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 3}),
    ), ep


def _code(e):
    return e.response.get("Error", {}).get("Code", "") if isinstance(e, ClientError) else ""


def ensure_bucket(s3, bucket):
    """Return a USABLE bucket name. Reuse `bucket` if it already exists; else try to
    create it; if creation is forbidden (ForbidCreateBucketException — the OBS key
    can't create buckets), fall back to an EXISTING bucket discovered via list_buckets
    (the operator may have pre-created one). Exits only if nothing is usable.

    Returns the bucket name to actually upload into (may differ from `bucket` when a
    fallback is used)."""
    try:
        s3.head_bucket(Bucket=bucket)
        print(f"upload_image_to_obs: reusing existing bucket {bucket}", file=sys.stderr)
        return bucket
    except ClientError:
        pass  # not present / not headable -> attempt to create below
    try:
        s3.create_bucket(Bucket=bucket)
        print(f"upload_image_to_obs: created bucket {bucket}", file=sys.stderr)
        return bucket
    except ClientError as e:
        code = _code(e)
        if code in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists"):
            print(f"upload_image_to_obs: bucket {bucket} already exists (ok)", file=sys.stderr)
            return bucket
        if code not in ("ForbidCreateBucketException", "AccessDenied", "AllAccessDisabled"):
            raise
        # Creation forbidden for this key -> reuse a pre-created bucket if one exists.
        print(
            f"upload_image_to_obs: cannot create bucket {bucket} ({code}); "
            f"searching for an existing bucket to reuse...",
            file=sys.stderr,
        )
        try:
            existing = [b["Name"] for b in s3.list_buckets().get("Buckets", [])]
        except ClientError as le:
            existing = []
            print(f"upload_image_to_obs: list_buckets failed ({_code(le)})", file=sys.stderr)
        if bucket in existing:
            print(f"upload_image_to_obs: reusing existing bucket {bucket}", file=sys.stderr)
            return bucket
        if existing:
            chosen = existing[0]
            print(
                f"upload_image_to_obs: reusing existing bucket {chosen} (available: {existing})",
                file=sys.stderr,
            )
            return chosen
        sys.exit(
            f"upload_image_to_obs: cannot create bucket {bucket} ({code}) and no existing "
            f"bucket is visible; pre-create a writable bucket and pass it via --bucket / OBS_BUCKET."
        )


def resolve_image(local_path, source_url):
    """Return a path to a local image file. If source_url is given and no local
    file, download it to a temp file first. Returns (path, cleanup_path_or_None)."""
    if local_path:
        if not os.path.isfile(local_path):
            sys.exit(f"upload_image_to_obs: local image not found: {local_path}")
        return local_path, None
    if not source_url:
        sys.exit("upload_image_to_obs: provide --image PATH or --source-url URL")

    # Stream the (potentially ~600MB) download to a temp file rather than memory.
    suffix = os.path.splitext(urllib.parse.urlparse(source_url).path)[1] or ".img"
    fd, tmp = tempfile.mkstemp(suffix=suffix, prefix="obs-image-")
    os.close(fd)
    print(f"upload_image_to_obs: downloading {source_url} -> {tmp}", file=sys.stderr)
    try:
        with urllib.request.urlopen(source_url) as resp, open(tmp, "wb") as out:
            while True:
                chunk = resp.read(1024 * 1024)
                if not chunk:
                    break
                out.write(chunk)
    except Exception as e:  # noqa: BLE001 - best-effort helper, surface and clean up
        os.path.exists(tmp) and os.remove(tmp)
        sys.exit(f"upload_image_to_obs: download failed: {e}")
    return tmp, tmp


def upload(s3, bucket, key, path):
    """Upload the image and make it public-read. boto3's upload_file multipart-
    chunks large files automatically, which is what we want for a ~600MB qcow2."""
    size = os.path.getsize(path)
    print(
        f"upload_image_to_obs: uploading {path} ({size/1e6:.1f} MB) -> "
        f"s3://{bucket}/{key}",
        file=sys.stderr,
    )
    s3.upload_file(path, bucket, key)
    # Make the object world-readable so the platform import service can GET it
    # without OBS credentials. If the bucket/account disallows object ACLs this
    # may fail; a bucket policy or pre-signed URL is the fallback (see findings).
    try:
        s3.put_object_acl(Bucket=bucket, Key=key, ACL="public-read")
    except ClientError as e:
        print(
            f"upload_image_to_obs: WARNING could not set public-read ACL "
            f"({_code(e)}); object may not be fetchable by the import service. "
            f"Consider a bucket policy or a pre-signed URL.",
            file=sys.stderr,
        )


def public_url(endpoint, bucket, key, style="virtual"):
    """Public object URL for the staged image.

    - virtual-hosted (default): https://<bucket>.<host>/<key>
    - path-style:               https://<host>/<bucket>/<key>

    SCP's image-import rejected the path-style form with
    "Object Storage URL for the Image file is invalid" (the object uploads fine),
    so virtual-hosted is the default; override with --url-style path."""
    base = endpoint.rstrip("/")
    qkey = urllib.parse.quote(key)
    if style == "path":
        return f"{base}/{bucket}/{qkey}"
    p = urllib.parse.urlparse(base)
    return f"{p.scheme}://{bucket}.{p.netloc}/{qkey}"


def main(argv):
    ap = argparse.ArgumentParser(description="Upload a VM image to OBS and print its public URL.")
    ap.add_argument("--image", help="path to a local image file (qcow2)")
    ap.add_argument(
        "--source-url",
        default=DEFAULT_SOURCE_URL,
        help="download the image from this URL if --image is not given "
        f"(default: tiny CirrOS qcow2 {DEFAULT_SOURCE_URL})",
    )
    ap.add_argument(
        "--bucket",
        default=DEFAULT_BUCKET,
        help=f"OBS bucket to upload into, created if absent (default: {DEFAULT_BUCKET})",
    )
    ap.add_argument("--key", help="object key; defaults to the source/local filename")
    ap.add_argument(
        "--url-style",
        choices=["virtual", "path"],
        default="virtual",
        help="public URL form: virtual-hosted (<bucket>.<host>/<key>, default) or path "
        "(<host>/<bucket>/<key>). SCP image-import rejected path-style.",
    )
    args = ap.parse_args(argv[1:])

    s3, endpoint = client()

    path, cleanup = resolve_image(args.image, args.source_url)
    try:
        key = args.key or os.path.basename(
            args.image or urllib.parse.urlparse(args.source_url).path
        )
        if not key:
            sys.exit("upload_image_to_obs: could not derive object key; pass --key")

        bucket = ensure_bucket(s3, args.bucket)
        upload(s3, bucket, key, path)
        url = public_url(endpoint, bucket, key, args.url_style)
        # The URL goes to stdout ALONE so it can be captured into TF_VAR_image_url;
        # all status/logging above is on stderr.
        print(url)
    finally:
        if cleanup and os.path.exists(cleanup):
            os.remove(cleanup)


if __name__ == "__main__":
    main(sys.argv)
