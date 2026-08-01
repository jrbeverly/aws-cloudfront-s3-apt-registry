#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" == "in-container" ]]; then
  DOMAIN="${CLOUDFRONT_DOMAIN:?inject CLOUDFRONT_DOMAIN from terraform output}"
  BUCKET="${S3_BUCKET:?inject S3_BUCKET from terraform output}"
  CERTS="/etc/apt/certs"

  # only the private repository is under test, not the Ubuntu archive
  rm -f /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources

  # apt methods drop privileges to _apt, so install the mounted certs readable
  mkdir -p /etc/apt/mtls
  cp "${CERTS}/dev/client.pem" /etc/apt/mtls/client.pem
  cp "${CERTS}/dev/client.key" /etc/apt/mtls/client.key
  chown _apt: /etc/apt/mtls/client.pem /etc/apt/mtls/client.key
  chmod 600 /etc/apt/mtls/client.key

  echo "== positive: apt update + apt install over ${DOMAIN} with client certificate"
  cat > /etc/apt/apt.conf.d/99mtls <<EOF
Acquire::https::${DOMAIN}::SslCert "/etc/apt/mtls/client.pem";
Acquire::https::${DOMAIN}::SslKey "/etc/apt/mtls/client.key";
EOF
  echo "deb [trusted=yes] https://${DOMAIN}/ stable main" > /etc/apt/sources.list.d/lab.list
  apt-get update
  apt-get install -y hello-lab
  cat /usr/share/hello-lab/message.txt

  echo
  echo "== negative: same request without the client certificate"
  rm /etc/apt/apt.conf.d/99mtls
  UPDATE_OUTPUT="$(apt-get update 2>&1 || true)"
  echo "${UPDATE_OUTPUT}"
  if grep -q "Failed to fetch" <<<"${UPDATE_OUTPUT}"; then
    echo "OK: edge refused the unauthenticated apt request"
  else
    echo "FAIL: apt update without a client certificate did not fail"
    exit 1
  fi

  if curl -fsS "https://${DOMAIN}/dists/stable/Release"; then
    echo "FAIL: TLS handshake without a client certificate succeeded"
    exit 1
  fi
  echo "OK: edge refused the unauthenticated TLS handshake"

  echo
  echo "== origin: direct S3 fetch bypassing CloudFront"
  STATUS="$(curl -sS -w '%{http_code}' -o /tmp/s3-response "https://${BUCKET}.s3.amazonaws.com/dists/stable/Release")"
  cat /tmp/s3-response
  echo
  if [[ "${STATUS}" != "403" ]]; then
    echo "FAIL: direct S3 fetch returned HTTP ${STATUS}, expected 403"
    exit 1
  fi
  echo "OK: direct S3 fetch denied (HTTP 403)"

  echo
  echo "== all checks passed"
  exit 0
fi

# host: inject the CloudFront domain and bucket from Terraform outputs
cd "${ROOT_DIR}"
CLOUDFRONT_DOMAIN="$(terraform output -raw cloudfront_domain)"
S3_BUCKET="$(terraform output -raw bucket_name)"

docker build -t apt-mtls-validation "${ROOT_DIR}/docker"

docker run --rm \
  -e CLOUDFRONT_DOMAIN="${CLOUDFRONT_DOMAIN}" \
  -e S3_BUCKET="${S3_BUCKET}" \
  -v "${ROOT_DIR}/certificates:/etc/apt/certs:ro" \
  apt-mtls-validation in-container
