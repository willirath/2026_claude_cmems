# Running on nesh — a short on-ramp

The [getting-started guide](../README.md) sets you up on a laptop with
[CMEMS](https://marine.copernicus.eu/) data. This is the next step: doing the same
kind of agent-assisted analysis on **nesh**, the HPC cluster run by Kiel
University's computing centre (RZ) with GEOMAR, where **NEMO** ocean-model output
lives right next to the CMEMS reference data.

The goal here is modest: **get you analysing on nesh at all.** It is not a
perfect, tuned HPC workflow — it's the shortest honest path that keeps you (and
the agent) out of trouble. Once you're running, you can optimise as you go.

Three things change when you move off your laptop, and everything below follows
from them:

1. **The machine has rules** — compute goes in a scheduler job, not on the login
   node; the internet is behind a proxy; storage is split across backed-up and
   scratch areas.
2. **The filesystem is shared** — the agent's habit of walking directory trees to
   orient itself can annoy the whole cluster. We keep it fast *and* not blind.
3. **The data is NEMO, and it's big** — curvilinear grids and lazy loading are
   things the agent has to get right, or results are silently wrong or blow up
   memory.

> [!IMPORTANT]
> **Confirm the site-specifics before you lean on them.** The nesh values below
> are from the official docs at <https://www.hiperf.rz.uni-kiel.de/nesh/> as of
> this writing, but partition names, the proxy address, quotas, and paths are
> exactly the things that drift. Treat them as a starting point and check them on
> your account — see [What to confirm locally](#7-what-to-confirm-locally).
> Support: `hpcsupport@rz.uni-kiel.de`.

---

## 1. Where do you run Claude?

**On nesh, not on your laptop.** The whole value of the agent is that it *sees the
data* — opens a file, reads the real chunk shape, renders a field, reacts to an
outlier. On nesh the NEMO output is tens of gigabytes to terabytes and never
leaves the cluster, so that's where Claude has to be. Your laptop keeps two jobs:
the terminal you SSH from, and the browser you point at a tunnelled Jupyter
([§4](#4-jupyter-from-your-laptop)).

On nesh there are two reasonable places to launch it:

- **On the login node (default).** Good for writing and editing scripts, reading
  the catalogue, peeking at netCDF headers (`ncdump -h`), and submitting jobs. Its
  internet is direct, so the CLI reaches the API fine. **Don't run heavy computes
  here.**
- **Inside an interactive allocation** (`srun --pty … /bin/bash`, then `claude`).
  Use this when you want the agent to iterate directly on real data in a tight
  loop. One catch: on a compute node the CLI's *own* API traffic goes through the
  proxy — if `claude` can't connect, that's almost always why
  ([§3](#3-running-under-slurm)).

Start on the login node; move into an allocation when you specifically want the
agent working against the data rather than submitting jobs for you.

---

## 2. First-time setup (do this once)

You do these steps yourself — the SSH and tunnel parts stay in your hands. Claude
is a useful **guide** here (ask it to explain an error, draft a job script, check
a config), but it shouldn't be `ssh`-ing on your behalf.

1. **Get access.** Request a nesh account from the RZ/GEOMAR HPC team. From
   off-campus you first need the **CAU VPN** (same username). Landing page:
   <https://www.rz.uni-kiel.de/en/our-portfolio/hiperf/nesh>.

2. **Set up SSH** so connecting is one word. In `~/.ssh/config` on your laptop:

   ```
   Host nesh
       HostName nesh-login.rz.uni-kiel.de
       User <your-username>
   ```

   Then `ssh nesh` once and accept the host key (the backgrounded tunnel in
   [§4](#4-jupyter-from-your-laptop) can't answer an interactive prompt later).

3. **Install `uv` on nesh** (once, on the login node — it has internet):

   ```bash
   curl -LsSf https://astral.sh/uv/install.sh | sh
   ```

   `uv` rather than conda is deliberate: conda materialises 100k+ tiny files and
   can blow the home-filesystem inode quota on its own; `uv` stays lean.

4. **Make a small, code-only project directory, separate from the data.** Under
   `$HOME` (backed up, meant for code) is right:

   ```bash
   mkdir -p "$HOME/projects/nemo_cmems_analysis"
   cd "$HOME/projects/nemo_cmems_analysis"
   ```

   Keep the multi-terabyte NEMO output *out* of this tree — the agent reaches it
   by explicit path, never by having it underfoot. This one choice is the biggest
   lever for keeping the agent off the shared filesystem ([§5](#5-keep-the-agent-off-the-shared-filesystem-and-not-blind)).

5. **Drop in the agent's guardrails.** Copy three templates from this repo into the
   project:

   - the base [`CLAUDE.md`](CLAUDE.md) **plus** the appended
     [nesh snippet](claude_md_nesh_snippet.md) → your project `CLAUDE.md`;
   - [`settings_nesh_example.json`](settings_nesh_example.json) →
     `.claude/settings.json`;
   - the [`catalogue_template/`](catalogue_template/) → `catalogue/` (you fill it
     in — [§6](#6-a-small-data-catalogue-so-the-agent-isnt-blind)).

6. **Launch Claude, scoped to the project:**

   ```bash
   cd "$HOME/projects/nemo_cmems_analysis" && claude
   ```

   Launching *inside* the project (never `$HOME` or a scratch root) bounds the
   agent's automatic context-gathering to code it can safely search.

---

## 3. Running under SLURM

nesh uses **SLURM** (`sbatch`, `srun`, `salloc`, `squeue`, `scancel`). It was
migrated off the old NEC NQSII system, so ignore any page that talks about
`qsub`/`#PBS`.

**Login nodes are for editing, small transfers, and submitting jobs — not
computation.** Anything heavier than reading a netCDF header goes into an
allocation. An interactive shell on a compute node:

```bash
# 1 hour, 4 cores, 8 GB, on the general-purpose "base" partition
srun --pty --time=01:00:00 --mem=8000 --nodes=1 --cpus-per-task=4 \
     --partition=base /bin/bash
```

- `base` is the default compute partition (48 h max walltime).
- `interactive` is a short partition (≈12 h cap, external networking) handy for
  download-heavy work.
- `--mem` is in **MB** by default; leave 1–2 GB headroom. **A bigger `--mem` is
  the simplest fix if an analysis runs out of memory** — reach for it before you
  tune anything.

For anything long or unattended, use a batch job:

```bash
#!/bin/bash
#SBATCH --job-name=nemo_analysis
#SBATCH --partition=base
#SBATCH --cpus-per-task=8
#SBATCH --mem=32000
#SBATCH --time=02:00:00

cd "$WORK/nemo_cmems_run"                 # run job I/O from $WORK
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
uv run python scripts/sst_orca025.py
# submit with: sbatch thisscript.sh
```

**The internet proxy.** Compute nodes on `base` reach the outside world only
through the site HTTP proxy. Anything that downloads — `copernicusmarine`, `uv`
resolving packages, `git`, *and Claude Code's own API traffic when you run it in
an allocation* — needs:

```bash
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
```

The official docs show `https_proxy=http://10.0.7.235:3128`; setting `http_proxy`
to the same value is the safe convention. It's the single most common reason "it
worked on the login node but hangs in the job." Login / `interactive` / data-mover
nodes have direct networking. **Confirm the exact value (and whether `no_proxy` is
needed) with `hpcsupport`.**

**Storage** — put things in the right place (`<inst>` is the literal `cau` or
`geomar`):

| Variable | Path | Use | Backed up? |
|---|---|---|---|
| `$HOME` | `/gxfs_home/<inst>/<user>` | code, scripts, this project, small results | yes (≈200 GB cap) |
| `$WORK` | `/gxfs_work/<inst>/<user>` | **all job I/O**, intermediate/large data | no (TB-scale) |
| `$TMPDIR` | `/scratch/SlurmTMP/<user>.<jobid>` | node-local per-job scratch; **dask spill** | no (gone at job end) |
| `$CEPH` | `/nfs/ceph_<inst>/<user>` | cold long-term storage | no |

Check usage with `workquota` (home/work) and `cephquota`. Note the paths are
`/gxfs_home/...` and `/gxfs_work/...`, not `/home/...`.

---

## 4. Jupyter from your laptop

When you want a real notebook, run JupyterLab **on a compute node** and reach it
from your laptop browser through an SSH tunnel. Don't reinvent this — GEOMAR's
[`jupyter_on_HPC_setup_guide`](https://git.geomar.de/python/jupyter_on_HPC_setup_guide)
already has the tunnel script; use its SOCKS5 / SSH-tunnel part. (Ignore the
conda-env and jupyter-manager pieces. Its job script is written for the old PBS
scheduler — translate it to SLURM as below; the tunnel mechanics are unchanged.)

The flow, which **you** drive step by step:

1. **On nesh**, submit a job that launches JupyterLab bound to the node's own
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
   uv run jupyter lab --no-browser --ip="$(hostname)"
   ```

2. **Read the token URL** from the job's output file (`jupyterlab.<jobid>.out`) —
   a line like `http://nesh-clk399:8888/?token=abc123…`. That internal hostname +
   token is what you open.

3. **On your laptop**, open a dynamic SOCKS proxy and point an isolated browser at
   it:

   ```bash
   ssh -f -D localhost:54321 nesh sleep 60
   chromium --proxy-server="socks5://localhost:54321" \
            --proxy-bypass-list="<-loopback>" \
            --user-data-dir=/tmp/nesh-jlab \
            'http://nesh-clk399:8888/?token=abc123…'
   ```

   GEOMAR's helper `run_chromium_through_ssh_tunnel.sh` does the same thing (picks
   a free port, launches an isolated Chromium) — grab it from the guide if you'd
   rather not type the above.

Two things that trip people up:

- **Why `-D` (SOCKS) and not `-L`?** You don't know which compute node you'll land
  on until the job starts, and it's only reachable *through* the login node. A
  SOCKS proxy lets the browser reach any internal `host:port` without hard-coding
  the node name.
- **`--proxy-bypass-list="<-loopback>"` is not optional cargo.** Chrome/Chromium
  (≳ v72) refuses to send loopback addresses through a SOCKS proxy by default;
  this flag re-enables it. If the page just won't load, this — or your browser
  version — is the usual culprit (the GEOMAR guide's issue tracker documents both
  the fix and later browser-version regressions).

The **dask dashboard** (`:8787`, [§8](#8-nemo--netcdfxarraydask-in-one-page))
rides the exact same tunnel — it's just another internal `host:port` the SOCKS
proxy can route to.

> nesh may by now ship its own SLURM-native Jupyter instructions; the current user
> docs at <https://www.hiperf.rz.uni-kiel.de/nesh/> are worth a look before you
> lean on the older GEOMAR job script.

---

## 5. Keep the agent off the shared filesystem (and not blind)

nesh's `gxfs` filesystems are **shared and parallel** (NEC GxFS, built on IBM
Spectrum Scale / GPFS). Every `stat`/`readdir` is a request to metadata storage
the whole cluster shares. A recursive walk — `find`, `grep -r`, `ls -R`, `du` over
`$HOME`, `$WORK`, or a data root — fires one such request *per file and directory*
and can produce a metadata storm that slows the cluster for everyone. On a tree
with millions of files, one careless walk is enough. This is the classic way to
earn a friendly email from the admins.

The catch specific to agents: **Claude Code runs `ls`, `cat`, `head`, `tail`,
`grep`, `find`, `wc`, `stat`, `du` (and read-only `git`) with no prompt, in every
mode** — that read-only set is documented and not configurable. So the agent's
instinct to "get the lay of the land" by tree-walking runs silently. Three levers
help, in decreasing order of how much they actually buy you:

1. **Scope the launch — this is the one that holds.** Launch `claude` from the
   small, code-only project directory ([§2](#2-first-time-setup-do-this-once)),
   never `$HOME` or scratch. That bounds Claude's ripgrep-backed Grep/Glob tools
   and its auto context-gathering to your code — there's simply nothing big to
   walk, so you can leave those tools enabled. The corollary: **never `--add-dir`
   the data root** (or list it in `additionalDirectories`); that undoes the
   scoping.

2. **`settings.json` deny rules — a real but leaky fence.** The example
   [`settings_nesh_example.json`](settings_nesh_example.json) denies the
   reflexive walk commands (`find`, `du`, `ls -R`, `grep -r`, `tree`). Deny beats
   allow at every settings layer, so committing it in the project is enough. Its
   real job is stopping a manual **absolute-path** walk (`find /gxfs_work/…`),
   which scoping alone can't catch. Be honest about the limits, though: Bash
   pattern matching is a coarse prefix heuristic, not a security boundary — e.g.
   `grep -r` is denied but `grep -rn` slips past. It stops the agent's *default*
   walks; it is not a guarantee. That's fine — lever 1 is what really holds.

3. **`CLAUDE.md` house rules — a nudge.** The [nesh snippet](claude_md_nesh_snippet.md)
   tells the agent, in plain language, not to walk the data tree and to read the
   catalogue instead. A well-behaved agent honours it; it is guidance, not
   enforcement.

**Don't over-engineer past this.** You don't need hooks, a sandbox, or a blanket
Grep/Glob ban — the last would just take away cheap, safe search over your own
code for no filesystem benefit. Scope the launch, commit the deny list, add the
`CLAUDE.md` line, and give the agent a catalogue so it isn't blind ([§6](#6-a-small-data-catalogue-so-the-agent-isnt-blind)).

> If the site ships a *managed* Claude Code settings file, it can override your
> project settings — worth asking `hpcsupport` whether one is deployed.

---

## 6. A small data catalogue, so the agent isn't blind

If the agent can't walk the filesystem, how does it know what data exists and how
it's shaped? You give it a tiny, **checked-in catalogue** it reads instead — the
single-user substitute for a real data-catalogue service. It lives in a
`catalogue/` directory in the project (template in
[`catalogue_template/`](catalogue_template/)) and is just three cheap ingredients:

1. **CDL headers — authoritative, machine-readable.** `ncdump -h -s` prints a
   file's dimensions, variables, and its on-disk chunking/compression
   (`_ChunkSizes`, `_DeflateLevel`, `_Shuffle`) while reading **zero** data.
   Commit one `.cdl` per representative stream:

   ```bash
   ncdump -h -s /path/to/ORCA025/rep_grid_T.nc > catalogue/orca025_grid_T.cdl
   ```

2. **`DATA.md` — prose the header can't carry.** For each dataset: the one stable
   path (marked "do not walk"), grid family and resolution, where `mesh_mask.nc`
   lives, the `grid_T/U/V/W` naming pattern, time coverage, rough size, and
   gotchas. This is where you tell the agent *which variable means what* and
   *which directory is off-limits to scanning*.

3. **`tree.txt` — a one-time, shallow snapshot.** Pay the metadata cost **once,
   deliberately, by hand**, at shallow depth:

   ```bash
   find "$DATA_ROOT" -maxdepth 2 -type d | sort > catalogue/tree.txt
   ```

The workflow that keeps this bootstrappable: **the agent proposes, you run and
commit.** Claude drafts `DATA.md` and the exact `ncdump`/`find` commands; *you*
run them (they're bounded and deliberate) and commit the result. When new data
lands, ask the agent to update the catalogue and re-run the generator. A
[`regenerate.sh`](catalogue_template/regenerate.sh) captures the recipe. CDL
*or* prose isn't the right question — you want both: the header for exact
shapes, the prose for meaning.

---

## 7. What to confirm locally

Everything above is real per the current nesh docs, but it's exactly what drifts.
Check on your account (ask the agent to help, or email `hpcsupport`):

- **Proxy** — the exact `http_proxy`/`https_proxy` value, whether `no_proxy` is
  needed, and which node classes require it.
- **Partitions & quotas** — that `base`/`interactive`/`highmem`/`gpu` are current,
  and your `$HOME`/`$WORK` space **and inode** quotas (`workquota`). nesh doesn't
  require an `--account` string; don't add one unless your project has one.
- **Your data** — inspect each stream with `ncdump -h -s`: whether it's already a
  single file or still per-processor (needs `rebuild_nemo`), whether lon/lat are
  1-D or 2-D ([§8](#8-nemo--netcdfxarraydask-in-one-page)), and the real
  `_ChunkSizes` before choosing dask chunks.
- **Jupyter** — whether nesh now has its own SLURM-native Jupyter recipe, and that
  `<-loopback>` still works in your browser version.

---

## 8. NEMO + netCDF/xarray/dask, in one page

This is the domain knowledge the agent needs to be *correct* and to *not blow up
memory*. It's condensed into the [nesh snippet](claude_md_nesh_snippet.md) so the
agent applies it by default; here's the reasoning.

**Triage the file first.** Not everything on nesh is curvilinear. Many CMEMS
products are distributed already regridded onto a **regular lon/lat grid** with
1-D `longitude`/`latitude` coordinates — there, `.sel(longitude=…, latitude=…)`
works normally and the traps below don't apply. Run `ncdump -h` (or look at
`ds.coords`): if lon/lat are **1-D dimension coordinates**, you're fine; if
`nav_lon`/`nav_lat` are **2-D arrays over `(y, x)`**, it's native NEMO/ORCA and
the C-grid rules kick in.

**Native NEMO is on a staggered Arakawa C-grid.** Scalars (T, S, SSH) sit at cell
centres (**T** points); velocities on the faces (**U**, **V**); vertical terms at
**W**; corners at **F**. Output is split by point type into `grid_T`/`grid_U`/
`grid_V`/`grid_W` files, one per period. Grid metrics and land–sea masks (`glam*`,
`gphi*`, `e1*`/`e2*` cell sizes **in metres**, `e3*`, `tmask` etc.) live in
`mesh_mask.nc` / `domain_cfg.nc` — keep those paths in the catalogue; most real
analysis needs them.

**The gotcha that fails loudly:** `nav_lon`/`nav_lat` are 2-D curvilinear arrays
over the index dims `(y, x)`, not 1-D coordinates — so `ds.sel(lon=…, lat=…)`
errors. Select with **`.isel`** on `x`/`y`, or use grid-aware tools (`cf-xarray`,
`xgcm`, `xnemogcm`, `xESMF` for regridding).

**The gotcha that fails *silently* — the dangerous one:** `grid_T`, `grid_U`, and
`grid_V` files share the *same* integer `(y, x)` dimensions, so xarray happily does
arithmetic across them with no error — even though a U-point is half a cell east of
the T-point at the same index. Anything that mixes grids (`speed = sqrt(u**2 +
v**2)`, fluxes, gradients) then pairs points that aren't co-located and produces a
quietly wrong field. Interpolate onto a common point first (`xgcm`/`xnemogcm`).
Related: an **unweighted** `.mean` over `(y, x)` is biased — weight spatial means
by cell area `e1t*e2t` (and `e3t` for volumes) and apply `tmask`.

**Other NEMO notes:** global ORCA tops out around 1/12° — the ~1/100° resolution
you're after comes from regional **AGRIF nests** (`1_`/`2_` filename prefixes),
not a global grid. The tripolar **north fold** along the top row can duplicate
cells and flips vector signs (older NEMO ≤4.0.x keeps those rows; ≥4.2.0 strips
them) — be wary of the northernmost rows.

**netCDF chunking → dask, and staying lazy** (the memory rules):

- Large files are internally **chunked and deflated**. Read the on-disk chunking
  from the catalogue's `.cdl` (or `ncdump -h -s`, or `ds[var].encoding`). To open
  many files lazily: `xr.open_mfdataset(..., data_vars="minimal",
  coords="minimal", compat="override")` so xarray doesn't re-read the big 2-D
  coords in every file; `engine="h5netcdf"` is often faster.
- **Stay lazy.** `.values`, `.compute()`, `.load()`, `.plot()` pull data into
  memory *now* — on a global 3-D field that's tens of GB into one process. Reduce
  or subset **first** (`.isel`, `.mean`), then materialise the small result. This
  is the single biggest OOM preventer.
- **Chunk size:** aim for ~100 MB per dask chunk (≳1e6 elements). Aligning chunks
  to be integer multiples of the on-disk `_ChunkSizes` avoids re-reading
  compressed blocks — a real speed-up, but an *optimisation*, not a prerequisite
  for opening the file. Start rough; tune if it's slow.
- **dask:** start with a single-node `LocalCluster` inside an allocation, spilling
  to node-local scratch — `local_directory=os.environ["TMPDIR"]`, **never** a
  shared filesystem. Reach for `dask_jobqueue.SLURMCluster` only when one node
  isn't enough (and there, write `memory="60GiB"` — SLURM's "GB" means GiB and
  you'll otherwise get slightly *less* than you asked for). Workers never run on
  the login node.

## Sources

- nesh user docs — <https://www.hiperf.rz.uni-kiel.de/nesh/> (Slurm, filesystems,
  software/proxy, access)
- GEOMAR Jupyter-on-HPC setup guide — <https://git.geomar.de/python/jupyter_on_HPC_setup_guide>
- NEMO user guide — <https://sites.nemo-ocean.io/user-guide/> ·
  `xnemogcm` <https://xnemogcm.readthedocs.io/> · `xgcm` <https://xgcm.readthedocs.io/>
- Claude Code permissions & settings — <https://code.claude.com/docs/en/permissions>,
  <https://code.claude.com/docs/en/settings>
- xarray & dask — <https://docs.xarray.dev/en/stable/user-guide/dask.html>,
  <https://docs.dask.org/en/stable/deploying-hpc.html>, <https://jobqueue.dask.org/>
