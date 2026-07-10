# NEMO / ORCA — model-output factsheet

Reference for the agent working with native NEMO ocean-model output (ORCA family).
For the netCDF / chunking / lazy-reading mechanics that apply to any large file, see
the **model-outputs** factsheet.

## Triage first

Get an overview with `ncdump -h` (or `ds.coords`) — no need to inspect literally
every file; if the output layout changed partway through a run, trust xarray to fail
loudly rather than pre-checking each one:

- **1-D `longitude` / `latitude`** dimension coordinates → a regridded product;
  `.sel(longitude=…, latitude=…)` works and the C-grid rules below don't apply.
- **2-D `nav_lon` / `nav_lat` over `(y, x)`** → native NEMO/ORCA; apply the rules
  below.

## The C-grid

- NEMO output sits on a staggered **Arakawa C-grid**. Points: **T** at the cell
  centre (`thetao`, `so`, `zos`), **U** on the east/west face (`uo`), **V** on the
  north/south face (`vo`), **W** on the top/bottom face (vertical), **F** at the
  cell corner (vorticity).
- **Which index is which face** (matters for divergence and any flux through a
  face): at `(j, i)`, `u(i)` is the **east** face of `t(i)` and `u(i-1)` the west;
  `v(j)` the **north** face of `t(j)` and `v(j-1)` the south; `f(i,j)` the
  north-east corner. So the faces bracketing `t(i)` are `u(i-1)` / `u(i)`, and
  horizontal divergence in a T-cell differences `u(i) - u(i-1)` and `v(j) - v(j-1)`
  (NEMO's `div_hor`) — **not** `u(i+1) - u(i)`.
- Fields are split by point type into **`grid_T` / `grid_U` / `grid_V` / `grid_W`**
  files, one set per output period.
- **Grid metrics and masks live in `mesh_mask.nc` / `domain_cfg.nc`**, not the
  field files: cell widths `e1{t,u,v,f}`, `e2{t,u,v,f}` and thicknesses
  `e3{t,u,v,w,f}` (all in **metres**), point coordinates `glam*` / `gphi*`, and
  masks `tmask` / `umask` / `vmask` / `fmask`. Most real analysis needs them. The
  **vertical** thicknesses are the fiddly part: `e3*` may be a 1-D reference column,
  a full 3-D partial-cell field (`ln_zps`), or time-varying `e3*(t)` under a
  non-linear free surface (z\*/vvl) — and names and dimensionality drift across NEMO
  versions and CMEMS post-processing. Open the actual `mesh_mask.nc` /
  `domain_cfg.nc` (or the product's coordinate file) to see which form you have
  before computing volumes or transports; ask the user if it's ambiguous.
- ORCA is **tripolar**: two mesh north poles over land remove the pole singularity,
  joined by a **north fold** across the top rows — those rows mirror/duplicate cells
  and vector components flip sign. Be wary of the northernmost rows.
- **Mind the boundary rows/columns generally, not only the fold.** A global ORCA
  file wraps east–west with duplicated overlap columns and has a closed southern
  row; treating the outermost `x` / `y` indices as physical double-counts in a
  global `.sum` / `.mean`. Check before reducing over the full domain.

## Indexing & alignment gotchas

- **`.sel(lon, lat)` fails on native ORCA.** `nav_lon` / `nav_lat` are 2-D
  curvilinear arrays over `(y, x)`, not 1-D dimension coordinates, so label-based
  `.sel` on longitude/latitude has no axis to index against. Select by integer
  index with **`.isel(x=…, y=…)`**.
- **`x` / `y` usually have no coordinate variables.** NEMO files typically ship the
  horizontal (and often the vertical/time) dimensions as bare sizes with no index
  coordinate. Then a `.shift(x=1)` or `.diff("x")` result has nothing for xarray to
  align on, so recombining it with the original array — which every C-grid stagger
  operation does — silently mis-pairs or drops cells. **Assign integer coords right
  after loading** so shifts and differences line up predictably:

  ```python
  import numpy as np
  ds = ds.assign_coords(x=np.arange(ds.sizes["x"]), y=np.arange(ds.sizes["y"]))
  ```

- **The silent one — never do arithmetic mixing `grid_T` / `grid_U` / `grid_V` by
  index.** They share the same integer `(y, x)` dims but sit half a cell apart, so
  xarray combines them with **no error** and the result is quietly wrong (e.g.
  `speed = sqrt(uo**2 + vo**2)` pairs points that aren't co-located). Move each field
  to a common point first — average the two neighbouring U (or V) cells onto the
  T-point (see below). Likewise an unweighted `.mean` over `(y, x)` is biased —
  weight by cell area `e1t*e2t` (and `e3t` for volumes) and apply `tmask`.

## Derived quantities on the C-grid (plain xarray)

No grid-aware wrapper is needed: the C-grid operators are a few `.shift` / difference
/ average steps with the `e1/e2/e3` scale factors. Reason from the staggering — which
neighbouring points to combine, and which point the result lands on — rather than
trusting a black box. For a subtle diagnostic, work out that grid logic (and, where a
definition is itself ambiguous — see kinetic energy and vorticity below — the
underlying NEMO numerics) **before** writing code: reasoning over this sheet is
usually enough, but the NEMO source (`divhor.F90`, `dynkeg.F90`, `dynvor.F90`) or
CDFTOOLS is the ground truth when it isn't. (Assign `x`/`y` coords first, as above.)
Two primitives:

- **Interpolate** a face value to the centre = **average the two neighbours**, e.g.
  U→T is `0.5 * (u + u.shift(x=1))` (NEMO's convention puts `u(i)` on the east face
  of `t(i)`, so `u(i)` and `u(i-1)` straddle `t(i)`); V→T is `0.5 * (v + v.shift(y=1))`.
- **Differentiate** = **neighbour difference ÷ local scale factor**, e.g.
  `(a.shift(x=-1) - a) / e1?`.

The shift direction (`+1` vs `-1`) follows the file's index convention for where
U/V/F sit relative to T — **verify it on the data** (e.g. check a land mask or a
known-sign field lines up) rather than assuming.

**Kinetic energy — order of operations matters.** KE at the T-point is *not*
½(ū² + v̄²) of the interpolated velocities. NEMO (`dynkeg`) squares the face
velocities first, then averages onto T: KE = ¼(u(i-1)² + u(i)²) + ¼(v(j-1)² + v(j)²).
The two forms differ by the velocity variance across the cell — real energy in
sheared flow — so square-then-average, matching the model:

```python
u = ds.uo; v = ds.vo
ke = 0.25 * (u.shift(x=1)**2 + u**2) + 0.25 * (v.shift(y=1)**2 + v**2)   # at T-point
```

**Relative vorticity / curl** ζ = ∂v/∂x − ∂u/∂y. It naturally lands on the **F-point
(corner):** ∂v/∂x differences two V-points along x and ∂u/∂y differences two U-points
along y, and the corner is the only place both differences co-locate. NEMO writes it
with the metrics folded in, ζ = 1/(e1f·e2f) · [ Δ_x(e2v·v) − Δ_y(e1u·u) ] where
Δ_x A(i) = A(i+1) − A(i):

```python
u = ds.uo.isel(depthu=0); v = ds.vo.isel(depthv=0)          # surface level
dvx = (ds.e2v * v).shift(x=-1) - (ds.e2v * v)               # ∂/∂x of e2v·v, lands on F
duy = (ds.e1u * u).shift(y=-1) - (ds.e1u * u)               # ∂/∂y of e1u·u, lands on F
zeta = (dvx - duy) / (ds.e1f * ds.e2f) * fmask_surface      # fmask[0] or fmaskutil
```

There's more than one defensible discrete ζ: compute it at F (above), interpolate the
F-point value to T, or interpolate the *velocities* first — NEMO's `dynvor` ships
several schemes (ENS / ENE / EEN / ENT) that differ in what they interpolate and which
invariant (energy, enstrophy) they conserve. All are second-order and converge to the
same continuous ζ as dx, dy → 0; choose the point you need the answer on and
interpolate consistently.

**Meridional overturning streamfunction (z-coordinates)** ψ(y, z) in Sv — meridional
volume transport, summed zonally, integrated over depth from the sea floor upward:

```python
e3v = ds.e3v_0 * ds.vmask                    # V-cell thickness [m], land-masked
vtrsp = ds.vo * ds.e1v * e3v                 # meridional volume transport per cell [m^3/s]
Vz = vtrsp.sum("x")                          # zonal integral -> (depth, y)
psi = -Vz.isel(depthv=slice(None, None, -1)).cumsum("depthv").isel(depthv=slice(None, None, -1)) / 1e6
```

Sanity check: the Atlantic (AMOC) cell should come out **positive** (order +15 Sv
near 1000 m) — sign and integration direction are conventions, so verify it. Under a
non-linear free surface (z\*/vvl) use the **time-varying `e3v(t)`**, not `e3v_0`.
Dimension names (`x`/`y`, `depthu`/`depthv`/`deptht`, `time_counter`) and field names
(`uo`/`vo`/`thetao`/`so` in NEMO 4+ and CMEMS) vary by product — adapt them to the
file.

## Sources

For an agent the **git-hosted sources below are easier to read and grep than the
rendered PDF or HTML** — go to the `.F90` / `.tex` / `.rst` directly.

- NEMO model source code — <https://forge.nemo-ocean.eu/nemo/nemo> — often the
  clearest ground truth. The discrete operators used above are in `src/OCE/DYN/`:
  `divhor.F90` (divergence), `dynkeg.F90` (kinetic energy), and `dynvor.F90`
  (vorticity, incl. the ENS / ENE / EEN / ENT scheme options).
- NEMO reference manual ("NEMO ocean engine") — **LaTeX source**
  <https://forge.nemo-ocean.eu/nemo/doc/manuals> (NEMO / SI³ / TOP; grep the `.tex`
  for the C-grid, scale factors, and ORCA tripolar grid). Published PDF on Zenodo —
  <https://doi.org/10.5281/zenodo.6334656>. (The old per-section
  `nemo-ocean.eu/doc/node*.html` pages are gone — don't link them.)
- NEMO user guide (install / config / run) — rendered
  <https://sites.nemo-ocean.io/user-guide/>, reStructuredText source
  <https://forge.nemo-ocean.eu/nemo/doc/guide>.
- CDFTOOLS — <https://github.com/meom-group/CDFTOOLS> — reference implementations of
  standard NEMO diagnostics (`cdfcurl`, `cdfdiv`, overturning `cdfmoc`, …); a great
  cross-check for the integrand, staggering, and sign of anything you build.
