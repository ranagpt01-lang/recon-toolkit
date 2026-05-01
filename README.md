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
- `jq`, `curl`, `shuf`, `xargs` (typically present on any Linux/macOS box)
- Go ≥ 1.21 (only needed for installing the PD / tomnomnom tools)

Optional (script will skip the related steps if missing):
- [`gau`](https://github.com/lc/gau)
- [`waybackurls`](https://github.com/tomnomnom/waybackurls)

## Installation

### 1. Install Go (skip if you already have it)

**Kali / Debian / Ubuntu:**
```bash
sudo apt update
sudo apt install -y golang-go jq curl
```

**Verify:**
```bash
go version    # should print go1.21+ or newer
```

### 2. Make sure `$HOME/go/bin` is on your PATH

`go install` puts binaries in `$HOME/go/bin`. Add it to your shell rc once:

```bash
# zsh (Kali default)
echo 'export PATH=$HOME/go/bin:$PATH' >> ~/.zshrc && source ~/.zshrc

# bash
echo 'export PATH=$HOME/go/bin:$PATH' >> ~/.bashrc && source ~/.bashrc
```

> Note: the script auto-detects ProjectDiscovery binaries even if your distro
> ships a same-named binary that shadows them (e.g. `apt`'s Python `httpx` on
> Kali). PATH ordering is **not strictly required** — but having `~/go/bin`
> first avoids an extra warning at startup.

### 3. Install the recon tools

```bash
go install -v github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install -v github.com/projectdiscovery/dnsx/cmd/dnsx@latest
go install -v github.com/projectdiscovery/httpx/cmd/httpx@latest
go install -v github.com/projectdiscovery/katana/cmd/katana@latest
go install -v github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest
go install -v github.com/tomnomnom/anew@latest
go install -v github.com/tomnomnom/waybackurls@latest
go install -v github.com/lc/gau/v2/cmd/gau@latest
```

First run downloads ~150+ Go packages; expect 5–15 min on a fast connection.

### 4. Pull nuclei templates

```bash
nuclei -update-templates
```

### 5. Clone this repo and run

```bash
git clone https://github.com/ranagpt01-lang/recon-toolkit.git
cd recon-toolkit
chmod +x recon.sh
./recon.sh example.com --fast
```

### 6. (Optional) Install system-wide

If you want to call `recon.sh` from any directory:

```bash
sudo ln -s "$PWD/recon.sh" /usr/local/bin/recon
recon example.com --fast
```

### 7. Verify everything is wired up

```bash
for t in subfinder dnsx httpx katana nuclei anew waybackurls gau jq curl shuf xargs; do
  command -v $t >/dev/null && echo "[OK]   $t" || echo "[MISS] $t"
done
```

All required tools should show `[OK]`. If any show `[MISS]`, re-run the
corresponding `go install` line from step 3.

## Updating

```bash
cd ~/recon-toolkit
git pull                     # pull latest recon.sh
nuclei -update-templates     # refresh template DB
```

To update the underlying tools, re-run the `go install ...@latest` block from
step 3.

## Uninstalling

```bash
rm -rf ~/recon-toolkit
rm -f $HOME/go/bin/{subfinder,dnsx,httpx,katana,nuclei,anew,waybackurls,gau}
sudo rm -f /usr/local/bin/recon   # only if you symlinked in step 6
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
