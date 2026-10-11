#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?Missing GitHub token}"
: "${GH_REPO:?Missing GitHub repository}"
: "${RELEASE_TAG:?Missing release tag}"
: "${R2_ACCOUNT_ID:?Missing R2_ACCOUNT_ID variable}"
: "${R2_BUCKET_NAME:?Missing R2_BUCKET_NAME variable}"
: "${AWS_ACCESS_KEY_ID:?Missing R2_ACCESS_KEY_ID secret}"
: "${AWS_SECRET_ACCESS_KEY:?Missing R2_SECRET_ACCESS_KEY secret}"

if [[ ! "$RELEASE_TAG" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo 'Release tag must use vMAJOR.MINOR.PATCH.' >&2
  exit 1
fi

export AWS_DEFAULT_REGION=auto AWS_EC2_METADATA_DISABLED=true AWS_PAGER=''
case "${R2_JURISDICTION:-default}" in
  default) endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com" ;;
  eu) endpoint="https://${R2_ACCOUNT_ID}.eu.r2.cloudflarestorage.com" ;;
  *) echo 'R2_JURISDICTION must be default or eu.' >&2; exit 1 ;;
esac
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

gh release view "$RELEASE_TAG" --json isDraft,isPrerelease > release.json
if ! jq -e '.isDraft == false and .isPrerelease == false' release.json > /dev/null; then
  echo 'Only published stable releases can be mirrored.' >&2
  exit 1
fi
gh release download "$RELEASE_TAG" --pattern AXE-Resource-Installer.exe --pattern SHA256SUMS.txt
# Windows release manifests use CRLF. Keep the published bytes for the mirror,
# but normalize line endings for validation on Linux.
sed 's/\r$//' SHA256SUMS.txt > checksum.check
# Accept exactly the checksum for this executable, never paths from release metadata.
if ! grep -Eq '^[0-9a-fA-F]{64}  AXE-Resource-Installer\.exe$' checksum.check || [[ $(wc -l < checksum.check) -ne 1 ]]; then
  echo 'Invalid installer checksum manifest.' >&2
  exit 1
fi
sha256sum --check checksum.check

upload_assets() {
  local prefix="$1" cache_control="$2"
  aws s3 cp AXE-Resource-Installer.exe "s3://${R2_BUCKET_NAME}/${prefix}/AXE-Resource-Installer.exe" \
    --endpoint-url "$endpoint" --content-type application/octet-stream \
    --content-disposition 'attachment; filename="AXE-Resource-Installer.exe"' --cache-control "$cache_control" --only-show-errors
  aws s3 cp SHA256SUMS.txt "s3://${R2_BUCKET_NAME}/${prefix}/SHA256SUMS.txt" \
    --endpoint-url "$endpoint" --content-type text/plain \
    --content-disposition 'attachment; filename="SHA256SUMS.txt"' --cache-control "$cache_control" --only-show-errors
}

upload_assets "packages/resource-installer/${RELEASE_TAG}" 'public, max-age=31536000, immutable'
latest_tag=$(gh api "repos/${GH_REPO}/releases/latest" --jq .tag_name)
if [[ "$latest_tag" == "$RELEASE_TAG" ]]; then
  upload_assets packages 'public, max-age=300, must-revalidate'
  echo "Updated stable installer to ${RELEASE_TAG}."
else
  echo "Mirrored ${RELEASE_TAG}; stable installer remains at ${latest_tag}."
fi
