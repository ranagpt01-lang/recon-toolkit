#!/usr/bin/env bash
# ============================================================================
#  Recon Toolkit v2 — Subdomain → Live → Crawl → JS Secrets → Nuclei
#  Author: Rana (ranagpt01-lang)  |  License: MIT
#  USE ONLY ON TARGETS YOU ARE EXPLICITLY AUTHORIZED TO TEST.
# ============================================================================

set -euo pipefail

# ---------- CLI ----------
usage() {
    cat <<EOF
Usage: $0 <domain> [--fast] [--out <dir>]

Options:
  --fast        Disable stealth mode (higher threads / no delays)
  --out <dir>   Output directory (default: recon_<domain>)
  -h, --help    Show this help
EOF
    exit "${1:-0}"
}

[[ $# -lt 1 ]] && usage 1

TARGET=""
STEALTH_MODE=true
OUTPUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fast) STEALTH_MODE=false; shift ;;
        --out)  OUTPUT="$2"; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "Unknown flag: $1" >&2; usage 1 ;;
        *)  TARGET="$1"; shift ;;
    esac
done

[[ -z "$TARGET" ]] && { echo "Error: target domain is required" >&2; usage 1; }

# Strip scheme / trailing slash if user pasted a URL
TARGET="${TARGET#http://}"
TARGET="${TARGET#https://}"
TARGET="${TARGET%%/*}"

OUTPUT="${OUTPUT:-recon_${TARGET}}"

# ---------- Logging helpers ----------
c_reset='\033[0m'; c_blue='\033[1;34m'; c_yellow='\033[1;33m'; c_red='\033[1;31m'; c_green='\033[1;32m'
log()  { printf "${c_blue}[*]${c_reset} %s\n" "$*"; }
warn() { printf "${c_yellow}[!]${c_reset} %s\n" "$*" >&2; }
die()  { printf "${c_red}[x]${c_reset} %s\n" "$*" >&2; exit 1; }
ok()   { printf "${c_green}[+]${c_reset} %s\n" "$*"; }

# ---------- Dependency check ----------
REQUIRED=(subfinder dnsx httpx katana nuclei jq anew curl shuf xargs)
OPTIONAL=(gau waybackurls)

missing=()
for tool in "${REQUIRED[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if (( ${#missing[@]} > 0 )); then
    die "Missing required tools: ${missing[*]}
Install via:
  go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
  go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
  go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
  go install -v github.com/projectdiscovery/katana/cmd/katana@latest
  go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
  go install -v github.com/tomnomnom/anew@latest
  apt install -y jq curl"
fi

for tool in "${OPTIONAL[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || warn "Optional tool not found: $tool (related step will be skipped)"
done

# ---------- Settings ----------
if [[ "$STEALTH_MODE" == true ]]; then
    THREADS=20
    DELAY=3
    RATE_LIMIT=25
    MODE_LABEL="STEALTH"
else
    THREADS=70
    DELAY=0
    RATE_LIMIT=80
    MODE_LABEL="FAST"
fi

# ---------- Banner ----------
printf '%s\n' \
"========================================" \
"  Recon Toolkit v2" \
"  Target : $TARGET" \
"  Mode   : $MODE_LABEL" \
"  Output : $OUTPUT" \
"========================================"

mkdir -p "$OUTPUT"
cd "$OUTPUT"

# ---------- User-Agent rotation ----------
# A UA list is written to a temp file so child processes (xargs subshells)
# can pick a fresh UA per request — bash arrays do NOT survive `export`.
UA_FILE="$(mktemp -t recon_ua.XXXXXX)"
trap 'rm -f "$UA_FILE"' EXIT INT TERM
cat > "$UA_FILE" <<'EOF'
Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36
Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36
Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0
Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15
Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1
EOF
export UA_FILE

random_ua() {
    shuf -n 1 "$UA_FILE"
}

UA_INITIAL="$(random_ua)"
log "Initial UA: ${UA_INITIAL:0:60}..."

# ============================================================================
# 1. Subdomain Enumeration
# ============================================================================
log "[1/7] Subdomain enumeration"
: > subdomains.txt

subfinder -d "$TARGET" -all -recursive -silent | anew subdomains.txt >/dev/null || warn "subfinder failed"

# crt.sh — handle multi-line name_value, filter wildcards, scope-check
{
    curl -s --max-time 30 -A "$(random_ua)" "https://crt.sh/?q=%25.${TARGET}&output=json" \
        | jq -r '.[]?.name_value' 2>/dev/null \
        | tr ',' '\n' \
        | sed 's/\*\.//g' \
        | tr '[:upper:]' '[:lower:]' \
        | { grep -E "(^|\.)${TARGET//./\\.}\$" || true; } \
        | sort -u \
        | anew subdomains.txt >/dev/null
} || warn "crt.sh fetch failed"

ok "Subdomains: $(wc -l < subdomains.txt)"

# ============================================================================
# 2. DNS resolution
# ============================================================================
log "[2/7] DNS resolution"
: > resolved.txt
if [[ -s subdomains.txt ]]; then
    dnsx -l subdomains.txt -silent -nc -a -resp -o resolved.txt >/dev/null 2>&1 || warn "dnsx failed"
    awk '{print $1}' resolved.txt | sort -u > resolved_hosts.txt
    ok "Resolved: $(wc -l < resolved_hosts.txt)"
else
    warn "No subdomains to resolve"
    : > resolved_hosts.txt
fi

# ============================================================================
# 3. Live host probing + tech detection
# ============================================================================
log "[3/7] Probing live hosts"
: > live_hosts.txt
: > live_urls.txt
if [[ -s resolved_hosts.txt ]]; then
    httpx -l resolved_hosts.txt \
        -H "User-Agent: $(random_ua)" \
        -silent -nc -title -tech-detect -status-code -web-server -cdn \
        -threads "$THREADS" -timeout 12 -rate-limit "$RATE_LIMIT" \
        -o live_hosts.txt >/dev/null 2>&1 || warn "httpx failed"

    # URL-only list for downstream tools
    awk '{print $1}' live_hosts.txt | sort -u > live_urls.txt
    ok "Live: $(wc -l < live_urls.txt)"
else
    warn "No hosts to probe"
fi

sleep "$DELAY"

# ============================================================================
# 4. Historical URLs + crawling
# ============================================================================
log "[4/7] Historical URLs + crawl"
: > wayback.txt
if command -v waybackurls >/dev/null 2>&1; then
    echo "$TARGET" | waybackurls | sort -u | anew wayback.txt >/dev/null || warn "waybackurls failed"
fi

: > gau.txt
if command -v gau >/dev/null 2>&1; then
    gau "$TARGET" --threads 5 --subs 2>/dev/null | sort -u | anew gau.txt >/dev/null || warn "gau failed"
fi

: > js_files.txt
if [[ -s live_urls.txt ]]; then
    {
        katana -list live_urls.txt -jc -d 4 -silent -nc 2>/dev/null \
            | { grep -Ei "\.js(\?|$)|\.json(\?|$)" || true; } \
            | sort -u \
            | anew js_files.txt >/dev/null
    } || warn "katana failed"
fi

# Also pull JS URLs from wayback/gau
if [[ -s wayback.txt || -s gau.txt ]]; then
    {
        cat wayback.txt gau.txt 2>/dev/null \
            | { grep -Ei "\.js(\?|$)" || true; } \
            | sort -u \
            | anew js_files.txt >/dev/null
    } || true
fi

ok "JS files: $(wc -l < js_files.txt)"
sleep "$DELAY"

# ============================================================================
# 5. JS secret hunting (parallel, rotating UA)
# ============================================================================
log "[5/7] JS secret hunting"
: > secrets_raw.txt

# Broader, case-insensitive regex that's still grep-friendly.
# Note: this is a coarse filter; pipe to a real secret scanner (trufflehog) for accuracy.
SECRET_REGEX='(api[_-]?key|secret|token|aws_access_key|aws_secret|s3\.amazonaws|firebase|bearer\s+[a-z0-9._-]+|client[_-]?secret|private[_-]?key|-----BEGIN [A-Z ]+ PRIVATE KEY-----)'

if [[ -s js_files.txt ]]; then
    export SECRET_REGEX
    fetch_one() {
        local url="$1"
        local ua
        ua="$(shuf -n 1 "$UA_FILE")"
        curl -s --max-time 10 -A "$ua" "$url" \
            | grep -aiEo ".{0,40}${SECRET_REGEX}.{0,80}" \
            | sed "s|^|${url}: |" || true
    }
    export -f fetch_one

    # Parallelism: 10 in stealth, 30 in fast
    PAR=$([[ "$STEALTH_MODE" == true ]] && echo 10 || echo 30)
    xargs -a js_files.txt -P "$PAR" -I {} bash -c 'fetch_one "$@"' _ {} \
        >> secrets_raw.txt 2>/dev/null || true
fi

sort -u secrets_raw.txt > secrets.txt
ok "Secret candidates: $(wc -l < secrets.txt) (manual review required)"
sleep "$DELAY"

# ============================================================================
# 6. Nuclei scanning
# ============================================================================
log "[6/7] Nuclei scanning"
: > nuclei_results.txt

NUCLEI_TEMPLATES="${NUCLEI_TEMPLATES:-$HOME/nuclei-templates}"
if [[ ! -d "$NUCLEI_TEMPLATES" ]]; then
    warn "Nuclei templates not found at $NUCLEI_TEMPLATES — running update"
    nuclei -update-templates -silent || warn "Failed to update templates"
fi

if [[ -s live_urls.txt ]]; then
    nuclei -l live_urls.txt \
        -H "User-Agent: $(random_ua)" \
        -severity critical,high,medium \
        -tags exposure,misconfig,secrets,cloud \
        -rate-limit "$RATE_LIMIT" \
        -silent -nc -o nuclei_results.txt >/dev/null 2>&1 || warn "nuclei failed"
fi
ok "Nuclei findings: $(wc -l < nuclei_results.txt)"

# ============================================================================
# 7. Final report
# ============================================================================
log "[7/7] Generating report"

{
    echo "Recon Toolkit v2 — Report"
    echo "========================="
    echo "Target     : $TARGET"
    echo "Mode       : $MODE_LABEL"
    echo "Date (UTC) : $(date -u +'%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "Subdomains : $(wc -l < subdomains.txt)"
    echo "Resolved   : $(wc -l < resolved_hosts.txt)"
    echo "Live hosts : $(wc -l < live_urls.txt)"
    echo "JS files   : $(wc -l < js_files.txt)"
    echo "Secrets*   : $(wc -l < secrets.txt)   (* coarse — review manually)"
    echo "Vulns      : $(wc -l < nuclei_results.txt)"
} > report.txt

cat report.txt
ok "Done. Output saved to: $(pwd)"
