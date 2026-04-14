#!/usr/bin/env bash

set -euo pipefail

BASE_URL="https://api.trackerr.ca/v1/exercisedb"
OUTPUT_DIR="${1:-./tmp/exercisedb}"
FETCH_ITEMS="${2:-}"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but not installed." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but not installed." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}/items"

echo "Fetching exercise index from ${BASE_URL}..."
curl -sS "${BASE_URL}/" > "${OUTPUT_DIR}/all-exercises.json"

echo "Extracting ids..."
jq -r '.[].id' "${OUTPUT_DIR}/all-exercises.json" | tee "${OUTPUT_DIR}/ids.txt" >/dev/null

count="$(wc -l < "${OUTPUT_DIR}/ids.txt" | tr -d ' ')"
echo "Found ${count} ids."

if [[ "${FETCH_ITEMS}" == "--fetch-items" ]]; then
  while IFS= read -r exercise_id; do
    [ -n "${exercise_id}" ] || continue
    echo "Fetching ${exercise_id}..."
    curl -sS "${BASE_URL}/${exercise_id}" > "${OUTPUT_DIR}/items/${exercise_id}.json"
  done < "${OUTPUT_DIR}/ids.txt"

  echo "Per-item payloads: ${OUTPUT_DIR}/items/"
fi

echo "Done."
echo "Index: ${OUTPUT_DIR}/all-exercises.json"
echo "IDs: ${OUTPUT_DIR}/ids.txt"
