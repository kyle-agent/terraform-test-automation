#!/usr/bin/env python3
"""obs_bucket.py -- minimal lifecycle for an SCP Object Storage (S3-compatible) bucket.

SCP Object Storage speaks S3, so we create/delete the bucket the network-logging
storage fixture needs with a tiny boto3 S3 client. We do NOT use the terraform
aws_s3_bucket resource: its post-create Read fans out to GetBucketPolicy / ACL /
CORS / lifecycle and only tolerates AWS's exact "not configured" error codes; OBS
answers GetBucketPolicy with a generic `404 Not Found: Policy does not exist`, which
the provider treats as a hard error. boto3's CreateBucket/DeleteBucket are single,
well-behaved calls, so this script is the reliable path.

region MUST be us-east-1: for any other region boto3 adds
CreateBucketConfiguration.LocationConstraint=<region>, which OBS rejects
("InvalidLocationConstraint"). OBS does not enforce the SigV4 signing region.

Credentials + endpoint come from the environment (same SCP access/secret key):
  TF_VAR_obs_access_key / OBS_ACCESS_KEY
  TF_VAR_obs_secret_key / OBS_SECRET_KEY
  TF_VAR_obs_endpoint   / OBS_ENDPOINT   (default object-store.kr-west1.e...)

Usage:
  obs_bucket.py create <bucket>     # idempotent (BucketAlreadyOwnedByYou is ok)
  obs_bucket.py delete <bucket>     # empty then delete; missing bucket is ok
  obs_bucket.py sweep  <prefix>...  # delete every bucket whose name starts with a prefix
"""
import os
import sys

import boto3
from botocore.config import Config
from botocore.exceptions import ClientError

DEFAULT_ENDPOINT = "https://object-store.kr-west1.e.samsungsdscloud.com"


def _env(*names, default=None):
    for n in names:
        v = os.environ.get(n)
        if v:
            return v
    return default


def client():
    ak = _env("TF_VAR_obs_access_key", "OBS_ACCESS_KEY")
    sk = _env("TF_VAR_obs_secret_key", "OBS_SECRET_KEY")
    ep = _env("TF_VAR_obs_endpoint", "OBS_ENDPOINT", default=DEFAULT_ENDPOINT)
    if not ak or not sk:
        sys.exit("obs_bucket: missing OBS access/secret key in environment")
    return boto3.client(
        "s3",
        endpoint_url=ep,
        aws_access_key_id=ak,
        aws_secret_access_key=sk,
        region_name="us-east-1",  # omit LocationConstraint; OBS ignores signing region
        config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 3}),
    )


def _code(e):
    return e.response.get("Error", {}).get("Code", "") if isinstance(e, ClientError) else ""


def create(s3, bucket):
    try:
        s3.create_bucket(Bucket=bucket)
        print(f"obs_bucket: created {bucket}")
    except ClientError as e:
        if _code(e) in ("BucketAlreadyOwnedByYou", "BucketAlreadyExists"):
            print(f"obs_bucket: {bucket} already exists (ok)")
        else:
            raise


def delete(s3, bucket):
    try:
        # empty first: network-logging may have dropped log objects in here
        token = None
        while True:
            kw = {"Bucket": bucket, **({"ContinuationToken": token} if token else {})}
            resp = s3.list_objects_v2(**kw)
            objs = [{"Key": o["Key"]} for o in resp.get("Contents", [])]
            if objs:
                s3.delete_objects(Bucket=bucket, Delete={"Objects": objs})
            if resp.get("IsTruncated"):
                token = resp.get("NextContinuationToken")
            else:
                break
        s3.delete_bucket(Bucket=bucket)
        print(f"obs_bucket: deleted {bucket}")
    except ClientError as e:
        if _code(e) in ("NoSuchBucket", "404", "NotFound"):
            print(f"obs_bucket: {bucket} already gone (ok)")
        else:
            raise


def sweep(s3, prefixes, min_age_hours=0.0):
    """Delete every bucket whose name starts with a prefix. With min_age_hours>0,
    only buckets older than that are deleted -- a TTL guard so a scheduled sweep can
    never race a concurrent test that just created its bucket."""
    import datetime
    try:
        buckets = s3.list_buckets().get("Buckets", [])
    except ClientError as e:
        print(f"obs_bucket: sweep list_buckets failed ({_code(e)}); skipping")
        return
    now = datetime.datetime.now(datetime.timezone.utc)
    for b in buckets:
        name = b["Name"]
        if not any(name.startswith(p) for p in prefixes):
            continue
        if min_age_hours > 0:
            created = b.get("CreationDate")
            if created and (now - created).total_seconds() < min_age_hours * 3600:
                print(f"obs_bucket: skipping {name} (younger than {min_age_hours}h)")
                continue
        print(f"obs_bucket: sweeping stale {name}")
        try:
            delete(s3, name)
        except ClientError as e:
            print(f"obs_bucket: sweep could not delete {name}: {_code(e)}")


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__)
    cmd = argv[1]
    s3 = client()
    if cmd == "create":
        create(s3, argv[2])
    elif cmd == "delete":
        delete(s3, argv[2])
    elif cmd == "sweep":
        # SWEEP_MIN_AGE_HOURS mirrors the SCP reaper's TTL guard: 0 for immediate
        # (pre-test cleanup), >0 for scheduled sweeps that must not race live tests.
        min_age = float(os.environ.get("SWEEP_MIN_AGE_HOURS", "0") or "0")
        sweep(s3, argv[2:] or ["regrnetlog", "regr-obs-"], min_age_hours=min_age)
    else:
        sys.exit(f"obs_bucket: unknown command {cmd!r}")


if __name__ == "__main__":
    main(sys.argv)
