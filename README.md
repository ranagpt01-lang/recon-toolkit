# Recon Toolkit v2

A bash-based, opinionated recon pipeline for **authorized** security assessments
(bug bounty, internal pentest, your own assets). Wraps the popular
ProjectDiscovery / tomnomnom toolchain into a single reproducible workflow.

> ⚠️ **Authorization required.** Only run this against domains you own or have
> explicit written permission to test. Unauthorized scanning is illegal in most
> jurisdictions.

## Pipeline

```
Subdomain enum  →  DNS resolve  →  Live + tech detect  →  Wayback / gau / katana
                                          ↓                        ↓
                                  JS secret hunt  ←  collected JS file list
                                          ↓
                                   Nuclei scan  →  report.txt
```

## Features

- **Stealth / Fast modes** — toggle between low-rate stealth and high-throughput.
- **Real User-Agent rotation** — a fresh UA per JS-fetch request, not just one
  pinned at startup.
- **Strict mode** (`set -euo pipefail`) and per-step error handling.
- **Dependency check** at startup with install hints.
- **Scope-aware crt.sh parsing** — multi-line `name_value` handled, wildcards
  stripped, results filtered to the target domain.
- **Clean separation** between human-readable host list and URL-only list fed
  into downstream tools.
- **Parallel JS fetching** via `xargs -P` (10 in stealth, 30 in fast mode).

## Requirements

Required:
- [`subfinder`](https://github.com/projectdiscovery/subfinder)
- [`dnsx`](https://github.com/projectdiscovery/dnsx)
- [`httpx`](https://github.com/projectdiscovery/httpx)
- [`katana`](https://github.com/projectdiscovery/katana)
- [`nuclei`](https://github.com/projectdiscovery/nuclei)
- [`anew`](https://github.com/tomnomnom/anew)
- `jq`, `curl`

Optional (script will skip the related steps if missing):
- [`gau`](https://github.com/lc/gau)
- [`waybackurls`](https://github.com/tomnomnom/waybackurls)

Install everything in one go:

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install -v github.com/tomnomnom/anew@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
sudo apt install -y jq curl
nuclei -update-templates
```

## Usage

```bash
./recon.sh example.com                 # stealth mode (default)
./recon.sh example.com --fast          # higher rate, no delays
./recon.sh example.com --out /tmp/foo  # custom output dir
./recon.sh -h                          # help
```

## Output

Inside `recon_<domain>/`:

| File                | Contents                                              |
|---------------------|-------------------------------------------------------|
| `subdomains.txt`    | Combined subfinder + crt.sh results                   |
| `resolved.txt`      | Resolved subdomains with A records                    |
| `resolved_hosts.txt`| Resolved hostnames only (one per line)                |
| `live_hosts.txt`    | httpx output with title, tech, status, server, CDN    |
| `live_urls.txt`     | URL-only list (used by nuclei / katana downstream)    |
| `wayback.txt`       | URLs from waybackurls                                 |
| `gau.txt`           | URLs from gau                                         |
| `js_files.txt`      | JavaScript / JSON files discovered                    |
| `secrets.txt`       | Candidate secrets in JS (manual review required)      |
| `nuclei_results.txt`| Nuclei findings                                       |
| `report.txt`        | Summary counts                                        |

## Notes & limitations

- The JS secret regex is intentionally coarse — it will produce false positives.
  For production use, pipe `js_files.txt` into
  [trufflehog](https://github.com/trufflesecurity/trufflehog) or
  [mantra](https://github.com/MrEmpy/mantra).
- This script does **not** perform any active exploitation, brute force, or
  destructive actions.
- Rate limits and stealth mode are best-effort — they do **not** guarantee
  evasion of WAFs, IDSs, or rate-limiters.

## License

MIT — see [LICENSE](LICENSE).
