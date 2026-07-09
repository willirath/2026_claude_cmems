# CLAUDE.md — nesh HPC snippet

This is the block to **append to your project `CLAUDE.md`** when the project runs
on **nesh** (CAU Kiel / GEOMAR HPC). It carries the conventions the agent should
honour by default; the reasoning and setup live in
[`hpc_nesh.md`](hpc_nesh.md). Copy everything below the line into your
`CLAUDE.md`, then adjust the `<placeholders>` to your account.

> Remember what `CLAUDE.md` is and isn't: it's a strong *nudge*, not enforcement.
> The filesystem rules below are backed by real deny rules in
> `.claude/settings.json` (see [`settings_nesh_example.json`](settings_nesh_example.json))
> and by launching `claude` from this project directory. Keep all three in place.

---

## HPC environment (nesh)

This project runs on **nesh** (CAU Kiel / GEOMAR). Key facts:

- **Scheduler is SLURM** (`sbatch`, `srun`, `salloc`, `squeue`) — *not* PBS/NQSII.
  Ignore any `qsub`/`#PBS` advice.
- **Never run heavy compute on the login node.** Editing, reading the catalogue,
  `ncdump -h`, and submitting jobs are fine there. Real computation goes in an
  allocation: `srun --pty --time=01:00:00 --mem=4000 --partition=base /bin/bash`,
  or a batch job on `base`.
- **Storage:** code and this project live in `$HOME` (`/gxfs_home/...`, backed up,
  small). **All job/data I/O uses `$WORK`** (`/gxfs_work/...`, large, not backed
  up). dask spill and scratch go to node-local `$TMPDIR` (`/scratch/SlurmTMP/...`).
- **Internet is behind a proxy on compute nodes.** Before anything downloads
  (`copernicusmarine`, `uv`, `pip`, `git`) inside a `base`-partition job/shell,
  export:
  ```bash
  export http_proxy=http://10.0.7.235:3128
  export https_proxy=http://10.0.7.235:3128
  ```
  (Login / `interactive` nodes have direct networking. Confirm the exact proxy
  with the user if a download hangs.)
- **Python via `uv` only** (`uv add`, `uv run`) — not conda. Conda's huge file
  count exhausts the home-filesystem inode quota; `uv` stays lean.

## Filesystem discipline (shared parallel FS — this matters)

- **Do NOT run `find`, `grep -r`, `grep -R`, `ls -R`, `rg`, `du`, or `tree` over
  the data tree, `$WORK`, `$HOME`, or any large directory.** This is a shared
  parallel filesystem; recursive walks cause metadata storms that slow the whole
  cluster. (These commands are also denied in `.claude/settings.json`.)
- **To learn what data exists and how it's shaped, read the catalogue** —
  `catalogue/DATA.md`, `catalogue/tree.txt`, and the `catalogue/*.cdl` header
  dumps. That is the index; treat it as the source of truth for paths and layout.
- **Reach data files by explicit path only** (paths come from the catalogue).
  Never scan for them. If you need a file that isn't catalogued, **ask the user
  to add it** — propose the exact `ncdump -h -s <file> > catalogue/<name>.cdl`
  command and let them run it.
- Searching this small project directory (your own code) with Grep/Glob is fine —
  it's local and cheap. The rule is about the *data* tree, not the project.

## NEMO / ORCA data conventions

- NEMO output is on a staggered **Arakawa C-grid**: T (centre: temperature,
  salinity, SSH), U/V (velocities on faces), W (vertical), F (corners). Grid
  metadata (`glam*`, `gphi*`, `e1*`/`e2*` in metres, `e3*`, masks `tmask` etc.)
  lives in `mesh_mask.nc` / `domain_cfg.nc` / `coordinates.nc` — find their paths
  in `catalogue/DATA.md`.
- **`nav_lon`/`nav_lat` (and `glamt`/`gphit`) are 2-D curvilinear arrays over the
  index dims `(y, x)`, not 1-D coordinates.** `ds.sel(lon=…, lat=…)` does **not**
  work on the horizontal dims — select with **`.isel`**, or use `cf-xarray` /
  `xgcm` / `xnemogcm` / `xESMF`. Assume ORCA/eORCA tripolar grids; be wary of the
  north-fold rows (duplicated cells, vector sign flips). High-res (~1/100°) comes
  from AGRIF nests with `1_`/`2_` filename prefixes.
- Output is split by grid-point type into `grid_T` / `grid_U` / `grid_V` /
  `grid_W` files, one per output period. If files are still per-processor tiles,
  they need `rebuild_nemo` first — check `catalogue/DATA.md`.

## netCDF + xarray + dask conventions

- **Inspect on-disk chunking before choosing dask chunks.** Read the `.cdl` in
  the catalogue (or `ncdump -h -s file.nc`, or `ds[var].encoding`) for
  `_ChunkSizes` / `_DeflateLevel`. **dask chunks must be integer multiples of the
  on-disk `_ChunkSizes`** (misalignment = read amplification). Target ~100 MB per
  chunk.
- Open many files with
  `open_mfdataset(..., combine="nested", concat_dim="time_counter",
  parallel=True, data_vars="minimal", coords="minimal", compat="override")`,
  `drop_variables=[...]` the big 2-D coords you don't need; `engine="h5netcdf"`
  is often faster.
- **Stay lazy.** Never call `.values` / `.compute()` / `.load()` / `.plot()` on a
  full global 3-D field — reduce/subset (`.isel`, `.mean`) first, then materialise
  only the small result.
- dask: start with a single-node `LocalCluster` inside an allocation; use
  `SLURMCluster` only when one node isn't enough; workers never run on the login
  node; set `local_directory` to node-local `$TMPDIR`; sizes are per-job and SLURM
  reads "GB" as GiB (use `memory="…GiB"`).

## Working with the human

- The user handles SSH and the Jupyter SSH/SOCKS5 tunnel themselves. Assist by
  explaining, drafting job scripts, and troubleshooting — don't try to `ssh` or
  open tunnels on their behalf.
- Prefer proposing a `sbatch` script or an `srun` interactive command over running
  long computes yourself in the session.
