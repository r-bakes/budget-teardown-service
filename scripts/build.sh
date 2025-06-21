#!/usr/bin/env bash

SERVICE_NAME=$1
SERVICE_SRC_DIR="services/${SERVICE_NAME}"
BUILD_ROOT="build"
OUT_DIR="${BUILD_ROOT}/${SERVICE_NAME}"
ZIP_FILE="${OUT_DIR}/${SERVICE_NAME}.zip"

echo ">>> Building service: ${SERVICE_NAME}"

if [ ! -d "${SERVICE_SRC_DIR}" ]; then
  echo "Error: Service source directory ${SERVICE_SRC_DIR} does not exist."
  exit 1
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

# 1. Install dependencies, if any.
if [ -f "${SERVICE_SRC_DIR}/pyproject.toml" ]; then
  echo "    Installing dependencies from pyproject.toml..."
  # Install into OUT_DIR so dependencies are at the root of the zip
  uv pip install --upgrade pip
  uv pip install --target "${OUT_DIR}" "${SERVICE_SRC_DIR}"
else
  echo "    No pyproject.toml found, skipping dependency install."
fi

# 2. Copy service code into OUT_DIR
#    Assumes your code folder is named exactly <service_name> under services/.
#    E.g., services/s3_teardown_lambda/s3_teardown_lambda/
if [ -d "${SERVICE_SRC_DIR}/${SERVICE_NAME}" ]; then
  echo "    Copying service code directory..."
  cp -r "${SERVICE_SRC_DIR}/${SERVICE_NAME}" "${OUT_DIR}/"
else
  echo "    Warning: ${SERVICE_SRC_DIR}/${SERVICE_NAME} not found."
fi

# 3. Create the ZIP
echo "    Creating ZIP ${ZIP_FILE}..."
pushd "${OUT_DIR}" >/dev/null || exit
# Zip everything in OUT_DIR into ../<service_name>.zip so that
# the root of the archive has your service directory and dependency folders/modules.
zip -r "../${SERVICE_NAME}.zip" . >/dev/null
popd >/dev/null || exit
