#!/usr/bin/env bash

set -Eeuo pipefail

UV_VERSION="0.8.17"
UV_ROOT="/opt/platform/uv"
UV_BIN="${UV_ROOT}/bin/uv"
PYTHON_ROOT="/opt/platform/python310"
PYTHON_LINK="/usr/local/bin/Python"
PYTHON3_LINK="/usr/local/bin/python3"

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "The Hybrid Worker compatibility runtime supports x86_64 only." >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run this installer as root." >&2
  exit 1
fi

install -d -m 0755 "${UV_ROOT}/bin" "${PYTHON_ROOT}"

if [[ ! -x "${UV_BIN}" ]]; then
  installer="$(mktemp)"
  trap 'rm -f "${installer}"' EXIT
  curl --fail --silent --show-error --location --retry 3 --max-time 120 \
    "https://astral.sh/uv/${UV_VERSION}/install.sh" --output "${installer}"
  UV_INSTALL_DIR="${UV_ROOT}/bin" sh "${installer}"
  rm -f "${installer}"
  trap - EXIT
fi

export UV_PYTHON_INSTALL_DIR="${PYTHON_ROOT}"
"${UV_BIN}" python install 3.10
python_path="$("${UV_BIN}" python find 3.10)"
if [[ ! -x "${python_path}" ]]; then
  echo "UV did not produce an executable Python 3.10 interpreter." >&2
  exit 1
fi

ln -sfn "${python_path}" "${PYTHON_LINK}"
ln -sfn "${python_path}" "${PYTHON3_LINK}"
"${PYTHON_LINK}" --version
"${PYTHON_LINK}" -c 'import imp; print("legacy imp module available")'
