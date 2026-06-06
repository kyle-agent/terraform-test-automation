#!/usr/bin/env bash
# setup_provider_mirror.sh
#
# Make `terraform init` work even when registry.terraform.io is unreachable
# (locked-down CI networks return 403). GitHub releases ARE reachable, so we
# download the provider plugin from the project's GitHub releases and configure
# a Terraform *filesystem mirror* pointing at it. Subsequent steps in the same
# job pick this up via TF_CLI_CONFIG_FILE (exported to $GITHUB_ENV).
#
# This is best-effort: if the download fails we leave Terraform's default
# (direct registry) behavior untouched rather than breaking the run, so the
# job still works in environments that CAN reach the registry.
#
# Env:
#   SCP_PROVIDER_VERSION  pin a version (e.g. 3.3.1); default: latest GitHub release
#   MIRROR_DIR            where to stage the mirror; default: $RUNNER_TEMP/tfmirror
#
# Usage (in a workflow step, after checkout):
#   - run: scripts/setup_provider_mirror.sh

set -euo pipefail

REPO="SamsungSDSCloud/terraform-provider-samsungcloudplatformv2"
NS="samsungsdscloud"     # registry namespace is lower-cased on disk
TYPE="samsungcloudplatformv2"
OS_ARCH="linux_amd64"

MIRROR_DIR="${MIRROR_DIR:-${RUNNER_TEMP:-/tmp}/tfmirror}"
DEST="${MIRROR_DIR}/registry.terraform.io/${NS}/${TYPE}"

# Resolve the version: explicit pin, else latest GitHub release tag, else a
# known-good fallback so the script never hard-fails on a transient API hiccup.
VER="${SCP_PROVIDER_VERSION:-}"
if [ -z "$VER" ]; then
  VER="$(curl -fsSL --max-time 30 \
    "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v?[0-9.]+"' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
fi
VER="${VER:-3.3.1}"

ASSET="terraform-provider-${TYPE}_${VER}_${OS_ARCH}.zip"
URL="https://github.com/${REPO}/releases/download/v${VER}/${ASSET}"

echo "Provider mirror: ${TYPE} v${VER}"
echo "  source: ${URL}"
echo "  dest:   ${DEST}"

mkdir -p "$DEST"
if ! curl -fsSL --max-time 180 -o "${DEST}/${ASSET}" "$URL"; then
  echo "WARNING: could not download provider plugin; leaving direct registry behavior."
  echo "         (terraform init will use registry.terraform.io as usual.)"
  rm -f "${DEST}/${ASSET}" 2>/dev/null || true
  exit 0
fi

# Packed filesystem-mirror layout: the .zip sits in MIRROR_DIR/HOST/NS/TYPE/,
# so the mirror `path` is MIRROR_DIR (the dir that holds "registry.terraform.io").
RC="${MIRROR_DIR}/terraformrc"
# Optionally also mirror the hashicorp/aws provider (for OBS S3 fixtures: SCP
# Object Storage is S3-compatible, so aws_s3_bucket against the object-store
# endpoint creates buckets with the same keys). Best-effort, from GitHub releases
# (registry.terraform.io is blocked in CI). Enable with MIRROR_AWS=1.
AWS_INCLUDE=""
if [ "${MIRROR_AWS:-0}" = "1" ]; then
  AWSVER="${AWS_PROVIDER_VERSION:-5.80.0}"
  AWS_DEST="${MIRROR_DIR}/registry.terraform.io/hashicorp/aws"
  AWS_ASSET="terraform-provider-aws_${AWSVER}_${OS_ARCH}.zip"
  AWS_URL="https://github.com/hashicorp/terraform-provider-aws/releases/download/v${AWSVER}/${AWS_ASSET}"
  echo "Provider mirror: aws v${AWSVER}"
  echo "  source: ${AWS_URL}"
  mkdir -p "$AWS_DEST"
  if curl -fsSL --max-time 300 -o "${AWS_DEST}/${AWS_ASSET}" "$AWS_URL"; then
    AWS_INCLUDE=', "registry.terraform.io/hashicorp/aws"'
    echo "  aws provider mirrored."
  else
    echo "  WARNING: could not download aws provider; OBS S3 fixtures will fail init."
    rm -f "${AWS_DEST}/${AWS_ASSET}" 2>/dev/null || true
  fi
fi

cat > "$RC" <<EOF
provider_installation {
  filesystem_mirror {
    path    = "${MIRROR_DIR}"
    include = ["registry.terraform.io/${NS}/${TYPE}"${AWS_INCLUDE}]
  }
  direct {
    exclude = ["registry.terraform.io/${NS}/${TYPE}"${AWS_INCLUDE}]
  }
}
EOF

echo "TF_CLI_CONFIG_FILE=${RC}" >> "${GITHUB_ENV:-/dev/stdout}"
echo "Provider mirror configured (TF_CLI_CONFIG_FILE=${RC})."
