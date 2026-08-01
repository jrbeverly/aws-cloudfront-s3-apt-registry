#!/usr/bin/env bash
set -euo pipefail

# Generates the local PKI inputs for the viewer-mTLS sliver.
# Outputs:
#   certificates/root-ca.pem   public CA bundle (uploaded as the trust store)
#   certificates/root-ca.key   CA private key (local only)
#   certificates/dev/          client cert, key, and CSR for the dev environment

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERTS_DIR="${ROOT_DIR}/certificates"

mkdir -p "${CERTS_DIR}/dev"

# Root CA
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "${CERTS_DIR}/root-ca.key" \
  -out "${CERTS_DIR}/root-ca.pem" \
  -subj "/C=CA/O=Local Lab/CN=local-root-ca"

# Dev client key + CSR
openssl req -newkey rsa:2048 -sha256 -nodes \
  -keyout "${CERTS_DIR}/dev/client.key" \
  -out "${CERTS_DIR}/dev/client.csr" \
  -subj "/C=CA/O=Local Lab/CN=local-dev-client"

# Dev client cert signed by the root CA
openssl x509 -req -sha256 -days 365 \
  -in "${CERTS_DIR}/dev/client.csr" \
  -CA "${CERTS_DIR}/root-ca.pem" \
  -CAkey "${CERTS_DIR}/root-ca.key" \
  -CAcreateserial \
  -out "${CERTS_DIR}/dev/client.pem"
