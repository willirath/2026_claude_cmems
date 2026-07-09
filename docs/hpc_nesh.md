# Beyond your laptop — agent-assisted analysis on nesh

The [getting-started guide](../README.md) sets you up on a laptop, downloading
[CMEMS](https://marine.copernicus.eu/) data over the internet. This document is
the next step: running the same kind of agent-assisted analysis on **nesh**, the
HPC cluster run by Kiel University's computing centre (RZ) together with GEOMAR,
where **NEMO** ocean-model output (global ORCA-family grids and AGRIF nests down
to ~1/100°) lives next to CMEMS reference data.

The cluster changes three things, and this guide is organised around them:

1. **The machine has rules.** Compute belongs in a scheduler allocation, not on
   the login node; the internet is behind a proxy; storage is split across
   backed-up and scratch filesystems. → [Where to run Claude](#1-where-do-you-run-claude),
   [First-time setup](#2-first-time-setup-do-this-once), [Working on nesh](#3-working-on-nesh-login-vs-interactive-vs-base).
2. **The filesystem is shared.** The agent's habit of walking the directory tree
   to orient itself can knock a parallel filesystem sideways for everyone. We
   keep it fast *and* not blind. → [Filesystem-friendly](#5-keep-the-agent-fast-and-filesystem-friendly),
   [A bootstrappable data catalogue](#6-keep-the-agent-not-blind-a-data-catalogue).
3. **The data is NEMO, and it is big.** Curvilinear grids, C-grid staggering,
   netCDF chunking, and lazy dask are things the agent has to get right or it
   will either be wrong or blow up memory. → [NEMO & dask specifics](#7-nemo-orca--netcdfxarraydask-specifics).

> [!IMPORTANT]
> **Confirm the site-specifics before you lean on them.** The nesh details below
> come from the official docs at <https://www.hiperf.rz.uni-kiel.de/nesh/> as of
> this writing. Clusters change. Partition names, the proxy address, quotas, and
> your account string are exactly the things that drift — treat the values here
> as a starting point and verify them on your account (see
> [What to confirm locally](#8-what-to-confirm-locally)). Support:
> `hpcsupport@rz.uni-kiel.de`.

---

## 1. Where do you run Claude?

Not on your laptop — at least not for the analysis loop. The whole value of the
agent is that it *sees the data*: it opens a file, reads the real chunk shape,
renders a field, notices an outlier, and reacts. On nesh the NEMO output is tens
of gigabytes to terabytes and never leaves the cluster, so **Claude runs on
nesh**, launched from a small project directory. Your laptop keeps two jobs: the
terminal you SSH from, and the browser you point at a tunnelled Jupyter (see
[§4](#4-jupyter-from-your-laptop-ssh-socks5-tunnel)).

There are two sensible places on nesh to run it. Pick per task:

| | **A — on the login node** (default) | **B — inside an interactive allocation** |
|---|---|---|
| **Launch** | `ssh` in, `cd` to project, `claude` | `srun --pty ... --partition=base /bin/bash`, then `claude` |
| **Good for** | Writing/editing scripts, reading the catalogue, submitting `sbatch` jobs, cheap header peeks (`ncdump -h`) | Letting the agent iterate directly on real data — open datasets, compute, render figures |
| **Internet** | Direct (login nodes have external networking) — the CLI reaches the API fine | **Set the proxy** so both the CLI *and* your code reach the internet (see [§3](#3-working-on-nesh-login-vs-interactive-vs-base)) |
| **Watch out** | Don't let it run heavy computes here | Allocation has a walltime; the session ends when it does |

Start in **mode A**. It is the lightest, it keeps heavy work in the scheduler
where it belongs, and it is the safest default for the shared filesystem. Move to
**mode B** when you specifically want the agent to run and refine an analysis
against the data in a tight loop rather than by submitting jobs.

A subtlety worth internalising: in mode B, Claude Code's *own* connection to the
Anthropic API goes through the same proxy your download code does. If `claude`
can't reach the API from a `base` node, the proxy variables are almost always why
— see the next sections.

---

## 2. First-time setup (do this once)

You do these steps yourself; the SSH and tunnel parts stay in your hands. Claude
is genuinely useful here as a **guide** — ask it to explain an error, draft a job
script, or check a config — but it should not be `ssh`-ing on your behalf. Think
of it as a knowledgeable colleague looking over your shoulder, not an
autopilot.

1. **Get access.** Request a nesh account via the RZ/GEOMAR HPC team. From
   off-campus you'll need the **CAU VPN**. Landing page:
   <https://www.rz.uni-kiel.de/en/our-portfolio/hiperf/nesh>.

2. **Set up SSH.** Add a stanza to `~/.ssh/config` on your laptop so connecting
   and tunnelling are one word:

   ```
   Host nesh
       HostName nesh-login.rz.uni-kiel.de
       User <your-username>
       # ForwardX11 no      # not needed; we use a browser tunnel instead
   ```

   Then `ssh nesh` once and accept the host key, so it lands in
   `~/.ssh/known_hosts` — the backgrounded tunnel in [§4](#4-jupyter-from-your-laptop-ssh-socks5-tunnel)
   can't answer an interactive host-key prompt.

3. **Install `uv` on nesh** (once, on the login node — it has internet):

   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

   `uv` is deliberately the tool here rather than conda — see the inode note in
   [§5](#5-keep-the-agent-fast-and-filesystem-friendly).

4. **Make a project directory** — small, code-only, and **separate from the
   data**. Under `$HOME` is right (it's backed up and meant for code):

   ```bash
   mkdir -p "$HOME/projects/nemo_cmems_analysis"
   cd "$HOME/projects/nemo_cmems_analysis"
   ```

   Keep the multi-terabyte NEMO output *out* of this tree. The agent reaches it
   by explicit path (via the catalogue), never by having it under its feet.

5. **Drop in the agent's guardrails.** Copy the three templates from this repo
   into the project:

   - the base [`CLAUDE.md`](CLAUDE.md), **plus** the appended
     [nesh snippet](claude_md_nesh_snippet.md) → your project `CLAUDE.md`;
   - [`settings_nesh_example.json`](settings_nesh_example.json) →
     `.claude/settings.json`;
   - the [`catalogue_template/`](catalogue_template/) → `catalogue/` (you fill it
     in — see [§6](#6-keep-the-agent-not-blind-a-data-catalogue)).

6. **Launch Claude, scoped to the project:**

   ```bash
   cd "$HOME/projects/nemo_cmems_analysis" && claude
   ```

   Launching *inside* the project directory (never `$HOME` or a scratch root) is
   the single most effective thing you do to keep the agent's automatic
   context-gathering bounded — see [§5](#5-keep-the-agent-fast-and-filesystem-friendly).

---

## 3. Working on nesh: login vs interactive vs base

nesh uses **SLURM** (it was migrated off the older NEC NQSII batch system — any
page you find that talks about `qsub`/`#PBS` is out of date; the commands are
`sbatch`, `srun`, `salloc`, `squeue`, `scancel`).

**Login nodes are for editing, compiling, small transfers, and submitting jobs —
not for computation.** They're load-balanced and get redeployed, so long-running
or detached processes there get killed anyway. Everything heavier than reading a
netCDF header goes into an allocation.

**Interactive shell on a compute node** (this is your mode-B home):

```bash
# 1 hour, 1 core, 1 GB, on the general-purpose "base" partition
srun --pty --time=01:00:00 --mem=4000 --nodes=1 --cpus-per-task=1 \
     --partition=base /bin/bash
```

- `base` is the default compute partition (Sapphire Rapids / Cascade Lake nodes).
- There's also a dedicated `interactive` partition (shorter walltime cap, external
  networking) that is handy for download-heavy interactive work.
- `--mem` is in **MB** by default; leave 1–2 GB headroom for the OS. Default max
  walltime is generous (~48 h on most partitions) but not infinite.

**Batch job** for anything long or unattended — a minimal script:

```bash
#!/bin/bash
#SBATCH --job-name=nemo_analysis
#SBATCH --partition=base
#SBATCH --nodes=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=32000
#SBATCH --time=02:00:00

cd "$WORK/nemo_cmems_run"          # run job I/O from $WORK, not $HOME
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
uv run python scripts/sst_orca025.py
# submit with: sbatch thisscript.sh
```

**The internet proxy.** Compute nodes on `base` reach the outside world only
through the site HTTP proxy. Anything that downloads — `copernicusmarine`, `uv`
resolving packages, `pip`, `git`, *and Claude Code's own API traffic in mode B* —
needs:

```bash
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
```

> The official docs show `https_proxy=http://10.0.7.235:3128` verbatim; setting
> `http_proxy` to the same value is the safe convention. **Confirm the exact
> variable set (and whether `no_proxy` is needed) with `hpcsupport`** — it's the
> single most common reason "it worked on the login node but hangs in the job."
> Login / `interactive` / data-mover nodes have direct networking and generally
> don't need it.

**Storage** — put things in the right place:

| Variable | Path | Use | Backed up? |
|---|---|---|---|
| `$HOME` | `/gxfs_home/<group>/<user>` | code, scripts, this project, small results | yes (small quota) |
| `$WORK` | `/gxfs_work/<group>/<user>` | **all batch I/O**, intermediate/large data | no (large quota) |
| `$TMPDIR` | `/scratch/SlurmTMP/<user>.<jobid>` | node-local per-job scratch; **dask spill goes here** | no (vanishes at job end) |
| `$CEPH` | `/nfs/ceph_<group>/<user>` | cold long-term storage | no |

Check usage with `workquota` (home/work) and `cephquota`. Note the paths are
`/gxfs_home/...` and `/gxfs_work/...`, not `/home/...`.

---

## 4. Jupyter from your laptop (SSH SOCKS5 tunnel)

When you want a real notebook, run JupyterLab **on a compute node** and reach it
from your laptop browser through an SSH tunnel. This follows GEOMAR's
[`jupyter_on_HPC_setup_guide`](https://git.geomar.de/python/jupyter_on_HPC_setup_guide)
— specifically its SOCKS5 tunnel script. (That repo's *job script* is written for
the old PBS scheduler; the tunnel mechanics below are unchanged, we just launch
Jupyter with SLURM instead.)

**Why a dynamic SOCKS5 proxy (`ssh -D`) and not a plain `ssh -L` forward?** You
don't know which compute node you'll land on until the job starts, and that node
is only reachable *through* the login node. A SOCKS proxy lets the browser reach
any internal `host:port` via the login node without hard-coding the node name.

**The flow — you drive each step:**

1. **On nesh**, submit a job that runs JupyterLab bound to the node's own
   hostname (so it listens on the internal network, not just localhost):

   ```bash
   #!/bin/bash
   #SBATCH --job-name=jupyterlab
   #SBATCH --partition=base
   #SBATCH --cpus-per-task=4
   #SBATCH --mem=16000
   #SBATCH --time=08:00:00
   #SBATCH --output=jupyterlab.%j.out

   cd "$HOME/projects/nemo_cmems_analysis"
   export http_proxy=http://10.0.7.235:3128
   export https_proxy=http://10.0.7.235:3128
   uv run jupyter lab --ip="$(hostname)" --no-browser
   ```

   (`srun --pty ... jupyter lab --ip=$(hostname) --no-browser` inside an
   interactive allocation works too.)

2. **Read the URL** it printed — `grep` the job's output file for the line like
   `http://nesh-clk399:8888/?token=abc123…`. That internal hostname + token is
   what you'll open.

3. **On your laptop**, open the tunnel and point an isolated browser at it. The
   minimal manual form:

   ```bash
   ssh -f -D localhost:54321 nesh sleep 60
   chromium-browser --proxy-server="socks5://localhost:54321" \
       --proxy-bypass-list="<-loopback>" \
       'http://nesh-clk399:8888/?token=abc123…'
   ```

   Or use GEOMAR's helper, which auto-picks a free port and launches an isolated
   Chromium for you:

   ```bash
   curl -O https://git.geomar.de/python/jupyter_on_HPC_setup_guide/raw/master/scripts/run_chromium_through_ssh_tunnel.sh
   chmod +x run_chromium_through_ssh_tunnel.sh
   ./run_chromium_through_ssh_tunnel.sh nesh 'http://nesh-clk399:8888/?token=abc123…'
   ```

   The `--proxy-bypass-list="<-loopback>"` flag is not optional cargo: Chrome/
   Chromium > v71 refuses to send loopback addresses through a SOCKS proxy by
   default, and `<-loopback>` re-enables it. Without it the page just won't load.

The **dask dashboard** (`:8787`, [§7](#7-nemo-orca--netcdfxarraydask-specifics))
is reached exactly the same way — it's another internal `host:port` the SOCKS
proxy can route to.

---

## 5. Keep the agent fast and filesystem-friendly

nesh's filesystems are **shared and parallel**. Every `stat`/`readdir` is a
request to a metadata server that the whole cluster shares. A recursive walk —
`find`, `grep -r`, `ls -R`, `rg`, `du` over `$HOME`, `$WORK`, or a data root —
fires one such request *per file and directory* and can generate a metadata storm
that slows the cluster for everyone. It is the classic way to get a friendly email
from the admins. (Parallel filesystems like Lustre top out around ~15k requests/s
across all users; on a tree with millions of files, one careless walk saturates
it.)

The catch specific to agents: **Claude Code treats `ls`, `cat`, `head`, `tail`,
`grep`, `find`, `wc`, `stat`, `du` (and read-only `git`) as read-only and runs
them with no prompt, in every mode — and that set is not configurable.** So the
agent's instinct to "get the lay of the land" by tree-walking runs silently.
There are three levers, in increasing order of strength. Use all three, and be
honest with yourself about what each one buys.

**Lever 1 — Scope the launch (the big one).** Launch `claude` from the small,
code-only project directory, never `$HOME` or scratch. Claude's automatic
context-gathering (including its own ripgrep-backed Grep/Glob tools) is bounded to
where you launched it. If the project directory contains only code and the small
`catalogue/`, there's simply nothing expensive to walk — and you can leave Grep/
Glob *enabled*, because searching a few dozen local files is cheap and useful.
The corollary: **never `--add-dir` the raw data root**, and don't put the project
inside the data tree.

**Lever 2 — `CLAUDE.md` house rules (a nudge).** The appended
[nesh snippet](claude_md_nesh_snippet.md) tells the agent, in plain language, not
to walk the data tree and to consult the catalogue instead. This is a *soft*
instruction — a well-behaved agent honours it, but it is guidance, not a fence.

**Lever 3 — `settings.json` deny rules (the actual fence).** The example
[`settings_nesh_example.json`](settings_nesh_example.json) denies the
recursive-walk commands outright:

```json
{
  "permissions": {
    "deny": [
      "Bash(find:*)",
      "Bash(grep -r:*)",
      "Bash(grep -R:*)",
      "Bash(ls -R:*)",
      "Bash(ls -lR:*)",
      "Bash(rg:*)",
      "Bash(du:*)",
      "Bash(tree:*)"
    ]
  }
}
```

Honest caveats, because this is where people fool themselves:

- Bash pattern matching is a **coarse prefix heuristic, not a security boundary**.
  It's plenty to stop the agent's *default* `find .`-style walks, but a determined
  or creative command (extra spaces, a wrapper, a redirect) can slip past
  argument constraints. Rules are enforced by Claude Code, not by the model.
- Rules evaluate **deny → ask → allow**, first match wins, and a deny at *any*
  settings layer wins — so committing this in the project `.claude/settings.json`
  is enough; nobody's personal allow-list can override it.
- These Bash denies don't touch Claude's own **Grep/Glob** tools — but *Lever 1*
  already handles those by scoping. Don't blanket-deny Grep/Glob; you'd take away
  cheap, safe search over your own code for no filesystem benefit.

Together: scoped launch means there's nothing big to walk, the deny rules stop the
agent from reaching *out* to the data tree by hand, and the `CLAUDE.md` rule tells
it what to do instead — read the catalogue.

**One more filesystem note — inodes, and why `uv` not conda.** Home filesystems
are limited by *file count* (inodes), not just bytes. A single conda environment
can materialise 100k+ tiny files and blow an inode quota on its own; `uv`
installs far fewer files and is faster. That's the concrete reason the whole
project standardises on `uv` (it's not just taste). If you must use conda, point
its package and environment dirs at `$WORK`.

---

## 6. Keep the agent not blind: a data catalogue

If the agent can't walk the filesystem, how does it know what data exists and how
it's shaped? You give it a small, **checked-in catalogue** it can read instead —
the single-user substitute for a real data-catalogue service. Three cheap
ingredients, all in a `catalogue/` directory in the project (template in
[`catalogue_template/`](catalogue_template/)):

1. **CDL headers — authoritative, machine-readable.** `ncdump -h -s` prints a
   file's dimensions, variables, attributes, *and* its on-disk chunking and
   compression (`_ChunkSizes`, `_DeflateLevel`, `_Shuffle`) — reading **zero**
   data. Commit one `.cdl` per representative stream. This is exactly what the
   agent needs to choose dask chunks correctly ([§7](#7-nemo-orca--netcdfxarraydask-specifics)):

   ```bash
   ncdump -h -s /path/to/ORCA025/rep_grid_T.nc > catalogue/orca025_grid_T.cdl
   ```

2. **`DATA.md` — prose the header can't carry.** Hand-written (draft it *with*
   the agent, then check it): for each dataset — the one stable path (marked
   "do not walk"), grid family and resolution, where `mesh_mask.nc` lives, the
   `grid_T/U/V/W` file-naming pattern, time coverage and per-file period,
   rough size, and gotchas (2D curvilinear coords, north fold, whether files
   still need `rebuild_nemo`). This is where you tell the agent *which variable
   means what* and *which directory is off-limits to scanning*.

3. **`tree.txt` — a one-time, bounded snapshot.** Pay the metadata cost **once,
   deliberately, by hand**, at shallow depth:

   ```bash
   find "$DATA_ROOT" -maxdepth 2 -type d | sort > catalogue/tree.txt
   ```

   Now the agent knows the layout without ever walking it live.

The workflow that makes this bootstrappable: **the agent proposes, you run and
commit.** Claude drafts `DATA.md` and the exact `ncdump`/`find` commands; *you*
run them (they're bounded and deliberate) and commit the result. When new data
lands, ask the agent to update the catalogue and re-run the (still bounded)
generator. A [`regenerate.sh`](catalogue_template/regenerate.sh) captures the
recipe so it's reproducible. Point `CLAUDE.md` at the catalogue and forbid live
scans (the snippet does this), and the agent stays oriented without touching the
filesystem in anger.

---

## 7. NEMO / ORCA + netCDF/xarray/dask specifics

This is the domain knowledge the agent needs to be *correct* on NEMO output and
*not blow up memory* on it. It lives in the [nesh snippet](claude_md_nesh_snippet.md)
so the agent applies it by default; the reasoning is here.

### The grid

NEMO discretises the ocean on a staggered **Arakawa C-grid**: scalars (temperature,
salinity, SSH) at cell centres (**T** points), horizontal velocities on the cell
faces (**U** east–west, **V** north–south), vertical velocity/mixing on the
top/bottom faces (**W**), and vorticity/Coriolis quantities at the corners (**F**).
Each point type carries its own coordinates and metric scale factors: `glam{t,u,v,f}`
(longitude), `gphi{t,u,v,f}` (latitude), `e1*`/`e2*` (horizontal cell sizes **in
metres**, not degrees), `e3{t,u,v,w}` (layer thicknesses), depths `gdept`/`gdepw`,
and 3-D land–sea masks `tmask`/`umask`/`vmask`/`fmask` (1 = ocean, 0 = land). This
metadata lives in `mesh_mask.nc` / `domain_cfg.nc` / `coordinates.nc` — keep those
paths in the catalogue; most real analysis needs them.

The global configs are the **ORCA tripolar family**: a regular Mercator mesh south
of ~20 °N, but the North Pole singularity is split into two poles placed over land
(northern Canada and Siberia). ORCA2 ≈ 2°, ORCA025 = ¼°, ORCA12 (= ORCA0083) =
1/12°; the **eORCA** variants extend south to ~85 °S to include Antarctic
ice-shelf cavities. The ~1/100° resolution you're after typically comes from a
regional **AGRIF nest** embedded in a coarser parent, not a global centi-degree
grid — child domains carry `1_`, `2_`, … filename prefixes. The **north fold**
along the top row duplicates cells and flips the sign of vector fields; be wary of
the northernmost rows.

### The one gotcha that breaks naive xarray

In NEMO output, `nav_lon`/`nav_lat` (and `glamt`/`gphit`) are **2-D curvilinear
arrays** over the integer index dimensions `(y, x)` — they are *not* 1-D dimension
coordinates. So **`ds.sel(lon=…, lat=…)` does not work** on the horizontal
dimensions. The real dimensions are the index axes `x`, `y`; select with **`.isel`**,
or use grid-aware tooling (`cf-xarray`, `xgcm`/`xnemogcm`, `xESMF` for regridding).
This trips up almost everyone once.

### netCDF chunking → dask chunking (the performance rule)

Large NEMO/CMEMS files are internally **chunked and deflated** (zlib + shuffle).
The rule that makes reads fast: **dask chunks must be integer multiples of the
on-disk `_ChunkSizes`.** Misaligned chunks straddle disk chunks and re-read the
same compressed block repeatedly (read amplification). So the habit is: **inspect
first, then chunk.**

```bash
ncdump -h -s file.nc     # _ChunkSizes, _DeflateLevel, _Shuffle
```
```python
ds["thetao"].encoding    # {'chunksizes': (...), 'zlib': True, 'complevel': 4, ...}
```

Then open many per-period files lazily, with chunks that are multiples of those
sizes, dropping the big 2-D coords you don't need:

```python
ds = xr.open_mfdataset(
    "NEMO_ORCA025_1m_*_grid_T.nc",
    combine="nested", concat_dim="time_counter", parallel=True,
    data_vars="minimal", coords="minimal", compat="override",
    drop_variables=["bounds_lon", "bounds_lat"],
    chunks={"time_counter": 1, "deptht": 75, "y": 300, "x": 400},  # ⇐ multiples of _ChunkSizes
    engine="h5netcdf",
)
```

`data_vars/coords="minimal"` + `compat="override"` stops xarray re-reading and
comparing the big 2-D `nav_lon`/`nav_lat` in every file. Aim for **~100 MB per
dask chunk** (≳1e6 elements): smaller explodes the task graph, larger risks
out-of-memory. If a file's on-disk chunking is pathological (e.g. contiguous),
rechunk it once with `nccopy -c … -d4 -s in.nc out.nc` and **verify with
`ncdump -h -s`**.

### Stay lazy

`.values`, `.compute()`, `.load()`, and `.plot()` all pull data into memory *now*
— on a global ORCA 3-D field that's tens of GB into one process. Reduce or subset
**first** (`.isel`, `.mean(...)`), then materialise only the small result.

### dask on nesh

Start with a single-node `LocalCluster` inside an allocation; reach for
`dask_jobqueue.SLURMCluster` only when one node isn't enough. **Never run workers
on the login node.** Two nesh-specific settings that bite:

```python
from dask.distributed import Client, LocalCluster
cluster = LocalCluster(n_workers=8, threads_per_worker=1,
                       memory_limit="24GiB",
                       local_directory="/scratch/SlurmTMP")   # node-local spill, NOT $WORK/$HOME
client = Client(cluster)
print(client.dashboard_link)   # reach :8787 via the same SOCKS5 tunnel as Jupyter (§4)
```

- **Spill to node-local `$TMPDIR`**, never a shared filesystem — dask writes many
  small spill files and would hammer the shared metadata server.
- With `SLURMCluster`, `cores`/`processes`/`memory` are **per job**, and SLURM
  reads "GB" as GiB — specify `memory="60GiB"` to get what you asked for.

---

## 8. What to confirm locally

Everything below is real per the current nesh docs, but it's exactly what drifts.
Verify on your account (ask the agent to help you check, or email `hpcsupport`):

- **Proxy** — docs show `https_proxy=http://10.0.7.235:3128`; confirm whether
  `http_proxy`/`no_proxy` are also needed and which node classes require it.
- **Partitions** — confirm `base` / `interactive` / `gpu` / `highmem` are current,
  and the `--account` string format for your project.
- **Filesystems & quotas** — confirm the `/gxfs_home` and `/gxfs_work` paths, the
  space **and inode** quotas (`workquota`), and the node-local scratch path for
  dask spill.
- **Jupyter job** — the GEOMAR helper's job script is PBS-era; use the SLURM
  version in [§4](#4-jupyter-from-your-laptop-ssh-socks5-tunnel) and confirm the
  login hostname (`nesh-login.rz.uni-kiel.de`) as your tunnel target.
- **Your data** — inspect each stream with `ncdump -h -s`; confirm whether output
  is already rebuilt or still per-processor (needs `rebuild_nemo`), and get the
  real `_ChunkSizes` before choosing dask chunks.
- **Site policy** — check whether admins ship a managed Claude Code settings file
  or have any policy on running agentic tools on login nodes.

## Sources

- nesh user docs — <https://www.hiperf.rz.uni-kiel.de/nesh/> (access, Slurm,
  file systems, software)
- GEOMAR Jupyter-on-HPC setup guide — <https://git.geomar.de/python/jupyter_on_HPC_setup_guide>
- NEMO documentation — <https://sites.nemo-ocean.io/user-guide/> ·
  `xnemogcm` <https://xnemogcm.readthedocs.io/>
- Claude Code permissions & settings — <https://code.claude.com/docs/en/permissions>,
  <https://code.claude.com/docs/en/settings>
- xarray & dask on HPC — <https://docs.xarray.dev/en/stable/user-guide/dask.html>,
  <https://docs.dask.org/en/stable/deploying-hpc.html>,
  <https://jobqueue.dask.org/>
