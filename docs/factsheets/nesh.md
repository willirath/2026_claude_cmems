# nesh — cluster factsheet

The HPC system run by Kiel University's computing centre (RZ) together with GEOMAR.
This is reference material for the agent working on nesh — read the relevant parts
before running anything here. Values marked _(confirm)_ drift between accounts and
over time: check them against the live environment or ask the user. Only as a last
resort should the user email `hpcsupport@rz.uni-kiel.de`.

## Access

- Login host `nesh-login.rz.uni-kiel.de` (round-robins across login1/2/3).
  Off-campus needs the **CAU or GEOMAR VPN** first (same credentials). Accounts:
  <https://www.rz.uni-kiel.de/en/our-portfolio/hiperf/nesh>.
- **No `--account` / project string is needed** — scheduling is fair-share
  (`sshare`). Don't add an account flag.

## Scheduler: SLURM

- `sbatch` (batch), `srun` / `salloc` (interactive), `squeue`, `scancel`.
- **Login nodes are for editing, small transfers, submitting jobs, and reading
  netCDF headers — not computation.** Anything heavier goes in an allocation.
- Interactive shell on a compute node:

  ```bash
  srun --pty --time=01:00:00 --mem=8G --cpus-per-task=4 --partition=base /bin/bash
  ```

- Write `--mem` with a unit (`--mem=8G`); a bare number means MB. Leave 1–2 GB
  headroom. **Raising `--mem` is the first fix for an out-of-memory analysis** —
  reach for it before tuning code.

## Partitions _(confirm names/limits)_

| Partition | For | Notes |
|---|---|---|
| `base` | default compute | 48 h cap; 32 cores/node (256 GB Sapphire / 192 GB Cascade) |
| `interactive` | download-heavy / interactive work | ~12 h cap, direct external network, one job per user |
| `highmem` | memory-bound work | 1–1.5 TB nodes |
| `gpu` | GPU work | H100 / V100 |
| `data` | staging / transfers | 10 GbE movers, up to 50 days, ≤4 cores — not storage |

`--qos=long` lifts the 48 h `base` cap.

## Internet proxy

Compute nodes on `base` (and `highmem` / `gpu`) reach the outside world **only
through the site HTTP proxy**. Anything that downloads — `copernicusmarine`, `uv`,
`pip`, `git`, and Claude Code's own API traffic when it runs inside an allocation —
needs:

```bash
export http_proxy=http://10.0.7.235:3128
export https_proxy=http://10.0.7.235:3128
```

Login, `interactive`, and `data` nodes have direct networking. This is the most
common reason something "works on the login node but hangs in the job." _(confirm
the exact value and whether `no_proxy` is needed)_

## Filesystems (gxfs — shared parallel FS)

`<inst>` is the literal `cau` or `geomar`.

| Variable | Path | Use | Backed up |
|---|---|---|---|
| `$HOME` | `/gxfs_home/<inst>/<user>` | code, scripts, this project, small results | yes (~150/200 GB) |
| `$WORK` | `/gxfs_work/<inst>/<user>` | all job I/O, large & intermediate data | no (TB-scale) |
| `$TMPDIR` | `/scratch/SlurmTMP/<user>.<jobid>` | node-local per-job scratch, **dask spill** | no (gone at job end) |
| `$CEPH` | `/nfs/ceph_<inst>/<user>` | cold long-term storage | no (~1 TB) |

- Paths are `/gxfs_home/...` and `/gxfs_work/...`, not `/home/...`.
- Check usage with `workquota` (home/work) and `cephquota`. Inode quotas bite too.
- It is a **shared parallel filesystem**: recursive metadata walks (`find`,
  `grep -r`, `ls -R`, `du`, `tree` over `$WORK`, `$HOME`, or a data root) fire one
  metadata request per file and can slow the cluster for everyone. **Avoid them —
  reach data by explicit path.** When you do need to look, a single non-recursive
  listing of one directory (`\ls <dir>`, no `-R`) is effectively instantaneous and
  fine; it's the deep walks that cause storms.

## Python

- Use **`uv`** (`uv add`, `uv run`). Avoid conda — it materialises 100k+ tiny files
  and can exhaust the home **inode** quota on its own.

## Source

- nesh user docs — <https://www.hiperf.rz.uni-kiel.de/nesh/> (authoritative for
  everything above)