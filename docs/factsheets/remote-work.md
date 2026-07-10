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

cd "$HOME/projects/<your-project>"
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
Chromium/Chrome routed through it and pointed at the token URL from step 2. This
script does both — save it and hand it the URL:

```bash
#!/usr/bin/env bash
# run_chromium_through_ssh_tunnel.sh — reach a compute-node JupyterLab through nesh.
#   ./run_chromium_through_ssh_tunnel.sh 'http://nesh-clk399:8888/?token=abc123…'
set -euo pipefail

URL="${1:?pass the compute-node token URL from the job output file}"
LOGIN="${NESH_LOGIN:-nesh-login.rz.uni-kiel.de}"   # or a ~/.ssh/config alias, e.g. nesh
PORT="${SOCKS_PORT:-54321}"                        # local SOCKS port
BROWSER="${BROWSER_BIN:-chromium}"                 # chromium, google-chrome, …

# -f backgrounds ssh after auth; `sleep 30` holds the tunnel open long enough for
# the browser to connect, after which ssh stays up while that connection is live.
ssh -f -D "localhost:${PORT}" "${LOGIN}" sleep 30

# Isolated browser through the proxy. --proxy-bypass-list="<-loopback>" re-enables
# SOCKS for loopback/internal hosts, which Chrome blocks by default.
"${BROWSER}" \
  --proxy-server="socks5://localhost:${PORT}" \
  --proxy-bypass-list="<-loopback>" \
  --user-data-dir="$(mktemp -d)" \
  "${URL}"
```

`nesh-clk399` in the URL is a placeholder for the compute node from step 2; a
`~/.ssh/config` alias can shorten `nesh-login.rz.uni-kiel.de` to `nesh` (set
`NESH_LOGIN=nesh`).

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

- The tunnel script above is vendored here and self-contained. It derives from
  GEOMAR's Jupyter-on-HPC setup guide
  (<https://git.geomar.de/python/jupyter_on_HPC_setup_guide>), which is dated — its
  job script targets a different scheduler, so use the SLURM job above instead.
