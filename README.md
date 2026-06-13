# Website Crawler with Bash

> Noted: this tool is for education and authorized testing only.

## Install

```sh
pkg update && pkg upgrade
pkg install openssl nmap curl dnsutils jq tor torsocks whois coreutils ncurses-utils -y
```

## Run with Tor

Start Tor in terminal 1:

```sh
tor
```

Run crawler in terminal 2:

```sh
cd crawler-shell
chmod +x crawl.sh
bash crawl.sh -u https://example.com --tor
```

## Run without Tor

```sh
bash crawl.sh -u https://example.com --no-tor
```

## Useful Options

```sh
bash crawl.sh -u https://example.com --no-tor -t 10 --timeout 15 --delay 0.2
bash crawl.sh -u https://example.com --no-tor --max-pages 30
bash crawl.sh -u https://example.com --no-tor --cache-dir .cache
bash crawl.sh -u https://example.com --no-tor --no-cache
bash crawl.sh -u https://example.com --profile quick
bash crawl.sh --check-tools
bash crawl.sh -u https://example.com -w custom_paths.txt --report-dir reports
```

## Features

- Optional external tool integration: `ffuf`, `dirsearch`, `dirb`, `nuclei`, `httpx`, `katana`
- Passive subdomain lookup via `crt.sh`
- Scan profile mode: `quick`, `normal`, `deep`
- JS endpoint extractor from linked `.js` files
- Risk score with LOW/MEDIUM/HIGH findings
- HTTP method audit for OPTIONS, TRACE, PUT, DELETE, PATCH
- CSP analyzer for unsafe-inline, unsafe-eval, wildcard, object-src, frame-ancestors
- Clickjacking check
- Sensitive keyword detector for HTML/JS sources without dumping values
- Open redirect candidate detector
- SSRF/LFI/RFI parameter candidate detector
- GraphQL endpoint detector
- CORS arbitrary-origin reflection check
- Host header reflection check
- Well-known endpoint audit
- Cloud storage URL candidate detector
- Dependency/version disclosure detector
- WordPress passive audit when WordPress is detected
- Auth surface mapper for login/admin/API/upload endpoints
- Security headers check
- Cookie security check
- CORS check
- TLS certificate check
- WAF/CDN detector
- Directory listing detector
- Robots.txt and sitemap parser
- Lightweight internal multipage crawler
- Form detector for login, upload, search, and POST forms
- Basic tech fingerprinting
- Interesting file checker without dumping sensitive file contents
- Admin path finder with configurable wordlist
- HTML report
- JSON report
- Response body cache for repeat scans

## Optional Tools

The script auto-detects these tools. If they are missing, it falls back to built-in checks.

```sh
pkg install golang python -y
```

Common external tools:

```sh
go install github.com/ffuf/ffuf/v2@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/katana/cmd/katana@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
pip install dirsearch
```

`crt.sh` is useful for passive subdomain discovery because it is free and does not need an API key. It is not a full replacement for `subfinder`: results can be noisy, old, wildcard-heavy, and limited to certificate transparency data. For a light Termux workflow, `crt.sh` is worth using as the default passive source; `subfinder` is still better when you want multiple passive sources.

`--check-tools` prints optional tool availability and exits.

Reports are saved to:

```text
reports/domain-YYYYMMDD-HHMMSS/
```

Important report files:

```text
summary.txt
report.html
report.json
risk_findings.tsv
external_tools.txt
nuclei_findings.txt
httpx.txt
katana_urls.txt
external_dirscan.txt
http_methods.tsv
security_headers.txt
csp_analysis.txt
clickjacking.txt
cors.txt
cors_reflection.txt
host_header_reflection.txt
tls.txt
waf_cdn.txt
cookies.txt
cookie_findings.tsv
tech_fingerprint.txt
js_sources.txt
js_endpoints.txt
internal_links.txt
crawled_pages.tsv
forms.tsv
directory_listing.tsv
auth_surface.tsv
open_redirect_candidates.tsv
ssrf_lfi_rfi_candidates.tsv
graphql.tsv
well_known.tsv
cloud_storage_candidates.tsv
dependency_versions.tsv
sensitive_keywords.tsv
wordpress_audit.tsv
robots_paths.txt
crtsh_subdomains.txt
sitemap_urls.txt
sitemap_pages.txt
interesting_files.tsv
admin_found.tsv
cache.tsv
```
