#!/usr/bin/env bash
set -euo pipefail

# Build and install oauth2-proxy from source.
# Usage:
#   bash server/install_oauth2_proxy.sh            # builds default version
#   bash server/install_oauth2_proxy.sh v7.14.2    # builds specific tag

VERSION="${1:-v7.14.2}"
INSTALL_DIR="/usr/local/bin"
BIN_NAME="oauth2-proxy"

if [[ "${VERSION}" != v* ]]; then
  echo "Version must be in form vX.Y.Z (example: v7.14.2)"
  exit 1
fi

for cmd in make go tar; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required tool: ${cmd}"
    echo "Install build tools first (example Ubuntu/Debian):"
    echo "  sudo apt-get update && sudo apt-get install -y make golang tar"
    exit 1
  fi
done

TARBALL="${VERSION}.tar.gz"
URL="https://github.com/oauth2-proxy/oauth2-proxy/archive/refs/tags/${TARBALL}"

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

echo "Building oauth2-proxy from source tag ${VERSION}..."
echo "Source URL: ${URL}"

if command -v curl >/dev/null 2>&1; then
  curl -fL "${URL}" -o "${TMP_DIR}/${TARBALL}"
elif command -v wget >/dev/null 2>&1; then
  wget -O "${TMP_DIR}/${TARBALL}" "${URL}"
else
  echo "Need either curl or wget installed."
  exit 1
fi

tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"
SRC_DIR="${TMP_DIR}/oauth2-proxy-${VERSION#v}"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "Expected source directory not found: ${SRC_DIR}"
  exit 1
fi

pushd "${SRC_DIR}" >/dev/null
make build
popd >/dev/null

if [[ ! -x "${SRC_DIR}/${BIN_NAME}" ]]; then
  echo "Build succeeded but binary not found at ${SRC_DIR}/${BIN_NAME}"
  exit 1
fi

echo "Installing binary to ${INSTALL_DIR}/${BIN_NAME} (sudo required)..."
sudo install -m 0755 "${SRC_DIR}/${BIN_NAME}" "${INSTALL_DIR}/${BIN_NAME}"

echo "Installed: ${INSTALL_DIR}/${BIN_NAME}"
"${INSTALL_DIR}/${BIN_NAME}" --version || true

echo
if systemctl list-unit-files | grep -q '^oauth2-proxy\.service'; then
  echo "Detected oauth2-proxy.service. Restarting it now..."
  sudo systemctl daemon-reload
  sudo systemctl restart oauth2-proxy
  sudo systemctl status oauth2-proxy --no-pager
else
  echo "oauth2-proxy.service not found. If needed, run:"
  echo "  bash server/install_systemd_globus.sh"
fi

echo
cat <<MSG
Next checks:
  ss -ltnp | rg ':4180\\b'
  curl -I http://127.0.0.1:4180/oauth2/auth
MSG
