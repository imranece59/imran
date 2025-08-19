#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./make_ca_bundle.sh host[:port] [OUTPUT_CA_BUNDLE.pem] [--append-certifi]
#
# Example:
#   ./make_ca_bundle.sh legacy.example.com:443 my-ca-bundle.pem --append-certifi

HOSTPORT="${1:-}"
OUTFILE="${2:-my-ca-bundle.pem}"
APPEND_CERTIFI="${3:-}"

if [[ -z "$HOSTPORT" ]]; then
  echo "Usage: $0 host[:443] [OUTPUT_CA_BUNDLE.pem] [--append-certifi]" >&2
  exit 1
fi

HOST="${HOSTPORT%%:*}"
PORT="${HOSTPORT##*:}"
[[ "$PORT" == "$HOST" ]] && PORT="443"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[*] Fetching presented chain from ${HOST}:${PORT} ..."
# Use SNI to be safe
openssl s_client -connect "${HOST}:${PORT}" -servername "${HOST}" -showcerts </dev/null > "${WORKDIR}/s_client.txt" 2>/dev/null || true

# Split all PEM blocks to files: cert_1.pem, cert_2.pem, ...
awk '
  /-----BEGIN CERTIFICATE-----/ {in_cert=1; fn=sprintf("cert_%02d.pem", ++n)}
  in_cert {print > fn}
  /-----END CERTIFICATE-----/ {in_cert=0}
' "${WORKDIR}/s_client.txt"

shopt -s nullglob
CERTS=( "${WORKDIR}"/cert_*.pem )
if (( ${#CERTS[@]} == 0 )); then
  echo "[!] No certificates found in server response. Aborting." >&2
  exit 2
fi

# Heuristic: first cert is the leaf (openssl s_client prints peer cert first)
LEAF="${CERTS[0]}"
echo "[*] Leaf certificate: ${LEAF}"

# Helper to print Subject/Issuer
print_si () { openssl x509 -in "$1" -noout -subject -issuer; }

echo "[*] Leaf S/I:"
print_si "$LEAF"

# Collect intermediates we have (everything except leaf)
INTER_DIR="${WORKDIR}/inters"
mkdir -p "$INTER_DIR"
for c in "${CERTS[@]:1}"; do
  cp "$c" "${INTER_DIR}/"
done

# Fetch missing intermediates by walking AIA from the leaf and newly found inters
fetch_aia () {
  local src="$1"
  # Extract any "CA Issuers" URIs
  openssl x509 -in "$src" -noout -text \
    | awk '/Authority Information Access/,/X509v3/ {print}' \
    | grep -Eo 'CA Issuers - URI:[^[:space:]]+' \
    | cut -d: -f3- \
    | sed 's/^ //' || true
}

normalize_pem () {
  # Convert DER to PEM if needed; input $1, output $2
  local in="$1" out="$2"
  if openssl x509 -in "$in" -noout >/dev/null 2>&1; then
    # Already PEM
    cp "$in" "$out"
  else
    # Try DER -> PEM
    openssl x509 -inform DER -in "$in" -out "$out" >/dev/null 2>&1 || return 1
  fi
}

echo "[*] Resolving missing intermediates via AIA ..."
SEEN_HASHES=()

add_unique_cert () {
  local pem="$1"
  local sha
  sha="$(openssl x509 -in "$pem" -noout -sha256 -fingerprint | sed 's/.*=//; s/://g')"
  for h in "${SEEN_HASHES[@]}"; do
    [[ "$h" == "$sha" ]] && return 0
  done
  SEEN_HASHES+=("$sha")
  cp "$pem" "${INTER_DIR}/"
}

# Seed hashes with existing inters
for c in "${INTER_DIR}"/*.pem 2>/dev/null; do
  [[ -e "$c" ]] || continue
  add_unique_cert "$c"
done

QUEUE=( "$LEAF" )
VISITED=()

while (( ${#QUEUE[@]} > 0 )); do
  CUR="${QUEUE[0]}"; QUEUE=( "${QUEUE[@]:1}" )
  VISITED+=( "$CUR" )

  # Pull AIA issuers for CUR
  mapfile -t AIS < <(fetch_aia "$CUR" | sed 's/\r//')
  for url in "${AIS[@]}"; do
    [[ -z "$url" ]] && continue
    echo "    [+] AIA: $url"
    tmp="${WORKDIR}/aia_download"
    if curl -fsSL --max-time 15 "$url" -o "${tmp}"; then
      pem="${WORKDIR}/aia.pem"
      if normalize_pem "${tmp}" "${pem}"; then
        # Skip if self-signed root (Subject == Issuer)
        subj="$(openssl x509 -in "$pem" -noout -subject)"
        issr="$(openssl x509 -in "$pem" -noout -issuer)"
        if [[ "$subj" == "$issr" ]]; then
          echo "       (self-signed root; usually not needed in bundle)"
          continue
        fi
        add_unique_cert "$pem"
        # Also enqueue this intermediate to walk its AIA if not visited
        already=false
        for v in "${VISITED[@]}"; do
          if diff -q <(openssl x509 -in "$v" -noout -sha256 -fingerprint) <(openssl x509 -in "$pem" -noout -sha256 -fingerprint) >/dev/null 2>&1; then
            already=true; break
          fi
        done
        "$already" || QUEUE+=( "$pem" )
      fi
    fi
  done
done

# Build bundle: include only intermediates (not the leaf)
echo "[*] Building CA bundle: ${OUTFILE}"
> "${OUTFILE}"
for c in "${INTER_DIR}"/*.pem 2>/dev/null; do
  [[ -e "$c" ]] || continue
  cat "$c" >> "${OUTFILE}"
  echo >> "${OUTFILE}"
done

if [[ ! -s "${OUTFILE}" ]]; then
  echo "[!] No intermediates found. The server may already send a full chain, or is misconfigured without AIA. You can try using the OS bundle instead." >&2
fi

# Quick local verification if a root is present in the OS store:
# (best-effort check; not fatal if it fails)
if command -v security >/dev/null 2>&1 && [[ "$OSTYPE" == darwin* ]]; then
  echo "[i] On macOS, Python still uses certifi by default. Consider --append-certifi."
fi

if [[ "$APPEND_CERTIFI" == "--append-certifi" ]]; then
  if python3 - <<'PY' >/dev/null 2>&1; then
import certifi, sys
print(certifi.where())
PY
  then
    CERTIFI=$(python3 - <<'PY'
import certifi
print(certifi.where())
PY
)
    COMBO="${OUTFILE%.pem}-with-certifi.pem"
    cat "$CERTIFI" "${OUTFILE}" > "$COMBO"
    echo "[*] Appended to certifi bundle:"
    echo "    ${COMBO}"
    echo "[*] Use in Python: verify=r'${COMBO}'"
  else
    echo "[!] Could not locate certifi via Python. Skipping append."
  fi
else
  echo "[*] Use in Python: verify=r'${OUTFILE}'"
fi

echo "[✓] Done."
