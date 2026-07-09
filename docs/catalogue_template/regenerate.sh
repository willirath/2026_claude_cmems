#!/bin/bash
# Regenerate the data catalogue — run this DELIBERATELY, by hand, not from an
# agent loop. Every command here is bounded on purpose: header-only dumps that
# read no data, and a single shallow directory walk. See ../hpc_nesh.md §6.
#
# Usage:
#   1. Edit DATA_ROOT and the FILES list below to match your data.
#   2. Run on the nesh login node:  bash regenerate.sh
#   3. Review, then commit catalogue/ to the repo.
#
# Do NOT turn this into a recursive scan. The whole point of the catalogue is to
# pay the metadata cost once, on your terms, instead of letting a tree-walk hit
# the shared filesystem.

set -euo pipefail

# --- edit these ------------------------------------------------------------
DATA_ROOT="/gxfs_work/<group>/<user>/data"

# One representative file per stream you want catalogued. Header-only (`-h`)
# with special attrs (`-s`) so chunking/deflation show up; reads zero data.
FILES=(
  "$DATA_ROOT/ORCA025/hindcast/rep_grid_T.nc"
  # "$DATA_ROOT/ORCA025/hindcast/rep_grid_U.nc"
  # "$DATA_ROOT/ORCA025/mesh_mask.nc"
  # "$DATA_ROOT/CMEMS/rep_so.nc"
)
# ---------------------------------------------------------------------------

here="$(cd "$(dirname "$0")" && pwd)"

# 1) CDL header dumps (cheap; no data read).
for f in "${FILES[@]}"; do
  name="$(basename "${f%.nc}")"
  echo "ncdump -h -s  ->  ${name}.cdl"
  ncdump -h -s "$f" > "${here}/${name}.cdl"
done

# 2) ONE shallow directory snapshot. -maxdepth keeps it bounded; this is the only
#    walk in this file, and you are running it deliberately.
echo "find -maxdepth 2  ->  tree.txt"
find "$DATA_ROOT" -maxdepth 2 -type d | sort > "${here}/tree.txt"

echo "Done. Review ${here}/*.cdl and tree.txt, update DATA.md, then commit."
