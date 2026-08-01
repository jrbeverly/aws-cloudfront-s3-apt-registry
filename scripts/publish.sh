#!/usr/bin/env bash
set -euo pipefail

# Publishes one trivial .deb and the minimum metadata apt needs to install it
# as static objects in the private S3 bucket. No repository server anywhere;
# apt consumes the objects directly, e.g.:
#   deb [trusted=yes] https://<cloudfront-domain>/ stable main
# Outputs (staged under repository/, then synced to the bucket root):
#   pool/stable/main/h/hello-lab/hello-lab_1.0.0_amd64.deb
#   dists/stable/main/binary-amd64/Packages
#   dists/stable/main/binary-amd64/Packages.gz
#   dists/stable/Release

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="${ROOT_DIR}/repository"

NAME="hello-lab"
VERSION="1.0.0"
ARCH="amd64"
SUITE="stable"
COMPONENT="main"

POOL_DIR="${REPO_DIR}/pool/${SUITE}/${COMPONENT}/h/${NAME}"
BINARY_DIR="${REPO_DIR}/dists/${SUITE}/${COMPONENT}/binary-${ARCH}"
DEB_FILE="${POOL_DIR}/${NAME}_${VERSION}_${ARCH}.deb"

rm -rf "${REPO_DIR}"
mkdir -p "${POOL_DIR}" "${BINARY_DIR}"

# build the single trivial .deb
PKG_ROOT="$(mktemp -d)"
mkdir -p "${PKG_ROOT}/DEBIAN" "${PKG_ROOT}/usr/share/${NAME}"
cat > "${PKG_ROOT}/DEBIAN/control" <<EOF
Package: ${NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: Local Lab <lab@example.invalid>
Description: Trivial package proving static APT repository publishing
EOF
echo "installed from a static S3 repository" > "${PKG_ROOT}/usr/share/${NAME}/message.txt"
dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${DEB_FILE}"
rm -rf "${PKG_ROOT}"

# Packages index for stable/main, Filename paths relative to the repo root
(
  cd "${REPO_DIR}"
  dpkg-scanpackages --arch "${ARCH}" "pool/${SUITE}/${COMPONENT}" /dev/null > "${BINARY_DIR}/Packages"
  gzip -9c "${BINARY_DIR}/Packages" > "${BINARY_DIR}/Packages.gz"
)

# unsigned Release describing the one component; consumers opt out with [trusted=yes]
cat > "${REPO_DIR}/dists/${SUITE}/Release" <<EOF
Origin: Local Lab
Label: Local Lab
Suite: ${SUITE}
Codename: ${SUITE}
Components: ${COMPONENT}
Architectures: ${ARCH}
Date: $(date -Ru)
SHA256:
 $(sha256sum "${BINARY_DIR}/Packages" | cut -d' ' -f1) $(stat -c %s "${BINARY_DIR}/Packages") ${COMPONENT}/binary-${ARCH}/Packages
 $(sha256sum "${BINARY_DIR}/Packages.gz" | cut -d' ' -f1) $(stat -c %s "${BINARY_DIR}/Packages.gz") ${COMPONENT}/binary-${ARCH}/Packages.gz
EOF

# publish the static tree into the private bucket named in the Terraform output
cd "${ROOT_DIR}"
BUCKET="$(terraform output -raw bucket_name)"
aws s3 sync "${REPO_DIR}" "s3://${BUCKET}"
