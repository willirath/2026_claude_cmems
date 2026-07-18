# Remote work — reaching a compute-node Jupyter factsheet

How to reach JupyterLab (and the dask dashboard) running on a nesh **compute node**
from a browser on your laptop. This sheet is the mechanism — the job, the tunnel, the
browser flags, and what breaks — so it works equally for setting the workflow up and
for debugging one that isn't ("why can't I see the JupyterLab?").

## Why it takes a tunnel

A compute node is reachable only _through_ the login node, and you don't know which
node your job lands on until it starts. So: run Jupyter on the compute node bound to
its own hostname, open a **dynamic SOCKS proxy** through the login node, and point
an isolated browser at the node's internal `host:port`.

## 1. Launch Jupyter in a job (on nesh)

```bash
#!/bin/bash
#SBATCH --job-name=jupyterlab
#SBATCH --partition=base
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=08:00:00
#SBATCH --output=jupyterlab.%j.out

cd "$WORK/projects/<your-project>"
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
uv run jupyter lab --no-browser --ip="$(hostname)"
```

`--ip="$(hostname)"` binds JupyterLab to the node's internal interface (not just
localhost) so the tunnel can reach it.

## 2. Read the token URL

From the job's output file (`jupyterlab.<jobid>.out`), copy the line like
`http://nesh-clk399:8888/?token=abc123…`. That **internal hostname + token** is what
you open in the browser.

## 3. Tunnel + isolated browser (on your laptop)

Open a dynamic SOCKS proxy through the login node, then launch an isolated
Chromium/Chrome routed through it and pointed at the token URL from step 2. The
script `bin/remote_tunnel_chrome.sh` (vendored in the getting-started repo; the
copy below is kept in sync with it) does both, on macOS, Linux, and Windows —
on Windows, run it in **Git Bash**. Hand it the login node and, optionally, the URL:

```bash
./remote_tunnel_chrome.sh <user>@nesh-login.rz.uni-kiel.de 'http://nesh-clk399:8888/?token=abc123…'
```

The URL is optional. Drop it and the browser just opens — paste the token URL
into the address bar once the window is up. That way you can `CTRL+R`-recall the
tunnel command and fire it off before you've even copied the URL:

```bash
./remote_tunnel_chrome.sh <user>@nesh-login.rz.uni-kiel.de
```

```bash
#!/usr/bin/env bash
# remote_tunnel_chrome.sh — reach a compute-node JupyterLab through the nesh login node.
#
#   ./remote_tunnel_chrome.sh <user>@nesh-login.rz.uni-kiel.de 'http://nesh-clk399:8888/?token=abc123…'
#   ./remote_tunnel_chrome.sh <user>@nesh-login.rz.uni-kiel.de   # then paste the URL in the browser
#
# Opens a dynamic SOCKS proxy through the login node, then launches an isolated
# Chrome/Chromium routed through it. The token URL from the Jupyter job output
# file is an optional second argument — pass it to open it straight away, or omit
# it and paste it into the browser's address bar once the window is up (handy for
# a CTRL+R recall of the command before you have the URL). Works on macOS, Linux,
# and Windows (run it in Git Bash). The same script is inlined in
# docs/factsheets/remote-work.md — keep the two in sync.
set -euo pipefail

LOGIN="${1:?pass the login node, e.g. jdoe@nesh-login.rz.uni-kiel.de (an ssh-config alias works too)}"
URL="${2:-}"  # optional: the compute-node token URL, else paste it in the browser

case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;; *) WINDOWS=0 ;; esac

# SOCKS port: $SOCKS_PORT if set, else ask python for a free ephemeral port,
# else fall back to a fixed default and hope it is free. On Windows, skip the
# python probe (the python on PATH is often the Microsoft Store stub, and the
# bind can trip the firewall dialog) and go straight to the default.
PY_FREE_PORT='import socket; s = socket.socket(); s.bind(("", 0)); print(s.getsockname()[1])'
if [ "${WINDOWS}" = 1 ]; then
  PORT="${SOCKS_PORT:-54321}"
else
  PORT="${SOCKS_PORT:-$( { python3 -c "${PY_FREE_PORT}" || python -c "${PY_FREE_PORT}"; } 2>/dev/null || echo 54321)}"
fi

# Chrome/Chromium binary: $BROWSER_BIN if set, else the first one found
# (Linux package names, then macOS app paths, then Windows installs as Git
# Bash sees them).
if [ -z "${BROWSER_BIN:-}" ]; then
  for candidate in chromium chromium-browser google-chrome google-chrome-stable \
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      "/Applications/Chromium.app/Contents/MacOS/Chromium" \
      "/c/Program Files/Google/Chrome/Application/chrome.exe" \
      "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
      "/c/Users/${USERNAME:-}/AppData/Local/Google/Chrome/Application/chrome.exe"; do
    if command -v "${candidate}" >/dev/null 2>&1; then BROWSER_BIN="${candidate}"; break; fi
  done
fi
: "${BROWSER_BIN:?no Chrome/Chromium found — set BROWSER_BIN to your browser binary}"

# Chrome on Windows is a native app: hand it a Windows-style profile path — it
# does not understand Git Bash's /tmp. Elsewhere a throwaway tmpdir is fine.
if [ "${WINDOWS}" = 1 ]; then
  USER_DATA_DIR="${USERPROFILE}\\Chrome-Proxy-${PORT}"
else
  USER_DATA_DIR="$(mktemp -d)"
fi

echo "SOCKS proxy localhost:${PORT} via ${LOGIN}; browser: ${BROWSER_BIN}" >&2

# -f backgrounds ssh after auth; `sleep 60` holds the tunnel open long enough
# for the browser to start and connect (cold starts on Windows are slow), after
# which ssh stays up while that connection is live.
ssh -f -D "localhost:${PORT}" "${LOGIN}" sleep 60

# Chrome's own phone-home traffic (Google endpoints) goes direct to the open
# internet instead of through the HPC login node.
GOOGLE_BYPASS='google.com;*.google.com;google.de;*.google.de;google.fr;*.google.fr;googleapis.com;*.googleapis.com;googleapis.de;*.googleapis.de;googleapis.fr;*.googleapis.fr;*.gvt1.com;*.gstatic.com'

# Isolated browser through the proxy. --proxy-bypass-list="<-loopback>" re-enables
# SOCKS for loopback/internal hosts, which Chrome blocks by default.
"${BROWSER_BIN}" \
  --new-window --no-first-run \
  --proxy-server="socks5://localhost:${PORT}" \
  --proxy-bypass-list="<-loopback>;${GOOGLE_BYPASS}" \
  --user-data-dir="${USER_DATA_DIR}" \
  ${URL:+"${URL}"}
```

`nesh-clk399` in the URL is a placeholder for the compute node from step 2; a
`~/.ssh/config` alias can shorten the first argument to just `nesh`.

Three things that matter when it doesn't work:

- **`-D` (dynamic SOCKS), not `-L`:** you don't know the node name ahead of time,
  and SOCKS lets the browser reach any internal `host:port` without hard-coding it.
- **`--proxy-bypass-list="<-loopback>"` is required:** Chrome/Chromium refuses to
  route loopback addresses through a SOCKS proxy by default; this flag re-enables
  it. If the page won't load, this — or your browser version — is the usual cause.
- Accept the host key once with a plain `ssh nesh-login.rz.uni-kiel.de` beforehand —
  the backgrounded `-f` tunnel can't answer an interactive prompt.

## dask dashboard

The dask dashboard (`:8787`) rides the **same tunnel** — it's just another internal
`host:port` the SOCKS proxy can route to. Open it in the same browser.

## Source

- The tunnel script is vendored in the getting-started repo as
  `bin/remote_tunnel_chrome.sh` and inlined above, self-contained. It derives from
  GEOMAR's Jupyter-on-HPC setup guide
  (<https://git.geomar.de/python/jupyter_on_HPC_setup_guide>), which is dated — its
  job script targets a different scheduler, so use the SLURM job above instead.
