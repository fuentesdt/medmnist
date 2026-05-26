#!/usr/bin/env bash
#
# download_medmnist3d.sh
#
# Download the six 3D datasets from MedMNIST v2 / MedMNIST+ (Zenodo 10519652)
# with MD5 verification and resume support.
#
# Defaults to the 28^3 (MNIST-like) size, which is the canonical benchmark
# and totals ~104 MB. Pass --size 64 for the 64^3 variant (~1.1 GB) or
# --size all for both.
#
# Usage:
#   ./download_medmnist3d.sh                    # 28^3 into ./data/medmnist3d
#   ./download_medmnist3d.sh --size 64          # 64^3 only
#   ./download_medmnist3d.sh --size all         # both sizes
#   ./download_medmnist3d.sh --dest /path/to    # custom destination
#
# Re-running is safe: files already present with a valid MD5 are skipped.

set -euo pipefail

# --- Config ------------------------------------------------------------------

readonly ZENODO_BASE="https://zenodo.org/records/10519652/files"

# name|md5 for the 28^3 variant
readonly DATASETS_28=(
  "adrenalmnist3d.npz|bbd3c5a5576322bc4cdfea780653b1ce"
  "fracturemnist3d.npz|6aa7b0143a6b42da40027a9dda61302f"
  "nodulemnist3d.npz|8755a7e9e05a4d9ce80a24c3e7a256f3"
  "organmnist3d.npz|a0c5a1ff56af4f155c46d46fbb45a2fe"
  "synapsemnist3d.npz|1235b78a3cd6280881dd7850a78eadb6"
  "vesselmnist3d.npz|b41fd4f7e7e2feedddb201585ecafa1b"
)

# name|md5 for the 64^3 variant
readonly DATASETS_64=(
  "adrenalmnist3d_64.npz|17721accfe9fb005146a47d33bc54b2f"
  "fracturemnist3d_64.npz|f01d7e6316aedf4210da0da5b7437b42"
  "nodulemnist3d_64.npz|c47c5b7d457bf6332200d2ea6d64ecd8"
  "organmnist3d_64.npz|58a2205adf14a9d0a189cb06dc78bf10"
  "synapsemnist3d_64.npz|43bd14ebf3af9d3dd072446fedc14d5e"
  "vesselmnist3d_64.npz|6bb274a8846e1097066dcd64e2c4520f"
)

DEST="./data/medmnist3d"
SIZE="28"

# --- Arg parsing -------------------------------------------------------------

usage() {
  # Print the leading comment block (lines starting with #), stripping the prefix.
  awk '/^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "$0"
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --size) SIZE="${2:-}"; shift 2 ;;
    --dest) DEST="${2:-}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

case "$SIZE" in
  28|64|all) ;;
  *) echo "Error: --size must be 28, 64, or all (got: $SIZE)" >&2; exit 1 ;;
esac

# --- Helpers -----------------------------------------------------------------

# Cross-platform MD5: prefer md5sum (Linux), fall back to md5 (macOS).
md5_of() {
  local file="$1"
  if command -v md5sum >/dev/null 2>&1; then
    md5sum "$file" | awk '{print $1}'
  elif command -v md5 >/dev/null 2>&1; then
    md5 -q "$file"
  else
    echo "Error: need md5sum or md5 in PATH" >&2
    exit 1
  fi
}

# Download one file with resume + verify. Returns 0 on success.
fetch_one() {
  local name="$1"
  local expected_md5="$2"
  local out="$DEST/$name"
  local url="$ZENODO_BASE/$name?download=1"

  if [[ -f "$out" ]]; then
    local actual
    actual=$(md5_of "$out")
    if [[ "$actual" == "$expected_md5" ]]; then
      printf '  [skip] %s (already valid)\n' "$name"
      return 0
    fi
    printf '  [warn] %s exists but MD5 mismatch; re-downloading\n' "$name"
    rm -f "$out"
  fi

  printf '  [get ] %s\n' "$name"
  # --location: follow redirects
  # --continue-at -: resume if a partial file is on disk
  # --fail: non-zero exit on HTTP errors so set -e catches it
  # --retry: handle transient network issues
  curl --location --fail --retry 3 --retry-delay 5 \
       --continue-at - \
       --output "$out" \
       "$url"

  local actual
  actual=$(md5_of "$out")
  if [[ "$actual" != "$expected_md5" ]]; then
    printf '  [fail] %s: MD5 %s != expected %s\n' "$name" "$actual" "$expected_md5" >&2
    return 1
  fi
  printf '  [ok  ] %s verified\n' "$name"
}

# --- Main --------------------------------------------------------------------

mkdir -p "$DEST"

declare -a queue=()
if [[ "$SIZE" == "28" || "$SIZE" == "all" ]]; then
  queue+=("${DATASETS_28[@]}")
fi
if [[ "$SIZE" == "64" || "$SIZE" == "all" ]]; then
  queue+=("${DATASETS_64[@]}")
fi

echo "Destination: $DEST"
echo "Size:        ${SIZE}^3"
echo "Files:       ${#queue[@]}"
echo

failed=0
for entry in "${queue[@]}"; do
  name="${entry%%|*}"
  md5="${entry##*|}"
  if ! fetch_one "$name" "$md5"; then
    failed=$((failed + 1))
  fi
done

echo
if [[ "$failed" -gt 0 ]]; then
  echo "Done with $failed failure(s). Re-run to retry — verified files will be skipped." >&2
  exit 1
fi
echo "All ${#queue[@]} files downloaded and verified."
