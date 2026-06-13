#!/bin/bash

#####################################################
# Version     : 1.0.0
# Script Name : crawl.sh
# Description : This script aims to search for vulnerabilities on websites. Please note that this script is for educational and experimental purposes only. Usage beyond these limits may violate the law. The author is not responsible for misuse or illegal use.
# License     : Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)
# Author      : @ghalangwh.official
# Date        : 08-08-2023
#####################################################


# Warna Terang
a="\e[90m"   #abu-abu
p="\e[97m"   #putih
m="\e[91m"   #merah
h="\e[92m"   #hijau
k="\e[93m"   #kuning
b="\e[94m"   #biru
u="\e[95m"   #ungu
c="\e[96m"   #cyan

# Warna Gelap
ag="\e[37m"  #abu-gelap
mg="\e[31m"  #merah-gelap
hg="\e[32m"  #hijau-gelap
kg="\e[33m"  #kuning-gelap
bg="\e[34m"  #biru-gelap
ug="\e[35m"  #ungu-gelap
cg="\e[36m"  #cyan-gelap

USE_TOR=1
THREADS=5
TIMEOUT=20
DELAY=0
MAX_PAGES=20
WORDLIST="list_page.txt"
TARGET_URL=""
REPORT_ROOT="reports"
CACHE_ROOT=".cache"
USE_CACHE=1
PROFILE="normal"
CHECK_TOOLS=0
INTERESTING_STATUS="200 301 302 401 403"

# Validate URL format and prevent command injection
validate_url() {
    local url="$1"
    
    # Check if URL is empty
    if [[ -z "$url" ]]; then
        echo "Error: URL cannot be empty" >&2
        return 1
    fi
    
    # Check for dangerous characters that could enable command injection
    if [[ "$url" =~ [\;\&\|\`\$\(\)\{\}\<\>] ]]; then
        echo "Error: URL contains invalid characters" >&2
        return 1
    fi
    
    # Validate URL format (must start with http:// or https://)
    if [[ ! "$url" =~ ^https?:// ]]; then
        echo "Error: URL must start with http:// or https://" >&2
        return 1
    fi
    
    return 0
}

# Sanitize file path to prevent directory traversal
sanitize_path() {
    local path="$1"
    
    # Check for dangerous characters
    if [[ "$path" =~ [\;\&\|\`\$\(\)\{\}\<\>] ]]; then
        echo "Error: Path contains invalid characters" >&2
        return 1
    fi
    
    # Check for directory traversal patterns
    if [[ "$path" =~ \.\. ]]; then
        echo "Error: Path contains directory traversal sequences" >&2
        return 1
    fi
    
    echo "$path"
    return 0
}

# Validate numeric input
validate_numeric() {
    local value="$1"
    local name="$2"
    local min="$3"
    local max="$4"
    
    # Check if value is a positive integer
    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo "Error: $name must be a positive integer" >&2
        return 1
    fi
    
    # Check range if provided
    if [[ -n "$min" ]] && [[ "$value" -lt "$min" ]]; then
        echo "Error: $name must be at least $min" >&2
        return 1
    fi
    
    if [[ -n "$max" ]] && [[ "$value" -gt "$max" ]]; then
        echo "Error: $name must be at most $max" >&2
        return 1
    fi
    
    return 0
}

usage() {
    cat <<EOF
Usage: bash crawl.sh [options]

Options:
  -u, --url URL             Target URL, example: https://example.com
  -w, --wordlist FILE       Admin path wordlist (default: list_page.txt)
  -t, --threads NUM         Concurrent admin path checks (default: 5)
      --max-pages NUM       Internal pages to crawl lightly (default: 20)
      --timeout NUM         Curl timeout in seconds (default: 20)
      --delay NUM           Delay between queued path checks (default: 0)
      --tor                 Use Tor/torsocks (default)
      --no-tor              Use direct connection without torsocks
      --report-dir DIR      Report root directory (default: reports)
      --cache-dir DIR       Cache directory for response bodies (default: .cache)
      --no-cache            Disable response body cache
      --profile MODE        Scan profile: quick, normal, deep
      --check-tools         Show optional security tool availability and exit
  -h, --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--url)
            TARGET_URL="$2"
            shift 2
            ;;
        -w|--wordlist)
            WORDLIST="$2"
            shift 2
            ;;
        -t|--threads)
            THREADS="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --max-pages)
            MAX_PAGES="$2"
            shift 2
            ;;
        --delay)
            DELAY="$2"
            shift 2
            ;;
        --tor)
            USE_TOR=1
            shift
            ;;
        --no-tor)
            USE_TOR=0
            shift
            ;;
        --report-dir)
            REPORT_ROOT="$2"
            shift 2
            ;;
        --cache-dir)
            CACHE_ROOT="$2"
            shift 2
            ;;
        --no-cache)
            USE_CACHE=0
            shift
            ;;
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --check-tools)
            CHECK_TOOLS=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Sanitize and validate inputs after parsing
if [[ -n "$TARGET_URL" ]]; then
    if ! validate_url "$TARGET_URL"; then
        exit 1
    fi
fi

# Sanitize file paths
WORDLIST=$(sanitize_path "$WORDLIST") || exit 1
REPORT_ROOT=$(sanitize_path "$REPORT_ROOT") || exit 1
CACHE_ROOT=$(sanitize_path "$CACHE_ROOT") || exit 1

# Validate numeric parameters
validate_numeric "$THREADS" "THREADS" 1 100 || exit 1
validate_numeric "$TIMEOUT" "TIMEOUT" 1 300 || exit 1
validate_numeric "$MAX_PAGES" "MAX_PAGES" 1 10000 || exit 1
validate_numeric "$DELAY" "DELAY" 0 60 || exit 1

is_positive_number() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]]
}

is_positive_integer() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

http_get() {
    if [[ "$USE_TOR" -eq 1 ]]; then
        torsocks curl "$@"
    else
        curl "$@"
    fi
}

http_status() {
    local target="$1"
    http_get -sL -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "$target"
}

http_status_direct() {
    local target="$1"
    http_get -s -o /dev/null -w "%{http_code}" --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "$target"
}

http_method_body() {
    local method="$1"
    local target="$2"
    http_get -sS -X "$method" --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "$target" 2>/dev/null
}

is_interesting_status() {
    local status="$1"
    [[ " $INTERESTING_STATUS " == *" $status "* ]]
}

sanitize_filename() {
    printf '%s' "$1" | sed -E 's#[^A-Za-z0-9._-]+#_#g; s#^_+|_+$##g'
}

normalize_body() {
    sed -E 's/\r//g; s/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//'
}

body_signature() {
    normalize_body | sha256sum | awk '{print $1}'
}

body_looks_like_homepage() {
    local body="$1"
    local sig

    sig=$(printf '%s' "$body" | body_signature)
    [[ "$sig" == "$HOME_BODY_SIG" ]]
}

body_contains_any() {
    local body="$1"
    shift
    local needle

    for needle in "$@"; do
        printf '%s\n' "$body" | grep -Eqi "$needle" && return 0
    done
    return 1
}

body_looks_adminish() {
    local body="$1"
    body_contains_any "$body" \
        'login' \
        'admin' \
        'dashboard' \
        'control[[:space:]-]*panel' \
        'sign[[:space:]]*in' \
        'username' \
        'password' \
        '<form' \
        'type=["'"'"'"]password["'"'"'"]'
}

safe_line_count() {
    local file="$1"
    if [[ -s "$file" ]]; then
        wc -l < "$file"
    else
        printf '0'
    fi
}

json_escape() {
    printf '%s' "$1" | jq -Rs .
}

tool_status() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "installed"
    else
        echo "missing"
    fi
}

check_optional_tools() {
    local tool
    for tool in ffuf dirsearch dirb nuclei httpx katana; do
        printf '%s\t%s\n' "$tool" "$(tool_status "$tool")"
    done
}

cache_key() {
    sanitize_filename "$1" | cut -c1-180
}

cached_body() {
    local target="$1"
    local key
    local cache_file

    if [[ "$USE_CACHE" -eq 0 || -z "$CACHE_DIR" ]]; then
        http_get -fsSL --max-time "$TIMEOUT" "$target" 2>/dev/null
        return
    fi

    mkdir -p "$CACHE_DIR"
    key=$(cache_key "$target")
    cache_file="$CACHE_DIR/${key}.body"

    if [[ -s "$cache_file" ]]; then
        printf 'HIT\t%s\n' "$target" >> "$REPORT_DIR/cache.tsv"
        cat "$cache_file"
        return
    fi

    if http_get -fsSL --max-time "$TIMEOUT" "$target" 2>/dev/null > "$cache_file"; then
        printf 'MISS\t%s\n' "$target" >> "$REPORT_DIR/cache.tsv"
        cat "$cache_file"
    else
        rm -f "$cache_file"
        printf 'FAIL\t%s\n' "$target" >> "$REPORT_DIR/cache.tsv"
        return 1
    fi
}

absolute_url() {
    local value="$1"
    local scheme="${URL%%://*}"

    case "$value" in
        http://*|https://*)
            printf '%s\n' "$value"
            ;;
        //* )
            printf '%s:%s\n' "$scheme" "$value"
            ;;
        /* )
            printf '%s%s\n' "$URL" "$value"
            ;;
        * )
            printf '%s/%s\n' "$URL" "$value"
            ;;
    esac
}

add_finding() {
    local severity="$1"
    local message="$2"
    printf '%s\t%s\n' "$severity" "$message" >> "$REPORT_DIR/risk_findings.tsv"
}

risk_score() {
    sort -u "$REPORT_DIR/risk_findings.tsv" | awk -F '\t' '
        $1 == "HIGH" { score += 30 }
        $1 == "MEDIUM" { score += 15 }
        $1 == "LOW" { score += 5 }
        END {
            if (score > 100) score = 100
            print score + 0
        }
    '
}

risk_level() {
    local score="$1"
    if [[ "$score" -ge 70 ]]; then
        echo "HIGH"
    elif [[ "$score" -ge 35 ]]; then
        echo "MEDIUM"
    elif [[ "$score" -gt 0 ]]; then
        echo "LOW"
    else
        echo "INFO"
    fi
}

check_security_headers() {
    local headers_lower="$1"
    local output="$REPORT_DIR/security_headers.txt"

    : > "$output"
    for header in \
        "strict-transport-security:LOW:HSTS missing" \
        "content-security-policy:MEDIUM:CSP missing" \
        "x-frame-options:LOW:X-Frame-Options missing" \
        "x-content-type-options:LOW:X-Content-Type-Options missing" \
        "referrer-policy:LOW:Referrer-Policy missing" \
        "permissions-policy:LOW:Permissions-Policy missing"
    do
        local header_name="${header%%:*}"
        local rest="${header#*:}"
        local severity="${rest%%:*}"
        local message="${rest#*:}"

        if printf '%s\n' "$headers_lower" | grep -q "^${header_name}:"; then
            printf 'OK\t%s\n' "$header_name" >> "$output"
        else
            printf 'MISSING\t%s\n' "$header_name" >> "$output"
            add_finding "$severity" "$message"
        fi
    done
}

check_http_methods() {
    local output="$REPORT_DIR/http_methods.tsv"
    local allow_header
    local status
    local method
    local body
    local body_sig

    : > "$output"
    allow_header=$(http_get -sI -X OPTIONS --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "$URL" 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^allow:/ {print}')
    printf 'ALLOW\t%s\n' "${allow_header:-not exposed}" >> "$output"

    for method in OPTIONS TRACE PUT DELETE PATCH; do
        body=$(http_method_body "$method" "$URL")
        status=$(http_get -s -o /dev/null -w "%{http_code}" -X "$method" --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "$URL")
        body_sig=$(printf '%s' "$body" | body_signature)
        printf '%s\t%s\n' "$method" "$status" >> "$output"

        case "$method:$status" in
            TRACE:200|TRACE:2*)
                [[ "$body_sig" != "$HOME_BODY_SIG" ]] && add_finding "HIGH" "HTTP TRACE method appears enabled"
                ;;
            PUT:200|PUT:201|PUT:204|DELETE:200|DELETE:202|DELETE:204|PATCH:200|PATCH:204)
                [[ "$body_sig" != "$HOME_BODY_SIG" ]] && add_finding "HIGH" "Potentially dangerous HTTP method accepted: $method"
                ;;
            OPTIONS:200|OPTIONS:204)
                add_finding "LOW" "HTTP OPTIONS method is enabled"
                ;;
        esac
    done
}

analyze_csp() {
    local output="$REPORT_DIR/csp_analysis.txt"
    local csp

    : > "$output"
    csp=$(printf '%s\n' "$HEADERS_LOWER" | awk -F':' '/^content-security-policy:/ {sub(/^[^:]+:[ \t]*/, ""); print; exit}')

    if [[ -z "$csp" ]]; then
        echo "MISSING	Content-Security-Policy header not found" > "$output"
        add_finding "MEDIUM" "CSP header missing"
        return
    fi

    echo "$csp" > "$output"

    printf '%s\n' "$csp" | grep -q "'unsafe-inline'" && {
        echo "WARN	CSP uses unsafe-inline" >> "$output"
        add_finding "MEDIUM" "CSP uses unsafe-inline"
    }
    printf '%s\n' "$csp" | grep -q "'unsafe-eval'" && {
        echo "WARN	CSP uses unsafe-eval" >> "$output"
        add_finding "MEDIUM" "CSP uses unsafe-eval"
    }
    printf '%s\n' "$csp" | grep -Eq '(^|[ ;])\*([ ;]|$)' && {
        echo "WARN	CSP contains wildcard source" >> "$output"
        add_finding "LOW" "CSP contains wildcard source"
    }
    printf '%s\n' "$csp" | grep -q 'object-src' || {
        echo "WARN	CSP missing object-src" >> "$output"
        add_finding "LOW" "CSP missing object-src"
    }
    printf '%s\n' "$csp" | grep -q 'frame-ancestors' || {
        echo "WARN	CSP missing frame-ancestors" >> "$output"
        add_finding "LOW" "CSP missing frame-ancestors"
    }
}

check_clickjacking() {
    local output="$REPORT_DIR/clickjacking.txt"
    local has_xfo
    local has_frame_ancestors

    : > "$output"
    has_xfo=$(printf '%s\n' "$HEADERS_LOWER" | grep -c '^x-frame-options:')
    has_frame_ancestors=$(printf '%s\n' "$HEADERS_LOWER" | grep -c '^content-security-policy:.*frame-ancestors')

    if [[ "$has_xfo" -eq 0 && "$has_frame_ancestors" -eq 0 ]]; then
        echo "WARN	Missing both X-Frame-Options and CSP frame-ancestors" > "$output"
        add_finding "MEDIUM" "Clickjacking protection missing"
    else
        echo "OK	Clickjacking protection header present" > "$output"
    fi
}

fingerprint_tech() {
    local headers_lower="$1"
    local html_lower="$2"
    local output="$REPORT_DIR/tech_fingerprint.txt"

    : > "$output"

    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'cloudflare\|cf-ray' && echo "Cloudflare" >> "$output"
    printf '%s\n' "$headers_lower" | grep -qi 'server: nginx' && echo "nginx" >> "$output"
    printf '%s\n' "$headers_lower" | grep -qi 'server: apache' && echo "Apache" >> "$output"
    printf '%s\n' "$headers_lower" | grep -qi 'x-powered-by:.*php\|phpsessid' && echo "PHP" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi 'wp-content\|wp-includes' && echo "WordPress" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'laravel_session\|xsrf-token' && echo "Laravel" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'ci_session\|codeigniter' && echo "CodeIgniter" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi '_next/static' && echo "Next.js" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi '_nuxt' && echo "Nuxt" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi 'data-reactroot\|react' && echo "React" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi 'vue' && echo "Vue" >> "$output"
    printf '%s\n' "$html_lower" | grep -qi 'vite' && echo "Vite" >> "$output"

    sort -u "$output" -o "$output"
}

detect_waf_cdn() {
    local headers_lower="$1"
    local html_lower="$2"
    local output="$REPORT_DIR/waf_cdn.txt"

    : > "$output"

    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'cloudflare\|cf-ray\|__cf_bm' && echo "Cloudflare" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'akamai\|akamai-ghost' && echo "Akamai" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'sucuri\|x-sucuri' && echo "Sucuri" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'imperva\|incapsula\|visid_incap' && echo "Imperva/Incapsula" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'fastly\|x-served-by' && echo "Fastly" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'cloudfront\|x-amz-cf' && echo "AWS CloudFront" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'vercel\|x-vercel' && echo "Vercel" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'netlify\|x-nf-request-id' && echo "Netlify" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'fly.io\|fly-request-id' && echo "Fly.io" >> "$output"
    printf '%s\n%s\n' "$headers_lower" "$html_lower" | grep -qi 'x-powered-by: express' && echo "Express" >> "$output"

    sort -u "$output" -o "$output"
}

crtsh_subdomains() {
    local output="$REPORT_DIR/crtsh_subdomains.txt"

    : > "$output"

    curl -fsS --max-time "$TIMEOUT" "https://crt.sh/?q=%25.${NOT_SUB}&output=json" 2>/dev/null \
        | jq -r '.[].name_value?' 2>/dev/null \
        | sed 's/\\n/\n/g' \
        | sed 's/\*\.//g' \
        | sed '/^$/d' \
        | sort -u > "$output"

    if [[ -s "$output" ]]; then
        add_finding "LOW" "crt.sh returned passive subdomains"
    else
        echo "No crt.sh data or request failed" > "$output"
    fi
}

run_external_probers() {
    local output="$REPORT_DIR/external_tools.txt"

    : > "$output"

    if command -v httpx >/dev/null 2>&1; then
        echo "[httpx]" >> "$output"
        printf '%s\n' "$URL" | httpx -silent -title -tech-detect -status-code -follow-redirects -no-color 2>/dev/null >> "$REPORT_DIR/httpx.txt"
        cat "$REPORT_DIR/httpx.txt" >> "$output"
    else
        echo "[httpx] not installed" >> "$output"
    fi

    if command -v katana >/dev/null 2>&1; then
        echo "[katana]" >> "$output"
        katana -u "$URL" -d 2 -silent -no-color 2>/dev/null | sort -u | head -n 200 > "$REPORT_DIR/katana_urls.txt"
        echo "katana_urls=$(safe_line_count "$REPORT_DIR/katana_urls.txt")" >> "$output"
    else
        echo "[katana] not installed" >> "$output"
    fi

    if command -v nuclei >/dev/null 2>&1; then
        echo "[nuclei]" >> "$output"
        nuclei -u "$URL" -severity low,medium,high,critical -silent -no-color -o "$REPORT_DIR/nuclei_findings.txt" >/dev/null 2>&1
        echo "nuclei_findings=$(safe_line_count "$REPORT_DIR/nuclei_findings.txt")" >> "$output"
        if [[ -s "$REPORT_DIR/nuclei_findings.txt" ]]; then
            add_finding "MEDIUM" "Nuclei returned findings"
        fi
    else
        echo "[nuclei] not installed" >> "$output"
    fi
}

run_external_directory_scan() {
    local output="$REPORT_DIR/external_dirscan.txt"

    : > "$output"

    if command -v ffuf >/dev/null 2>&1; then
        echo "[ffuf]" >> "$output"
        ffuf -u "${URL}/FUZZ" -w "$WORDLIST" -mc 200,301,302,401,403 -t "$THREADS" -timeout "$TIMEOUT" -of csv -o "$REPORT_DIR/ffuf.csv" -s 2>/dev/null
        if [[ -s "$REPORT_DIR/ffuf.csv" ]]; then
            awk -F',' 'NR>1 {print $2 "\t" $1}' "$REPORT_DIR/ffuf.csv" > "$REPORT_DIR/ffuf_hits.tsv"
            cat "$REPORT_DIR/ffuf_hits.tsv" >> "$output"
            add_finding "LOW" "ffuf found interesting paths"
        fi
    elif command -v dirsearch >/dev/null 2>&1; then
        echo "[dirsearch]" >> "$output"
        dirsearch -u "$URL" -w "$WORDLIST" -t "$THREADS" -x 404 --format=plain -o "$REPORT_DIR/dirsearch.txt" --no-color >/dev/null 2>&1
        cat "$REPORT_DIR/dirsearch.txt" >> "$output"
        if [[ -s "$REPORT_DIR/dirsearch.txt" ]]; then
            add_finding "LOW" "dirsearch found interesting paths"
        fi
    elif command -v dirb >/dev/null 2>&1; then
        echo "[dirb]" >> "$output"
        dirb "$URL" "$WORDLIST" -S -r -o "$REPORT_DIR/dirb.txt" >/dev/null 2>&1
        cat "$REPORT_DIR/dirb.txt" >> "$output"
        if [[ -s "$REPORT_DIR/dirb.txt" ]]; then
            add_finding "LOW" "dirb completed directory scan"
        fi
    else
        echo "No external directory scanner installed. Used built-in curl loop only." >> "$output"
    fi
}

extract_js_endpoints() {
    local main_html="$1"
    local js_sources="$REPORT_DIR/js_sources.txt"
    local endpoints="$REPORT_DIR/js_endpoints.txt"
    local js_count=0

    : > "$js_sources"
    : > "$endpoints"

    printf '%s\n' "$main_html" \
        | grep -Eoi "src=['\"][^'\"]+\.js([^'\"]*)?['\"]" \
        | sed -E "s/src=['\"]//;s/['\"]$//" \
        | while IFS= read -r src; do
            absolute_url "$src"
        done \
        | sort -u \
        | head -n 25 > "$js_sources"

    while IFS= read -r js_url; do
        [[ -z "$js_url" ]] && continue
        js_count=$((js_count + 1))
        cached_body "$js_url" \
            | grep -Eo "['\"][A-Za-z0-9_./?&=%:#-]*(api|admin|login|graphql|upload|auth|user|token|v[0-9]/)[A-Za-z0-9_./?&=%:#-]*['\"]" \
            | tr -d "\"'" \
            | grep -E '^/|^https?://' \
            >> "$endpoints"
    done < "$js_sources"

    sort -u "$endpoints" -o "$endpoints"

    if [[ -s "$endpoints" ]]; then
        add_finding "LOW" "JS endpoints discovered"
    fi
}

parse_robots_and_sitemaps() {
    local robots_content="$1"
    local robots_paths="$REPORT_DIR/robots_paths.txt"
    local sitemap_urls="$REPORT_DIR/sitemap_urls.txt"
    local sitemap_pages="$REPORT_DIR/sitemap_pages.txt"

    : > "$robots_paths"
    : > "$sitemap_urls"
    : > "$sitemap_pages"

    printf '%s\n' "$robots_content" \
        | awk 'BEGIN{IGNORECASE=1} /^(allow|disallow):/ {print $0}' \
        | sed -E 's/^[^:]+:[[:space:]]*//' \
        | grep -E '^/' \
        | sort -u > "$robots_paths"

    printf '%s\n' "$robots_content" \
        | awk 'BEGIN{IGNORECASE=1} /^sitemap:/ {print $2}' \
        | sort -u > "$sitemap_urls"

    printf '%s\n%s/sitemap.xml\n%s/sitemap_index.xml\n' "$(cat "$sitemap_urls")" "$URL" "$URL" \
        | grep -E '^https?://' \
        | sort -u > "${sitemap_urls}.tmp"
    mv "${sitemap_urls}.tmp" "$sitemap_urls"

    while IFS= read -r sitemap_url; do
        [[ -z "$sitemap_url" ]] && continue
        cached_body "$sitemap_url" \
            | grep -Eo '<loc>[^<]+' \
            | sed 's#<loc>##' \
            >> "$sitemap_pages"
    done < "$sitemap_urls"

    sort -u "$sitemap_pages" -o "$sitemap_pages"

    if [[ -s "$robots_paths" ]]; then
        add_finding "LOW" "Robots.txt exposes crawl paths"
    fi
}

check_interesting_files() {
    local output="$REPORT_DIR/interesting_files.tsv"
    local path status severity
    local body

    : > "$output"

    for item in \
        ".env:HIGH" \
        ".git/config:HIGH" \
        "phpinfo.php:HIGH" \
        "backup.zip:HIGH" \
        "backup.sql:HIGH" \
        "db.sql:HIGH" \
        "database.sql:HIGH" \
        "config.php.bak:MEDIUM" \
        "composer.json:MEDIUM" \
        "package.json:LOW" \
        ".DS_Store:LOW" \
        ".well-known/security.txt:INFO"
    do
        path="${item%%:*}"
        severity="${item#*:}"
        status=$(http_status_direct "${URL}/${path}")
        body=$(cached_body "${URL}/${path}" 2>/dev/null || true)

        if [[ -z "$body" || "$(printf '%s' "$body" | body_signature)" == "$HOME_BODY_SIG" ]]; then
            continue
        fi

        case "$path" in
            .env)
                body_contains_any "$body" '(^|[[:space:]])APP_KEY=' '(^|[[:space:]])DB_' '(^|[[:space:]])MAIL_' '(^|[[:space:]])SECRET=' || continue
                ;;
            .git/config)
                body_contains_any "$body" '^\[core\]' 'repositoryformatversion' 'filemode' || continue
                ;;
            phpinfo.php)
                body_contains_any "$body" 'PHP Version' 'phpinfo\(\)' || continue
                ;;
            backup.zip|backup.sql|db.sql|database.sql)
                body_contains_any "$body" 'MySQL dump' 'PostgreSQL database dump' 'PK' 'SQLite format 3' || true
                ;;
            composer.json)
                body_contains_any "$body" '"name"' '"require"' '"autoload"' || continue
                severity="LOW"
                ;;
            package.json)
                body_contains_any "$body" '"name"' '"dependencies"' '"scripts"' || continue
                severity="INFO"
                ;;
            .DS_Store)
                continue
                ;;
            .well-known/security.txt)
                severity="INFO"
                ;;
        esac

        if [[ "$status" =~ ^(200|401|403)$ ]]; then
            printf '%s\t%s\t%s\n' "$status" "$severity" "${URL}/${path}" >> "$output"
            if [[ "$status" == "200" && "$severity" != "INFO" ]]; then
                add_finding "$severity" "Interesting file exposed: /$path"
            elif [[ "$status" =~ ^(401|403)$ ]]; then
                add_finding "LOW" "Protected interesting file exists: /$path"
            fi
        fi
    done
}

detect_sensitive_keywords() {
    local output="$REPORT_DIR/sensitive_keywords.tsv"
    local keyword
    local src
    local content

    : > "$output"
    for keyword in api_key secret token password bearer firebase s3.amazonaws.com private_key client_secret access_key; do
        if printf '%s\n' "$MAIN_HTML_LOWER" | grep -q "$keyword"; then
            printf '%s\t%s\n' "$keyword" "$REAL" >> "$output"
        fi
    done

    while IFS= read -r src; do
        [[ -z "$src" ]] && continue
        content=$(cached_body "$src" | tr '[:upper:]' '[:lower:]')
        for keyword in api_key secret token password bearer firebase s3.amazonaws.com private_key client_secret access_key; do
            if printf '%s\n' "$content" | grep -q "$keyword"; then
                printf '%s\t%s\n' "$keyword" "$src" >> "$output"
            fi
        done
    done < "$REPORT_DIR/js_sources.txt"

    sort -u "$output" -o "$output"
    if [[ -s "$output" ]]; then
        add_finding "MEDIUM" "Sensitive keywords found in HTML/JS sources"
    fi
}

wordpress_passive_audit() {
    local output="$REPORT_DIR/wordpress_audit.tsv"
    local status
    local path

    : > "$output"

    if ! grep -qi '^WordPress$' "$REPORT_DIR/tech_fingerprint.txt" 2>/dev/null; then
        echo "SKIP	WordPress not detected" > "$output"
        return
    fi

    add_finding "LOW" "WordPress detected: review plugins, themes, xmlrpc, and wp-json exposure"

    for path in wp-json/ xmlrpc.php wp-login.php readme.html wp-content/plugins/ wp-content/themes/; do
        status=$(http_status_direct "${URL}/${path}")
        printf '%s\t/%s\n' "$status" "$path" >> "$output"
        if [[ "$path" == "xmlrpc.php" && "$status" =~ ^(200|405)$ ]]; then
            add_finding "MEDIUM" "WordPress xmlrpc.php is reachable"
        elif [[ "$path" == "readme.html" && "$status" == "200" ]]; then
            add_finding "LOW" "WordPress readme.html is exposed"
        elif [[ "$path" =~ plugins|themes && "$status" == "200" ]]; then
            add_finding "LOW" "WordPress directory may be browsable: /$path"
        fi
    done
}

check_cors() {
    local output="$REPORT_DIR/cors.txt"
    local origin
    local credentials

    : > "$output"
    origin=$(printf '%s\n' "$HEADERS_LOWER" | awk -F':' '/^access-control-allow-origin:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    credentials=$(printf '%s\n' "$HEADERS_LOWER" | awk -F':' '/^access-control-allow-credentials:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')

    echo "Access-Control-Allow-Origin: ${origin:-not set}" >> "$output"
    echo "Access-Control-Allow-Credentials: ${credentials:-not set}" >> "$output"

    if [[ "$origin" == "*" && "$credentials" == "true" ]]; then
        add_finding "HIGH" "CORS allows wildcard origin with credentials"
        echo "HIGH	CORS wildcard origin with credentials" >> "$output"
    elif [[ "$origin" == "*" ]]; then
        add_finding "LOW" "CORS allows wildcard origin"
        echo "LOW	CORS wildcard origin" >> "$output"
    elif [[ -n "$origin" ]]; then
        echo "INFO	CORS is configured" >> "$output"
    fi
}

collect_url_sources() {
    local output="$REPORT_DIR/url_sources.txt"

    : > "$output"
    for file in \
        "$REPORT_DIR/links.txt" \
        "$REPORT_DIR/js_endpoints.txt" \
        "$REPORT_DIR/sitemap_pages.txt" \
        "$REPORT_DIR/internal_links.txt" \
        "$REPORT_DIR/katana_urls.txt"
    do
        [[ -s "$file" ]] && cat "$file" >> "$output"
    done

    sort -u "$output" -o "$output"
}

detect_parameter_candidates() {
    local output_redirect="$REPORT_DIR/open_redirect_candidates.tsv"
    local output_injection="$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv"
    local source_file="$REPORT_DIR/url_sources.txt"

    collect_url_sources
    : > "$output_redirect"
    : > "$output_injection"

    if [[ ! -s "$source_file" ]]; then
        return
    fi

    grep -Ei '[?&](redirect|redir|next|url|return|continue|callback|target|dest|destination)=' "$source_file" \
        | awk '{print "OPEN_REDIRECT_CANDIDATE\t" $0}' \
        | sort -u > "$output_redirect"

    grep -Ei '[?&](url|uri|path|file|page|template|include|image|proxy|fetch|load|resource|document)=' "$source_file" \
        | awk '{print "SSRF_LFI_RFI_CANDIDATE\t" $0}' \
        | sort -u > "$output_injection"

    [[ -s "$output_redirect" ]] && add_finding "LOW" "Open redirect candidate parameters found"
    [[ -s "$output_injection" ]] && add_finding "LOW" "SSRF/LFI/RFI candidate parameters found"
}

detect_graphql() {
    local output="$REPORT_DIR/graphql.tsv"
    local path
    local status

    : > "$output"

    for path in graphql api/graphql graphiql; do
        status=$(http_status_direct "${URL}/${path}")
        if [[ "$status" =~ ^(200|400|401|403|405)$ ]]; then
            printf '%s\t/%s\n' "$status" "$path" >> "$output"
        fi
    done

    if [[ -s "$REPORT_DIR/js_endpoints.txt" ]]; then
        grep -Ei 'graphql|graphiql' "$REPORT_DIR/js_endpoints.txt" \
            | awk '{print "JS\t" $0}' >> "$output"
    fi

    sort -u "$output" -o "$output"
    [[ -s "$output" ]] && add_finding "LOW" "GraphQL surface candidate found"
}

check_cors_reflection() {
    local output="$REPORT_DIR/cors_reflection.txt"
    local test_origin="https://evil.invalid"
    local response_headers
    local allow_origin
    local allow_credentials

    : > "$output"
    response_headers=$(http_get -sI --max-time "$TIMEOUT" -H "Origin: $test_origin" -A "$(shuf -n 1 user_agents.txt)" "$URL" 2>/dev/null)
    allow_origin=$(printf '%s\n' "$response_headers" | tr '[:upper:]' '[:lower:]' | awk -F':' '/^access-control-allow-origin:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    allow_credentials=$(printf '%s\n' "$response_headers" | tr '[:upper:]' '[:lower:]' | awk -F':' '/^access-control-allow-credentials:/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')

    {
        echo "Test-Origin: $test_origin"
        echo "Access-Control-Allow-Origin: ${allow_origin:-not set}"
        echo "Access-Control-Allow-Credentials: ${allow_credentials:-not set}"
    } > "$output"

    if [[ "$allow_origin" == "$test_origin" && "$allow_credentials" == "true" ]]; then
        echo "HIGH	Origin reflection with credentials" >> "$output"
        add_finding "HIGH" "CORS reflects arbitrary Origin with credentials"
    elif [[ "$allow_origin" == "$test_origin" ]]; then
        echo "MEDIUM	Origin reflection without credentials" >> "$output"
        add_finding "MEDIUM" "CORS reflects arbitrary Origin"
    fi
}

check_host_header_reflection() {
    local output="$REPORT_DIR/host_header_reflection.txt"
    local test_host="host-check.invalid"
    local response

    : > "$output"
    response=$(http_get -sS --max-time "$TIMEOUT" -H "Host: $test_host" -A "$(shuf -n 1 user_agents.txt)" "$URL" 2>/dev/null | head -c 20000)

    if printf '%s\n' "$response" | grep -qi "$test_host"; then
        echo "WARN	Host header value reflected in response body" > "$output"
        add_finding "MEDIUM" "Host header value reflected in response body"
    else
        echo "OK	Host header reflection not observed in response body" > "$output"
    fi
}

audit_well_known() {
    local output="$REPORT_DIR/well_known.tsv"
    local path
    local status

    : > "$output"

    for path in \
        ".well-known/security.txt" \
        ".well-known/change-password" \
        ".well-known/assetlinks.json" \
        ".well-known/apple-app-site-association" \
        ".well-known/openid-configuration" \
        ".well-known/oauth-authorization-server"
    do
        status=$(http_status_direct "${URL}/${path}")
        printf '%s\t/%s\n' "$status" "$path" >> "$output"
    done
}

detect_cloud_storage_candidates() {
    local output="$REPORT_DIR/cloud_storage_candidates.tsv"
    local source="$REPORT_DIR/cloud_storage_source.txt"

    : > "$output"
    {
        printf '%s\n' "$MAIN_HTML"
        [[ -s "$REPORT_DIR/js_sources.txt" ]] && while IFS= read -r src; do cached_body "$src"; done < "$REPORT_DIR/js_sources.txt"
    } > "$source"

    grep -Eoi 'https?://[^"'\'' <>]*(s3\.amazonaws\.com|storage\.googleapis\.com|blob\.core\.windows\.net|r2\.cloudflarestorage\.com|digitaloceanspaces\.com)[^"'\'' <>]*' "$source" \
        | sort -u > "$output"

    [[ -s "$output" ]] && add_finding "LOW" "Cloud storage URL candidates found"
}

detect_dependency_versions() {
    local output="$REPORT_DIR/dependency_versions.tsv"
    local source="$REPORT_DIR/dependency_source.txt"

    : > "$output"
    {
        printf '%s\n' "$MAIN_HTML"
        [[ -s "$REPORT_DIR/js_sources.txt" ]] && cat "$REPORT_DIR/js_sources.txt"
    } > "$source"

    grep -Eoi '(jquery[-./]?[0-9]+\.[0-9]+\.[0-9]+|jquery[?]ver=[0-9.]+|bootstrap[-./]?[0-9]+\.[0-9]+\.[0-9]+|bootstrap[?]ver=[0-9.]+|wp-(content|includes)[^"'\'' <>]*ver=[0-9.]+|<meta[^>]+generator[^>]+>)' "$source" \
        | sed 's/[<>]/ /g' \
        | sort -u > "$output"

    [[ -s "$output" ]] && add_finding "LOW" "Dependency or version disclosure candidates found"
}

extract_internal_links() {
    local html="$1"
    local output="$2"

    printf '%s\n' "$html" \
        | grep -Eoi "href=['\"][^'\"]+['\"]" \
        | sed -E "s/href=['\"]//;s/['\"]$//" \
        | grep -Ev '^(mailto:|tel:|javascript:|#)' \
        | while IFS= read -r href; do
            absolute_url "$href"
        done \
        | sed 's/#.*$//' \
        | grep -E "^${URL}(/|$)" \
        | sort -u \
        | head -n "$MAX_PAGES" > "$output"
}

detect_forms_from_html() {
    local page_url="$1"
    local html="$2"
    local output="$REPORT_DIR/forms.tsv"
    local lower_html
    local form_count
    local password_count
    local upload_count
    local search_count
    local post_count
    local form_type

    lower_html=$(printf '%s\n' "$html" | tr '[:upper:]' '[:lower:]')
    form_count=$(printf '%s\n' "$lower_html" | grep -Eo '<form[ >]' | wc -l)
    [[ "$form_count" -eq 0 ]] && return

    password_count=$(printf '%s\n' "$lower_html" | grep -Eo 'type=["'\'']?password' | wc -l)
    upload_count=$(printf '%s\n' "$lower_html" | grep -Eo 'type=["'\'']?file' | wc -l)
    search_count=$(printf '%s\n' "$lower_html" | grep -Eo 'type=["'\'']?search|name=["'\'']?q|name=["'\'']?search' | wc -l)
    post_count=$(printf '%s\n' "$lower_html" | grep -Eo 'method=["'\'']?post' | wc -l)
    form_type="generic"

    if [[ "$password_count" -gt 0 ]]; then
        form_type="login"
        add_finding "LOW" "Login form detected: $page_url"
    elif [[ "$upload_count" -gt 0 ]]; then
        form_type="upload"
        add_finding "MEDIUM" "Upload form detected: $page_url"
    elif [[ "$search_count" -gt 0 ]]; then
        form_type="search"
    elif [[ "$post_count" -gt 0 ]]; then
        form_type="post"
    fi

    printf '%s\t%s\tforms=%s\tpassword=%s\tupload=%s\tpost=%s\n' \
        "$form_type" "$page_url" "$form_count" "$password_count" "$upload_count" "$post_count" >> "$output"
}

detect_directory_listing_from_html() {
    local page_url="$1"
    local html="$2"
    local lower_html

    lower_html=$(printf '%s\n' "$html" | tr '[:upper:]' '[:lower:]')
    if printf '%s\n' "$lower_html" | grep -Eq '<title>index of|index of /|parent directory'; then
        printf 'POSSIBLE\t%s\n' "$page_url" >> "$REPORT_DIR/directory_listing.tsv"
        add_finding "HIGH" "Possible directory listing exposed: $page_url"
    fi
}

crawl_internal_pages() {
    local output="$REPORT_DIR/crawled_pages.tsv"
    local links_file="$REPORT_DIR/internal_links.txt"
    local queue_file="$REPORT_DIR/internal_queue.txt"
    local page_url
    local status
    local page_html
    local page_title
    local page_links
    local page_contacts

    : > "$output"
    : > "$REPORT_DIR/forms.tsv"
    : > "$REPORT_DIR/directory_listing.tsv"
    extract_internal_links "$MAIN_HTML" "$links_file"

    if ! grep -qx "$URL" "$links_file" 2>/dev/null; then
        printf '%s\n' "$URL" >> "$links_file"
    fi
    sort -u "$links_file" -o "$links_file"
    head -n "$MAX_PAGES" "$links_file" > "$queue_file"

    while IFS= read -r page_url; do
        [[ -z "$page_url" ]] && continue
        status=$(http_status "$page_url")
        page_html=$(cached_body "$page_url")
        page_title=$(printf '%s\n' "$page_html" | awk -F '</?title>' 'NF>2 {print $2; exit}')
        page_links=$(printf '%s\n' "$page_html" | grep -Eoi "href=['\"][^'\"]+['\"]" | wc -l)
        page_contacts=$(printf '%s\n' "$page_html" | grep -Eo '[[:alnum:]+\.\_\-]+@[[:alnum:]+\.\_\-]+\.[[:alpha:]]+' | sort -u | wc -l)

        printf '%s\t%s\tlinks=%s\tcontacts=%s\ttitle=%s\n' "$status" "$page_url" "$page_links" "$page_contacts" "$page_title" >> "$output"
        detect_forms_from_html "$page_url" "$page_html"
        detect_directory_listing_from_html "$page_url" "$page_html"

        printf '%s\n' "$page_html" \
            | grep -Eoi "href=['\"][^'\"]+['\"]" \
            | sed -E "s/href=['\"]//;s/['\"]$//" \
            | grep -Ev '^(mailto:|tel:|javascript:|#)' \
            | while IFS= read -r href; do
                absolute_url "$href"
            done \
            | sed 's/#.*$//' \
            | grep -E "^${URL}(/|$)" >> "$links_file"

    done < "$queue_file"

    sort -u "$links_file" -o "$links_file"
    head -n "$MAX_PAGES" "$links_file" > "${links_file}.tmp"
    mv "${links_file}.tmp" "$links_file"
}

check_cookie_security() {
    local output="$REPORT_DIR/cookies.txt"
    local cookies

    : > "$output"
    cookies=$(printf '%s\n' "$HEADERS" | awk 'BEGIN{IGNORECASE=1} /^set-cookie:/ {print}')

    if [[ -z "$cookies" ]]; then
        echo "No Set-Cookie headers found" > "$output"
        return
    fi

    printf '%s\n' "$cookies" | while IFS= read -r cookie; do
        printf '%s\n' "$cookie" >> "$output"
        printf '%s\n' "$cookie" | grep -qi 'secure' || {
            printf 'WARN\tMissing Secure\t%s\n' "$cookie" >> "$REPORT_DIR/cookie_findings.tsv"
            add_finding "LOW" "Cookie missing Secure attribute"
        }
        printf '%s\n' "$cookie" | grep -qi 'httponly' || {
            printf 'WARN\tMissing HttpOnly\t%s\n' "$cookie" >> "$REPORT_DIR/cookie_findings.tsv"
            add_finding "LOW" "Cookie missing HttpOnly attribute"
        }
        printf '%s\n' "$cookie" | grep -qi 'samesite=' || {
            printf 'WARN\tMissing SameSite\t%s\n' "$cookie" >> "$REPORT_DIR/cookie_findings.tsv"
            add_finding "LOW" "Cookie missing SameSite attribute"
        }
    done
}

check_tls_certificate() {
    local output="$REPORT_DIR/tls.txt"
    local cert_file="$REPORT_DIR/tls_cert.pem"
    local enddate
    local subject
    local issuer
    local san
    local tls_timeout

    : > "$output"

    if [[ "$URL" != https://* ]]; then
        echo "Skipped: target URL is not HTTPS" > "$output"
        return
    fi

    tls_timeout="${TIMEOUT%.*}"
    [[ -z "$tls_timeout" || "$tls_timeout" -lt 1 ]] && tls_timeout=20

    if ! timeout "$((tls_timeout + 5))" openssl s_client -servername "$DOMAIN" -connect "${DOMAIN}:443" </dev/null 2>/dev/null \
        | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' > "$cert_file"; then
        echo "TLS check failed" > "$output"
        add_finding "LOW" "TLS certificate check failed"
        return
    fi

    if [[ ! -s "$cert_file" ]]; then
        echo "TLS certificate not captured" > "$output"
        add_finding "LOW" "TLS certificate not captured"
        return
    fi

    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null)
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null)
    enddate=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    san=$(openssl x509 -in "$cert_file" -noout -ext subjectAltName 2>/dev/null | sed '1d')

    {
        echo "$subject"
        echo "$issuer"
        echo "notAfter=$enddate"
        echo "SubjectAltName:"
        echo "$san"
    } > "$output"

    if ! openssl x509 -in "$cert_file" -checkend 2592000 -noout >/dev/null 2>&1; then
        add_finding "MEDIUM" "TLS certificate expires within 30 days or is expired"
        echo "WARN	Certificate expires within 30 days or is expired" >> "$output"
    fi
}

build_auth_surface() {
    local output="$REPORT_DIR/auth_surface.tsv"

    : > "$output"

    if [[ -s "$REPORT_DIR/forms.tsv" ]]; then
        awk -F '\t' '$1 ~ /login|upload|post/ {print "FORM\t" $1 "\t" $2}' "$REPORT_DIR/forms.tsv" >> "$output"
    fi

    if [[ -s "$REPORT_DIR/admin_found.tsv" ]]; then
        awk -F '\t' '{print "ADMIN_PATH\t" $1 "\t" $2}' "$REPORT_DIR/admin_found.tsv" >> "$output"
    fi

    if [[ -s "$REPORT_DIR/js_endpoints.txt" ]]; then
        grep -Ei 'login|auth|token|user|admin|upload|graphql' "$REPORT_DIR/js_endpoints.txt" \
            | awk '{print "JS_ENDPOINT\tMATCH\t" $0}' >> "$output"
    fi

    sort -u "$output" -o "$output"
    if [[ -s "$output" ]]; then
        add_finding "LOW" "Authentication or upload surface discovered"
    fi
}

html_escape_file() {
    local file="$1"
    if [[ -s "$file" ]]; then
        sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$file"
    else
        printf 'No data\n'
    fi
}

json_array_from_tsv() {
    local file="$1"
    local columns="$2"

    if [[ -s "$file" ]]; then
        jq -Rn --arg file "$file" --argjson columns "$columns" '
            [inputs
             | select(length > 0)
             | split("\t")
             | if $columns == 2 then {field1: .[0], field2: .[1]}
               elif $columns == 3 then {field1: .[0], field2: .[1], field3: .[2]}
               elif $columns == 4 then {field1: .[0], field2: .[1], field3: .[2], field4: .[3]}
               else {raw: .}
               end]
        ' "$file"
    else
        echo '[]'
    fi
}

json_array_from_lines() {
    local file="$1"
    if [[ -s "$file" ]]; then
        jq -Rn '[inputs | select(length > 0)]' "$file"
    else
        echo '[]'
    fi
}

json_array_file_from_tsv() {
    local src="$1"
    local columns="$2"
    local output="$3"

    if [[ -s "$src" ]]; then
        jq -Rn --argjson columns "$columns" '
            [inputs
             | select(length > 0)
             | split("\t")
             | if $columns == 2 then {field1: .[0], field2: .[1]}
               elif $columns == 3 then {field1: .[0], field2: .[1], field3: .[2]}
               elif $columns == 4 then {field1: .[0], field2: .[1], field3: .[2], field4: .[3]}
               else {raw: .}
               end]
        ' "$src" > "$output"
    else
        printf '[]\n' > "$output"
    fi
}

json_array_file_from_lines() {
    local src="$1"
    local output="$2"
    if [[ -s "$src" ]]; then
        jq -Rn '[inputs | select(length > 0)]' "$src" > "$output"
    else
        printf '[]\n' > "$output"
    fi
}

generate_html_report() {
    local output="$REPORT_DIR/report.html"

    cat > "$output" <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Crawler Report - ${DOMAIN}</title>
<style>
:root{--bg:#f5f7fa;--panel:#fff;--ink:#18202a;--muted:#667085;--line:#d9e0e8}
body{font-family:Arial,sans-serif;margin:0;background:var(--bg);color:var(--ink)}
header{background:#111827;color:white;padding:26px}
main{max-width:1180px;margin:0 auto;padding:20px}
section{background:var(--panel);border:1px solid var(--line);border-radius:6px;margin:14px 0;padding:16px}
h1,h2{margin:0 0 10px}
.meta{color:#d0d5dd;margin-top:6px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:12px;margin:14px 0}
.card{background:white;border:1px solid var(--line);border-radius:6px;padding:14px}
.label{color:var(--muted);font-size:12px;text-transform:uppercase}
.value{font-size:22px;font-weight:bold;margin-top:6px}
pre{white-space:pre-wrap;word-break:break-word;background:#f2f4f7;padding:12px;border-radius:4px;overflow:auto;max-height:420px}
.risk{font-size:20px;font-weight:bold}
.HIGH{color:#b42318}.MEDIUM{color:#b54708}.LOW{color:#067647}.INFO{color:#175cd3}
</style>
</head>
<body>
<header>
<h1>Crawler Report</h1>
<div class="meta">${DOMAIN}</div>
<div class="risk ${LEVEL}">Risk: ${LEVEL} (${SCORE}/100)</div>
</header>
<main>
<div class="grid">
<div class="card"><div class="label">Admin Hits</div><div class="value">$(safe_line_count "$REPORT_DIR/admin_found.tsv")</div></div>
<div class="card"><div class="label">Forms</div><div class="value">$(safe_line_count "$REPORT_DIR/forms.tsv")</div></div>
<div class="card"><div class="label">Pages</div><div class="value">$(safe_line_count "$REPORT_DIR/crawled_pages.tsv")</div></div>
<div class="card"><div class="label">JS Endpoints</div><div class="value">$(safe_line_count "$REPORT_DIR/js_endpoints.txt")</div></div>
<div class="card"><div class="label">Dir Listing</div><div class="value">$(safe_line_count "$REPORT_DIR/directory_listing.tsv")</div></div>
</div>
<section><h2>Summary</h2><pre>$(html_escape_file "$REPORT_DIR/summary.txt")</pre></section>
<section><h2>Risk Findings</h2><pre>$(html_escape_file "$REPORT_DIR/risk_findings.tsv")</pre></section>
<section><h2>HTTP Methods</h2><pre>$(html_escape_file "$REPORT_DIR/http_methods.tsv")</pre></section>
<section><h2>Security Headers</h2><pre>$(html_escape_file "$REPORT_DIR/security_headers.txt")</pre></section>
<section><h2>CSP Analysis</h2><pre>$(html_escape_file "$REPORT_DIR/csp_analysis.txt")</pre></section>
<section><h2>Clickjacking</h2><pre>$(html_escape_file "$REPORT_DIR/clickjacking.txt")</pre></section>
<section><h2>CORS</h2><pre>$(html_escape_file "$REPORT_DIR/cors.txt")</pre></section>
<section><h2>CORS Reflection</h2><pre>$(html_escape_file "$REPORT_DIR/cors_reflection.txt")</pre></section>
<section><h2>Host Header Reflection</h2><pre>$(html_escape_file "$REPORT_DIR/host_header_reflection.txt")</pre></section>
<section><h2>TLS Certificate</h2><pre>$(html_escape_file "$REPORT_DIR/tls.txt")</pre></section>
<section><h2>WAF/CDN</h2><pre>$(html_escape_file "$REPORT_DIR/waf_cdn.txt")</pre></section>
<section><h2>External Tools</h2><pre>$(html_escape_file "$REPORT_DIR/external_tools.txt")</pre></section>
<section><h2>Nuclei Findings</h2><pre>$(html_escape_file "$REPORT_DIR/nuclei_findings.txt")</pre></section>
<section><h2>httpx</h2><pre>$(html_escape_file "$REPORT_DIR/httpx.txt")</pre></section>
<section><h2>Katana URLs</h2><pre>$(html_escape_file "$REPORT_DIR/katana_urls.txt")</pre></section>
<section><h2>Cookies</h2><pre>$(html_escape_file "$REPORT_DIR/cookies.txt")</pre><pre>$(html_escape_file "$REPORT_DIR/cookie_findings.tsv")</pre></section>
<section><h2>Forms</h2><pre>$(html_escape_file "$REPORT_DIR/forms.tsv")</pre></section>
<section><h2>Crawled Pages</h2><pre>$(html_escape_file "$REPORT_DIR/crawled_pages.tsv")</pre></section>
<section><h2>Directory Listing</h2><pre>$(html_escape_file "$REPORT_DIR/directory_listing.tsv")</pre></section>
<section><h2>Auth Surface</h2><pre>$(html_escape_file "$REPORT_DIR/auth_surface.tsv")</pre></section>
<section><h2>Open Redirect Candidates</h2><pre>$(html_escape_file "$REPORT_DIR/open_redirect_candidates.tsv")</pre></section>
<section><h2>SSRF/LFI/RFI Candidates</h2><pre>$(html_escape_file "$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv")</pre></section>
<section><h2>GraphQL</h2><pre>$(html_escape_file "$REPORT_DIR/graphql.tsv")</pre></section>
<section><h2>Well-Known Audit</h2><pre>$(html_escape_file "$REPORT_DIR/well_known.tsv")</pre></section>
<section><h2>Cloud Storage Candidates</h2><pre>$(html_escape_file "$REPORT_DIR/cloud_storage_candidates.tsv")</pre></section>
<section><h2>Dependency Versions</h2><pre>$(html_escape_file "$REPORT_DIR/dependency_versions.tsv")</pre></section>
<section><h2>Sensitive Keywords</h2><pre>$(html_escape_file "$REPORT_DIR/sensitive_keywords.tsv")</pre></section>
<section><h2>WordPress Passive Audit</h2><pre>$(html_escape_file "$REPORT_DIR/wordpress_audit.tsv")</pre></section>
<section><h2>Tech Fingerprint</h2><pre>$(html_escape_file "$REPORT_DIR/tech_fingerprint.txt")</pre></section>
<section><h2>JS Endpoints</h2><pre>$(html_escape_file "$REPORT_DIR/js_endpoints.txt")</pre></section>
<section><h2>Robots Paths</h2><pre>$(html_escape_file "$REPORT_DIR/robots_paths.txt")</pre></section>
<section><h2>crt.sh Subdomains</h2><pre>$(html_escape_file "$REPORT_DIR/crtsh_subdomains.txt")</pre></section>
<section><h2>Sitemap Pages</h2><pre>$(html_escape_file "$REPORT_DIR/sitemap_pages.txt")</pre></section>
<section><h2>Interesting Files</h2><pre>$(html_escape_file "$REPORT_DIR/interesting_files.tsv")</pre></section>
<section><h2>Admin Hits</h2><pre>$(html_escape_file "$REPORT_DIR/admin_found.tsv")</pre></section>
<section><h2>External Directory Scan</h2><pre>$(html_escape_file "$REPORT_DIR/external_dirscan.txt")</pre></section>
<section><h2>Cache</h2><pre>$(html_escape_file "$REPORT_DIR/cache.tsv")</pre></section>
</main>
</body>
</html>
EOF
}

generate_json_report() {
    local output="$REPORT_DIR/report.json"
    local risk_findings_json_file="$REPORT_DIR/.risk_findings.json"
    local admin_hits_json_file="$REPORT_DIR/.admin_hits.json"
    local redirects_json_file="$REPORT_DIR/.open_redirect_candidates.json"
    local ssrf_json_file="$REPORT_DIR/.ssrf_lfi_rfi_candidates.json"
    local graphql_json_file="$REPORT_DIR/.graphql.json"
    local well_known_json_file="$REPORT_DIR/.well_known.json"
    local http_methods_json_file="$REPORT_DIR/.http_methods.json"
    local security_headers_json_file="$REPORT_DIR/.security_headers.json"
    local cookies_json_file="$REPORT_DIR/.cookies.json"
    local forms_json_file="$REPORT_DIR/.forms.json"
    local crawled_pages_json_file="$REPORT_DIR/.crawled_pages.json"
    local directory_listing_json_file="$REPORT_DIR/.directory_listing.json"
    local auth_surface_json_file="$REPORT_DIR/.auth_surface.json"
    local sensitive_keywords_json_file="$REPORT_DIR/.sensitive_keywords.json"
    local wordpress_audit_json_file="$REPORT_DIR/.wordpress_audit.json"
    local tech_fingerprint_json_file="$REPORT_DIR/.tech_fingerprint.json"
    local waf_cdn_json_file="$REPORT_DIR/.waf_cdn.json"
    local external_tools_json_file="$REPORT_DIR/.external_tools.json"
    local nuclei_json_file="$REPORT_DIR/.nuclei_findings.json"
    local httpx_json_file="$REPORT_DIR/.httpx.json"
    local katana_json_file="$REPORT_DIR/.katana_urls.json"
    local crc_json_file="$REPORT_DIR/.crtsh_subdomains.json"

    json_array_file_from_tsv "$REPORT_DIR/risk_findings.tsv" 2 "$risk_findings_json_file"
    json_array_file_from_tsv "$REPORT_DIR/admin_found.tsv" 2 "$admin_hits_json_file"
    json_array_file_from_lines "$REPORT_DIR/open_redirect_candidates.tsv" "$redirects_json_file"
    json_array_file_from_lines "$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv" "$ssrf_json_file"
    json_array_file_from_lines "$REPORT_DIR/graphql.tsv" "$graphql_json_file"
    json_array_file_from_lines "$REPORT_DIR/well_known.tsv" "$well_known_json_file"
    json_array_file_from_lines "$REPORT_DIR/http_methods.tsv" "$http_methods_json_file"
    json_array_file_from_lines "$REPORT_DIR/security_headers.txt" "$security_headers_json_file"
    json_array_file_from_lines "$REPORT_DIR/cookies.txt" "$cookies_json_file"
    json_array_file_from_lines "$REPORT_DIR/forms.tsv" "$forms_json_file"
    json_array_file_from_lines "$REPORT_DIR/crawled_pages.tsv" "$crawled_pages_json_file"
    json_array_file_from_lines "$REPORT_DIR/directory_listing.tsv" "$directory_listing_json_file"
    json_array_file_from_lines "$REPORT_DIR/auth_surface.tsv" "$auth_surface_json_file"
    json_array_file_from_lines "$REPORT_DIR/sensitive_keywords.tsv" "$sensitive_keywords_json_file"
    json_array_file_from_lines "$REPORT_DIR/wordpress_audit.tsv" "$wordpress_audit_json_file"
    json_array_file_from_lines "$REPORT_DIR/tech_fingerprint.txt" "$tech_fingerprint_json_file"
    json_array_file_from_lines "$REPORT_DIR/waf_cdn.txt" "$waf_cdn_json_file"
    json_array_file_from_lines "$REPORT_DIR/external_tools.txt" "$external_tools_json_file"
    json_array_file_from_lines "$REPORT_DIR/nuclei_findings.txt" "$nuclei_json_file"
    json_array_file_from_lines "$REPORT_DIR/httpx.txt" "$httpx_json_file"
    json_array_file_from_lines "$REPORT_DIR/katana_urls.txt" "$katana_json_file"
    json_array_file_from_lines "$REPORT_DIR/crtsh_subdomains.txt" "$crc_json_file"

    jq -n \
        --arg domain "$DOMAIN" \
        --arg target_url "$REAL" \
        --arg base_url "$URL" \
        --arg profile "$PROFILE" \
        --arg report_dir "$REPORT_DIR" \
        --arg cache_dir "$CACHE_DIR" \
        --argjson risk_score "${SCORE:-0}" \
        --arg risk_level "${LEVEL:-INFO}" \
        --rawfile risk_findings "$risk_findings_json_file" \
        --rawfile admin_hits "$admin_hits_json_file" \
        --rawfile open_redirect_candidates "$redirects_json_file" \
        --rawfile ssrf_lfi_rfi_candidates "$ssrf_json_file" \
        --rawfile graphql "$graphql_json_file" \
        --rawfile well_known "$well_known_json_file" \
        --rawfile http_methods "$http_methods_json_file" \
        --rawfile security_headers "$security_headers_json_file" \
        --rawfile cookies "$cookies_json_file" \
        --rawfile forms "$forms_json_file" \
        --rawfile crawled_pages "$crawled_pages_json_file" \
        --rawfile directory_listing "$directory_listing_json_file" \
        --rawfile auth_surface "$auth_surface_json_file" \
        --rawfile sensitive_keywords "$sensitive_keywords_json_file" \
        --rawfile wordpress_audit "$wordpress_audit_json_file" \
        --rawfile tech_fingerprint "$tech_fingerprint_json_file" \
        --rawfile waf_cdn "$waf_cdn_json_file" \
        --rawfile external_tools "$external_tools_json_file" \
        --rawfile nuclei_findings "$nuclei_json_file" \
        --rawfile httpx "$httpx_json_file" \
        --rawfile katana_urls "$katana_json_file" \
        --rawfile crtsh_subdomains "$crc_json_file" \
        '{
            domain: $domain,
            target_url: $target_url,
            base_url: $base_url,
            profile: $profile,
            report_dir: $report_dir,
            cache_dir: $cache_dir,
            risk: {level: $risk_level, score: $risk_score},
            counts: {
                risk_findings: ($risk_findings | fromjson | length),
                admin_hits: ($admin_hits | fromjson | length),
                open_redirect_candidates: ($open_redirect_candidates | fromjson | length),
                ssrf_lfi_rfi_candidates: ($ssrf_lfi_rfi_candidates | fromjson | length),
                graphql: ($graphql | fromjson | length),
                well_known: ($well_known | fromjson | length),
                http_methods: ($http_methods | fromjson | length),
                security_headers: ($security_headers | fromjson | length),
                cookies: ($cookies | fromjson | length),
                forms: ($forms | fromjson | length),
                crawled_pages: ($crawled_pages | fromjson | length),
                directory_listing: ($directory_listing | fromjson | length),
                auth_surface: ($auth_surface | fromjson | length),
                sensitive_keywords: ($sensitive_keywords | fromjson | length),
                wordpress_audit: ($wordpress_audit | fromjson | length),
                tech_fingerprint: ($tech_fingerprint | fromjson | length),
                waf_cdn: ($waf_cdn | fromjson | length),
                external_tools: ($external_tools | fromjson | length),
                nuclei_findings: ($nuclei_findings | fromjson | length),
                httpx: ($httpx | fromjson | length),
                katana_urls: ($katana_urls | fromjson | length),
                crtsh_subdomains: ($crtsh_subdomains | fromjson | length)
            },
            risk_findings: ($risk_findings | fromjson),
            admin_hits: ($admin_hits | fromjson),
            open_redirect_candidates: ($open_redirect_candidates | fromjson),
            ssrf_lfi_rfi_candidates: ($ssrf_lfi_rfi_candidates | fromjson),
            graphql: ($graphql | fromjson),
            well_known: ($well_known | fromjson),
            http_methods: ($http_methods | fromjson),
            security_headers: ($security_headers | fromjson),
            cookies: ($cookies | fromjson),
            forms: ($forms | fromjson),
            crawled_pages: ($crawled_pages | fromjson),
            directory_listing: ($directory_listing | fromjson),
            auth_surface: ($auth_surface | fromjson),
            sensitive_keywords: ($sensitive_keywords | fromjson),
            wordpress_audit: ($wordpress_audit | fromjson),
            tech_fingerprint: ($tech_fingerprint | fromjson),
            waf_cdn: ($waf_cdn | fromjson),
            external_tools: ($external_tools | fromjson),
            nuclei_findings: ($nuclei_findings | fromjson),
            httpx: ($httpx | fromjson),
            katana_urls: ($katana_urls | fromjson),
            crtsh_subdomains: ($crtsh_subdomains | fromjson)
        }' > "$output"
}


if [ -f user_agents.txt ] && [ -f "$WORDLIST" ]; then
    tor_pid=$(pgrep -x tor 2>/dev/null)

    curl -fsS --max-time 10 ident.me &> /dev/null
    if [ $? -eq 0 ]; then
      if [[ "$USE_TOR" -eq 1 && -z "$tor_pid" ]]; then
        clear
        echo " [+] Please Running your tor"
        echo " [!] Tor is not running or you are not connected through Tor."
        exit 1
      else
# Daftar command dan paket yang diperlukan: command:nama_paket
required_packages=(
    "openssl:openssl"
    "nmap:nmap"
    "curl:curl"
    "dig:dnsutils"
    "nslookup:dnsutils"
    "whois:whois"
    "jq:jq"
    "tor:tor"
    "torsocks:torsocks"
    "shuf:coreutils"
    "timeout:coreutils"
    "tput:ncurses-utils"
)

# Fungsi untuk memeriksa command dan menginstal paket jika belum ada.
function check_and_install_package() {
    local command_name="$1"
    local package_name="$2"

    if ! command -v "$command_name" &> /dev/null; then
        echo -e "Paket $package_name untuk command $command_name tidak ditemukan. Menginstal paket..."
        if [[ -n $(command -v pkg) ]]; then
            pkg install -y "$package_name" &> /dev/null
        elif [[ -n $(command -v apt-get) ]]; then
            sudo apt-get install -y "$package_name" &> /dev/null
        elif [[ -n $(command -v yum) ]]; then
            sudo yum install -y "$package_name" &> /dev/null
        else
            echo -e "Sistem operasi tidak didukung. Silakan instal paket $package_name secara manual."
            exit 1
        fi

        if ! command -v "$command_name" &> /dev/null; then
            echo -e "Command $command_name masih belum tersedia setelah instalasi paket $package_name."
            exit 1
        fi
    fi
}

# Memeriksa dan menginstal setiap paket dalam daftar.
for package in "${required_packages[@]}"; do
    if [[ "$USE_TOR" -eq 0 && ( "${package%%:*}" == "tor" || "${package%%:*}" == "torsocks" ) ]]; then
        continue
    fi
    check_and_install_package "${package%%:*}" "${package#*:}"
done

if ! is_positive_integer "$THREADS"; then
    echo -e "Threads harus angka bulat lebih dari 0."
    exit 1
fi

if ! is_positive_number "$TIMEOUT"; then
    echo -e "Timeout harus angka lebih dari 0."
    exit 1
fi

if ! is_positive_number "$DELAY"; then
    echo -e "Delay harus angka 0 atau lebih."
    exit 1
fi

if ! is_positive_integer "$MAX_PAGES"; then
    echo -e "Max pages harus angka bulat lebih dari 0."
    exit 1
fi

RUN_EXTERNAL_PROBERS=1
RUN_EXTERNAL_DIRSCAN=1
RUN_WP_AUDIT=1
RUN_INTERNAL_CRAWL=1

case "$PROFILE" in
    quick)
        RUN_EXTERNAL_PROBERS=0
        RUN_EXTERNAL_DIRSCAN=0
        RUN_WP_AUDIT=0
        RUN_INTERNAL_CRAWL=0
        [[ "$THREADS" == "5" ]] && THREADS=3
        [[ "$MAX_PAGES" == "20" ]] && MAX_PAGES=10
        ;;
    normal)
        ;;
    deep)
        [[ "$THREADS" == "5" ]] && THREADS=10
        [[ "$MAX_PAGES" == "20" ]] && MAX_PAGES=50
        [[ "$TIMEOUT" == "20" ]] && TIMEOUT=30
        ;;
    *)
        echo -e "Profile harus salah satu dari: quick, normal, deep."
        exit 1
        ;;
esac

if [[ "$CHECK_TOOLS" -eq 1 ]]; then
    check_optional_tools
    exit 0
fi

clear

# Function to generate a random color code
generate_random_color() {
    echo $((RANDOM % 256))
}
# Function to print a colorful centered banner box                print_centered_banner_box() {
print_centered_banner_box() {
    local message="$1"
    local length=${#message}
    local terminal_width=$(tput cols 2>/dev/null || echo 80)
    local border_char="="
    local padding_char=" "
    local num_colors=6  # Number of available colors
    local random_color1=$(generate_random_color)
    local random_color2=$(generate_random_color)

    # Calculate the width of the box
    local box_width=$((length + 4))

    # Calculate the left padding
    local left_padding=$(( (terminal_width - box_width) / 2 ))

    # Print the top border
    printf "\e[38;5;${random_color1}m%${left_padding}s" ""
    for ((i = 0; i < box_width; i++)); do
        printf "${border_char}"
    done
    printf "\e[0m\n"

    # Print the message line with alternating colors
    printf "\e[38;5;${random_color2}m%${left_padding}s${border_char}${padding_char}${message}${padding_char}${border_char}\e[0m\n"

    # Print the bottom border
    printf "\e[38;5;${random_color1}m%${left_padding}s" ""
    for ((i = 0; i < box_width; i++)); do
        printf "${border_char}"
    done
    printf "\e[0m\n"
}

# Usage example
print_centered_banner_box "Created By ghalangwh-official"

# get information from user
PUBLIC_IP=$(http_get -fsS --max-time 15 ident.me 2>/dev/null)
echo -e "\n ${p}[${m}+${p}] ${b}Information from me ${m}: ${hg}\n $(curl -fsS --max-time 15 "http://ip-api.com/json/${PUBLIC_IP}" 2>/dev/null | jq | tr -d '{}",')"

# Menerima input dari pengguna
if [[ -n "$TARGET_URL" ]]; then
    URL="$TARGET_URL"
else
    echo -n -e "\n ${p}[${mg}?${p}] ${kg}Masukkan ${mg}URL ${p}(${ag}http${m}/${a}https${p})${u}:${ug} "; read -r URL
fi

# Validate the URL immediately after input
if ! validate_url "$URL"; then
    echo -e " ${p}[${h}!${p}] ${m}Invalid or dangerous URL provided"
    exit 1
fi

printf '%s\n' "$URL" > .history_url_real.bak
REAL=$(cat .history_url_real.bak)

# Menghapus path/query setelah domain.
URL=$(echo "$URL" | sed -E 's#^(https?://[^/]*).*#\1#')

# Mengubah URL menjadi huruf kecil
URL=$(echo "$URL" | tr '[:upper:]' '[:lower:]')

# Menghapus garis miring diakhir URL jika ada
URL=$(echo "$URL" | sed 's:/$::')

# Memeriksa apakah input dimulai dengan "http://" atau "https://"
if [[ $URL =~ ^(http|https):// ]]; then
    # Menampilkan response
    echo -e "\n ${p}[${mg}+${mg}${p}] ${kg}URL ${ug}: $REAL\n"
    RESPONSE=$(http_status "${REAL}")
    if [[ $RESPONSE =~ ^(000|404)$ ]]; then
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
        echo -e " ${p}[${a}!${p}] ${m}website/url Not found"
        exit
    elif [[ $RESPONSE == "200" ]]; then
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
    else
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${ug}${REAL} ${mg}- ${ug}Code: ${ag}[${mg}${RESPONSE}${ag}]"
    fi
# Memeriksa apakah input dimulai dengan https/http
else
    echo -e " ${p}[${h}!${p}] ${ug}URL : ${k}${REAL} ${m}tidak valid"
    exit 1
fi

DOMAIN=$(echo "$URL" | sed -e 's|^[^/]*//||' -e 's|/.*$||')
if [[ "$DOMAIN" == *.*.* ]]; then
    NOT_SUB="${DOMAIN#*.}"
else
    NOT_SUB="$DOMAIN"
fi
REPORT_DIR="${REPORT_ROOT}/$(sanitize_filename "$DOMAIN")-$(date +%Y%m%d-%H%M%S)"
CACHE_DIR="${CACHE_ROOT}/$(sanitize_filename "$DOMAIN")"
mkdir -p "$REPORT_DIR"
: > "$REPORT_DIR/risk_findings.tsv"
: > "$REPORT_DIR/cache.tsv"

{
    echo "Target URL  : $REAL"
    echo "Base URL    : $URL"
    echo "Domain      : $DOMAIN"
    echo "Use Tor     : $USE_TOR"
    echo "Threads     : $THREADS"
    echo "Max pages   : $MAX_PAGES"
    echo "Timeout     : $TIMEOUT"
    echo "Delay       : $DELAY"
    echo "Wordlist    : $WORDLIST"
    echo "Cache       : $USE_CACHE"
    echo "Cache dir   : $CACHE_DIR"
    echo "Started at  : $(date)"
} > "$REPORT_DIR/summary.txt"

print_centered_banner_box "get the information on web"
MAIN_HTML=$(cached_body "$REAL")
MAIN_HTML_LOWER=$(printf '%s\n' "$MAIN_HTML" | tr '[:upper:]' '[:lower:]')
TITLE=$(printf '%s\n' "$MAIN_HTML" | awk -F '</?title>' 'NF>2 {print $2; exit}')
HOME_BODY_SIG=$(printf '%s' "$MAIN_HTML" | body_signature)
HOME_TITLE="$TITLE"
SERVER=$(http_get -fsSLI --max-time "$TIMEOUT" "$REAL" 2>/dev/null | awk -F': ' 'tolower($1) == "server" {print $2}')
echo -e "\n Title    : $TITLE"
echo -e " Server   : $SERVER"
{
    echo "Title  : $TITLE"
    echo "Server : $SERVER"
} >> "$REPORT_DIR/summary.txt"

print_centered_banner_box "Contact"
CONTACTS=$(printf '%s\n' "$MAIN_HTML" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}|[[:alnum:]+\.\_\-]+@[[:alnum:]+\.\_\-]+\.[[:alpha:]]+' | sed 's/^[[:space:]]*//' | sort -u)
echo -e " Contact  : \n$CONTACTS"
printf '%s\n' "$CONTACTS" > "$REPORT_DIR/contacts.txt"

print_centered_banner_box "Ekstrak link"
LINKS=$(printf '%s\n' "$MAIN_HTML" | grep -o 'href="[^"]*"' | sed 's/href="//;s/"//g' | grep -Eo 'http[s]?://[^ ]+' | sort -u)
echo -e " Get_Link  : \n$LINKS"
printf '%s\n' "$LINKS" > "$REPORT_DIR/links.txt"

print_centered_banner_box "JS Endpoint Extractor"
extract_js_endpoints "$MAIN_HTML"
if [[ -s "$REPORT_DIR/js_endpoints.txt" ]]; then
    cat "$REPORT_DIR/js_endpoints.txt"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan endpoint menarik dari file JS"
fi

print_centered_banner_box "Sensitive Keyword Detector"
detect_sensitive_keywords
if [[ -s "$REPORT_DIR/sensitive_keywords.tsv" ]]; then
    cat "$REPORT_DIR/sensitive_keywords.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan keyword sensitif di HTML/JS"
fi

print_centered_banner_box "Cloud Storage Candidates"
detect_cloud_storage_candidates
if [[ -s "$REPORT_DIR/cloud_storage_candidates.tsv" ]]; then
    cat "$REPORT_DIR/cloud_storage_candidates.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan kandidat cloud storage URL"
fi

print_centered_banner_box "Dependency Version Disclosure"
detect_dependency_versions
if [[ -s "$REPORT_DIR/dependency_versions.tsv" ]]; then
    cat "$REPORT_DIR/dependency_versions.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan kandidat versi dependency"
fi

print_centered_banner_box "Multipage Crawler and Form Detector"
if [[ "$RUN_INTERNAL_CRAWL" -eq 1 ]]; then
    crawl_internal_pages
    echo -e " Crawled pages : $(safe_line_count "$REPORT_DIR/crawled_pages.tsv")"
    echo -e " Forms found   : $(safe_line_count "$REPORT_DIR/forms.tsv")"
    echo -e " Dir listing   : $(safe_line_count "$REPORT_DIR/directory_listing.tsv")"
    if [[ -s "$REPORT_DIR/forms.tsv" ]]; then
        cat "$REPORT_DIR/forms.tsv"
    fi
    if [[ -s "$REPORT_DIR/directory_listing.tsv" ]]; then
        cat "$REPORT_DIR/directory_listing.tsv"
    fi
else
    echo -e " ${p}[${h}!${p}] ${m}Skipped in quick profile"
fi


# Nmap Info
   echo -e "\n"
   print_centered_banner_box "Nmap"
   NMAP_INFO=$(nmap "$DOMAIN")
   echo -e " ${m}${NMAP_INFO}\n"
   printf '%s\n' "$NMAP_INFO" > "$REPORT_DIR/nmap.txt"

# Subdomain
   echo -e "\n"
   print_centered_banner_box "Subdomain"
   SUBDOMAIN_INFO=$(nmap -sn --script hostmap-crtsh "$NOT_SUB")
   echo -e " ${c}${SUBDOMAIN_INFO}\n"
   printf '%s\n' "$SUBDOMAIN_INFO" > "$REPORT_DIR/subdomains.txt"

   print_centered_banner_box "crt.sh Passive Subdomains"
   crtsh_subdomains
   cat "$REPORT_DIR/crtsh_subdomains.txt"

# Whois
   echo -e "\n"
   print_centered_banner_box "Whois"
   WHOIS_INFO=$(whois "$NOT_SUB")
   echo -e "${WHOIS_INFO}\n"
   printf '%s\n' "$WHOIS_INFO" > "$REPORT_DIR/whois.txt"

# Dns Lookup
   print_centered_banner_box "Nslookup"
   NSLOOKUP_INFO=$(nslookup "$DOMAIN")
   echo -e "${hg}${NSLOOKUP_INFO} \n"
   printf '%s\n' "$NSLOOKUP_INFO" > "$REPORT_DIR/nslookup.txt"

# Dig information
   print_centered_banner_box "Dig information"
   DIG_INFO=$(dig "$DOMAIN")
   echo -e " ${bg}${DIG_INFO} \n"
   printf '%s\n' "$DIG_INFO" > "$REPORT_DIR/dig.txt"

# Information with curl
   print_centered_banner_box "Header Website"
   echo -e "${kg}\n"
   HEADERS=$(http_get -sLI --max-time "$TIMEOUT" -A "$(shuf -n 1 user_agents.txt)" "${URL}")
   HEADERS_LOWER=$(printf '%s\n' "$HEADERS" | tr '[:upper:]' '[:lower:]')
   echo "$HEADERS"
   printf '%s\n' "$HEADERS" > "$REPORT_DIR/headers.txt"

# Security headers
   print_centered_banner_box "Security Headers"
   check_security_headers "$HEADERS_LOWER"
   cat "$REPORT_DIR/security_headers.txt"

# HTTP methods
   print_centered_banner_box "HTTP Method Audit"
   check_http_methods
   cat "$REPORT_DIR/http_methods.tsv"

# CSP analyzer
   print_centered_banner_box "CSP Analyzer"
   analyze_csp
   cat "$REPORT_DIR/csp_analysis.txt"

# Clickjacking
   print_centered_banner_box "Clickjacking Check"
   check_clickjacking
   cat "$REPORT_DIR/clickjacking.txt"

# CORS
   print_centered_banner_box "CORS Check"
   check_cors
   cat "$REPORT_DIR/cors.txt"

   print_centered_banner_box "CORS Origin Reflection"
   check_cors_reflection
   cat "$REPORT_DIR/cors_reflection.txt"

   print_centered_banner_box "Host Header Reflection"
   check_host_header_reflection
   cat "$REPORT_DIR/host_header_reflection.txt"

# Cookie security
   print_centered_banner_box "Cookie Security"
   : > "$REPORT_DIR/cookie_findings.tsv"
   check_cookie_security
   cat "$REPORT_DIR/cookies.txt"
   if [[ -s "$REPORT_DIR/cookie_findings.tsv" ]]; then
       cat "$REPORT_DIR/cookie_findings.tsv"
   fi

# Tech fingerprint
   print_centered_banner_box "Tech Fingerprint"
   fingerprint_tech "$HEADERS_LOWER" "$MAIN_HTML_LOWER"
   if [[ -s "$REPORT_DIR/tech_fingerprint.txt" ]]; then
       cat "$REPORT_DIR/tech_fingerprint.txt"
   else
       echo -e " ${p}[${h}!${p}] ${m}Tech stack belum terdeteksi"
   fi

# WordPress passive audit
   print_centered_banner_box "WordPress Passive Audit"
   if [[ "$RUN_WP_AUDIT" -eq 1 ]]; then
       wordpress_passive_audit
       cat "$REPORT_DIR/wordpress_audit.tsv"
   else
       echo -e " ${p}[${h}!${p}] ${m}Skipped in quick profile"
   fi

# WAF/CDN detector
   print_centered_banner_box "WAF CDN Detector"
   detect_waf_cdn "$HEADERS_LOWER" "$MAIN_HTML_LOWER"
   if [[ -s "$REPORT_DIR/waf_cdn.txt" ]]; then
       cat "$REPORT_DIR/waf_cdn.txt"
   else
       echo -e " ${p}[${h}!${p}] ${m}WAF/CDN belum terdeteksi"
   fi

# TLS certificate
   print_centered_banner_box "TLS Certificate"
   check_tls_certificate
   cat "$REPORT_DIR/tls.txt"

# Optional external probers
print_centered_banner_box "External Tool Probers"
   if [[ "$RUN_EXTERNAL_PROBERS" -eq 1 ]]; then
       run_external_probers
       cat "$REPORT_DIR/external_tools.txt"
   else
       echo -e " ${p}[${h}!${p}] ${m}Skipped in quick profile"
   fi

# Robots.txt finder
   print_centered_banner_box "Robots Finder"
ROBOTS_FIND=$(http_status "${URL}/robots.txt")
if [[ $ROBOTS_FIND == "200" ]]; then
    ROBOTS_CONTENT=$(cached_body "${URL}/robots.txt")
    echo -e "\b" "$ROBOTS_CONTENT" "\n"
    printf '%s\n' "$ROBOTS_CONTENT" > "$REPORT_DIR/robots.txt"
else
    echo -e "\n [${mg}-${p}] ${kg}Robots.txt ${mg}Not Found \n"
    echo "Robots.txt not found. HTTP status: $ROBOTS_FIND" > "$REPORT_DIR/robots.txt"
fi

print_centered_banner_box "Robots and Sitemap Parser"
parse_robots_and_sitemaps "$ROBOTS_CONTENT"
echo -e " Robots paths : $(safe_line_count "$REPORT_DIR/robots_paths.txt")"
echo -e " Sitemaps     : $(safe_line_count "$REPORT_DIR/sitemap_urls.txt")"
echo -e " Sitemap URLs : $(safe_line_count "$REPORT_DIR/sitemap_pages.txt")"

print_centered_banner_box "Well-Known Endpoint Audit"
audit_well_known
cat "$REPORT_DIR/well_known.tsv"

print_centered_banner_box "GraphQL Detector"
detect_graphql
if [[ -s "$REPORT_DIR/graphql.tsv" ]]; then
    cat "$REPORT_DIR/graphql.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan kandidat GraphQL"
fi

print_centered_banner_box "Parameter Candidate Detector"
detect_parameter_candidates
if [[ -s "$REPORT_DIR/open_redirect_candidates.tsv" ]]; then
    cat "$REPORT_DIR/open_redirect_candidates.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan kandidat open redirect"
fi
if [[ -s "$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv" ]]; then
    cat "$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan kandidat SSRF/LFI/RFI parameter"
fi

print_centered_banner_box "Interesting File Checker"
check_interesting_files
if [[ -s "$REPORT_DIR/interesting_files.tsv" ]]; then
    cat "$REPORT_DIR/interesting_files.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan file menarik yang terbuka/terproteksi"
fi

    print_centered_banner_box "Admin login Finder"

# Fungsi untuk memeriksa URL
check_url() {
    page="$1"
    FULL_URL="$URL/$page"
    RESPONSE=$(http_status "${FULL_URL}")
    local body
    body=$(cached_body "${FULL_URL}" 2>/dev/null || true)

    if [[ -z "$body" || "$(printf '%s' "$body" | body_signature)" == "$HOME_BODY_SIG" ]]; then
        return
    fi

    if is_interesting_status "$RESPONSE"; then
        if [[ "$RESPONSE" == "200" ]] && ! body_looks_adminish "$body"; then
            echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
            return
        fi
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${hg}${RESPONSE}${ag}]"
        printf '%s\t%s\n' "$RESPONSE" "$FULL_URL" >> "$REPORT_DIR/admin_found.tsv"
        if [[ "$RESPONSE" == "200" ]]; then
            add_finding "MEDIUM" "Admin-like path accessible: /$page"
        else
            add_finding "LOW" "Admin-like path discovered with HTTP $RESPONSE: /$page"
        fi
    else
        echo -e " ${p}[${mg}+${p}] ${kg}URL ${mg}- ${bg}${FULL_URL} ${mg}- ${ug}Code: ${ag}[${mg}${RESPONSE}${ag}]"
    fi
}

# URL dan jumlah maksimum thread

max_threads="$THREADS"
: > "$REPORT_DIR/admin_checked.tsv"
: > "$REPORT_DIR/admin_found.tsv"

# Baca setiap baris dari list_page.txt dan jalankan tugas dalam thread
while IFS= read -r page; do
    [[ -z "$page" || "$page" =~ ^[[:space:]]*# ]] && continue

    # Batasi jumlah thread yang sedang berjalan
    while [ $(jobs -r | wc -l) -ge $max_threads ]; do
        sleep 1
    done

    printf '%s\n' "$URL/$page" >> "$REPORT_DIR/admin_checked.tsv"

    # Jalankan tugas dalam subshell (background process)
    (check_url "$page") &

    if [[ "$DELAY" != "0" && "$DELAY" != "0.0" ]]; then
        sleep "$DELAY"
    fi
done < "$WORDLIST"

# Tunggu semua thread selesai
wait


echo -e "\n"
if [[ -s "$REPORT_DIR/admin_found.tsv" ]]; then
print_centered_banner_box "Admin login found"
cat "$REPORT_DIR/admin_found.tsv"
else
print_centered_banner_box "Admin login not found"
echo -e " ${p}[${h}!${p}] ${m}Tidak Dapat Menemukan Admin Login Page, Silahkan Tambahkan page secara manual di list_page.txt"
fi

print_centered_banner_box "External Directory Scanner"
if [[ "$RUN_EXTERNAL_DIRSCAN" -eq 1 ]]; then
    run_external_directory_scan
    cat "$REPORT_DIR/external_dirscan.txt"
else
    echo -e " ${p}[${h}!${p}] ${m}Skipped in quick profile"
fi

print_centered_banner_box "Auth Surface Mapper"
build_auth_surface
if [[ -s "$REPORT_DIR/auth_surface.tsv" ]]; then
    cat "$REPORT_DIR/auth_surface.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak menemukan auth/upload surface dari hasil scan"
fi

SCORE=$(risk_score)
LEVEL=$(risk_level "$SCORE")
print_centered_banner_box "Risk Score"
echo -e " ${p}[${mg}+${p}] ${kg}Risk ${ug}: ${LEVEL} (${SCORE}/100)"
if [[ -s "$REPORT_DIR/risk_findings.tsv" ]]; then
    cat "$REPORT_DIR/risk_findings.tsv"
else
    echo -e " ${p}[${h}!${p}] ${m}Tidak ada temuan risk dari check ringan"
fi

{
    echo
    echo "Finished at : $(date)"
    echo "Report dir  : $REPORT_DIR"
    echo "Admin hits  : $(safe_line_count "$REPORT_DIR/admin_found.tsv")"
    echo "Forms found : $(safe_line_count "$REPORT_DIR/forms.tsv")"
    echo "Pages crawl : $(safe_line_count "$REPORT_DIR/crawled_pages.tsv")"
    echo "Dir listing : $(safe_line_count "$REPORT_DIR/directory_listing.tsv")"
    echo "Auth surf   : $(safe_line_count "$REPORT_DIR/auth_surface.tsv")"
    echo "Sens keys   : $(safe_line_count "$REPORT_DIR/sensitive_keywords.tsv")"
    echo "Redirects   : $(safe_line_count "$REPORT_DIR/open_redirect_candidates.tsv")"
    echo "Param cand  : $(safe_line_count "$REPORT_DIR/ssrf_lfi_rfi_candidates.tsv")"
    echo "GraphQL     : $(safe_line_count "$REPORT_DIR/graphql.tsv")"
    echo "Cloud URLs  : $(safe_line_count "$REPORT_DIR/cloud_storage_candidates.tsv")"
    echo "Cache logs  : $(safe_line_count "$REPORT_DIR/cache.tsv")"
    echo "Risk level  : $LEVEL"
    echo "Risk score  : $SCORE/100"
} >> "$REPORT_DIR/summary.txt"

generate_html_report
generate_json_report

print_centered_banner_box "Report saved"
echo -e " ${p}[${h}+${p}] ${kg}$REPORT_DIR"
echo -e " ${p}[${h}+${p}] ${kg}$REPORT_DIR/report.html"
echo -e " ${p}[${h}+${p}] ${kg}$REPORT_DIR/report.json"

fi

else
echo -e "[•] Please check your internet connection !"
fi

else
echo -e " [•] Please check your file connection !\n [•] Please install this is script on github"
fi
