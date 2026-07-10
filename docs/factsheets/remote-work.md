# Remote work — reaching a compute-node Jupyter factsheet

How to use the browser on your laptop to reach JupyterLab (and the dask dashboard)
running on a nesh **compute node**. The user drives these steps by hand; the agent
assists by drafting the job script and troubleshooting, not by opening tunnels on
their behalf.

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

Don't reinvent this — GEOMAR ships a helper,
[`run_chromium_through_ssh_tunnel.sh`](https://git.geomar.de/python/jupyter_on_HPC_setup_guide/-/blob/master/scripts/run_chromium_through_ssh_tunnel.sh),
that opens the SOCKS tunnel and launches an isolated Chromium already configured for
it — hand it the token URL from step 2. Under the hood it does:

```bash
ssh -f -D localhost:54321 nesh-login.rz.uni-kiel.de sleep 60
chromium --proxy-server="socks5://localhost:54321" \
         --proxy-bypass-list="<-loopback>" \
         --user-data-dir=/tmp/nesh-jlab \
         'http://nesh-clk399:8888/?token=abc123…'
```

`nesh-clk399` is a placeholder for the compute node from step 2; a `~/.ssh/config`
alias can shorten `nesh-login.rz.uni-kiel.de` to `nesh`.

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

- GEOMAR Jupyter-on-HPC setup guide — <https://git.geomar.de/python/jupyter_on_HPC_setup_guide>
  (its job script targets a different scheduler; submit the SLURM job above instead)
