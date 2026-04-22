#!/usr/bin/env bash

set -e

# Generate self-signed SSL certificates for PostgreSQL
# This script creates certificates that will be stored in a Kubernetes secret

NAMESPACE="${1:-cost-metrics}"
CERT_DIR="./ssl-certs"

echo "Generating self-signed SSL certificates for PostgreSQL..."
echo "Namespace: ${NAMESPACE}"
echo ""

# Create directory for certificates
mkdir -p "${CERT_DIR}"

# Generate private key
echo "1. Generating private key..."
openssl genrsa -out "${CERT_DIR}/server.key" 2048

# Generate certificate signing request
echo "2. Generating certificate signing request..."
openssl req -new -key "${CERT_DIR}/server.key" -out "${CERT_DIR}/server.csr" \
  -subj "/C=US/ST=State/L=City/O=Organization/OU=IT/CN=postgres.${NAMESPACE}.svc.cluster.local"

# Generate self-signed certificate (valid for 10 years)
echo "3. Generating self-signed certificate (valid for 10 years)..."
openssl x509 -req -days 3650 \
  -in "${CERT_DIR}/server.csr" \
  -signkey "${CERT_DIR}/server.key" \
  -out "${CERT_DIR}/server.crt"

# Set proper permissions (PostgreSQL requires 0600 for key file)
chmod 600 "${CERT_DIR}/server.key"
chmod 644 "${CERT_DIR}/server.crt"

echo ""
echo "4. Creating Kubernetes secret..."

# Check if secret already exists
if kubectl get secret postgres-ssl-certs -n "${NAMESPACE}" &>/dev/null; then
  echo "Secret 'postgres-ssl-certs' already exists. Deleting..."
  kubectl delete secret postgres-ssl-certs -n "${NAMESPACE}"
fi

# Create secret from certificate files
kubectl create secret generic postgres-ssl-certs \
  --from-file=server.key="${CERT_DIR}/server.key" \
  --from-file=server.crt="${CERT_DIR}/server.crt" \
  -n "${NAMESPACE}"

echo ""
echo "✓ SSL certificates generated and secret created successfully!"
echo ""
echo "Certificate details:"
openssl x509 -in "${CERT_DIR}/server.crt" -noout -subject -dates
echo ""
echo "Next steps:"
echo "1. Update deploy/postgres-deployment.yml to mount the SSL certificates"
echo "2. Redeploy the PostgreSQL pod"
echo ""
echo "To clean up local certificate files:"
echo "  rm -rf ${CERT_DIR}"

# Made with Bob
