# NEMO / ORCA — model-output factsheet

Reference for the agent working with native NEMO ocean-model output (ORCA family).
For the netCDF / chunking / lazy-reading mechanics that apply to any large file, see
the **model-outputs** factsheet.

## Triage every file first

Run `ncdump -h` (or check `ds.coords`):

- **1-D `longitude` / `latitude`** dimension coordinates → a regridded product;
  `.sel(longitude=…, latitude=…)` works and the C-grid rules below don't apply.
- **2-D `nav_lon` / `nav_lat` over `(y, x)`** → native NEMO/ORCA; apply the rules
  below.

## The C-grid

- NEMO output sits on a staggered **Arakawa C-grid**. Points: **T** at the cell
  centre (`thetao`, `so`, `zos`), **U** on the east/west face (`uo`), **V** on the
  north/south face (`vo`), **W** on the top/bottom face (vertical), **F** at the
  cell corner (vorticity).
- Fields are split by point type into **`grid_T` / `grid_U` / `grid_V` / `grid_W`**
  files, one set per output period.
- **Grid metrics and masks live in `mesh_mask.nc` / `domain_cfg.nc`**, not the
  field files: cell widths `e1{t,u,v,f}`, `e2{t,u,v,f}` and thicknesses
  `e3{t,u,v,w,f}` (all in **metres**), point coordinates `glam*` / `gphi*`, and
  masks `tmask` / `umask` / `vmask` / `fmask`. Most real analysis needs them.
- ORCA is **tripolar**: two mesh north poles over land remove the pole singularity,
  joined by a **north fold** across the top rows — those rows mirror/duplicate cells
  and vector components flip sign. Be wary of the northernmost rows.

## Two selection traps

- **`.sel(lon, lat)` fails on native ORCA.** `nav_lon` / `nav_lat` are 2-D
  curvilinear arrays over `(y, x)`, not axes. Select with **`.isel(x=…, y=…)`**, or
  use grid-aware tools (`cf-xarray`, `xgcm`, `xnemogcm`; `xESMF` to regrid).
- **The silent one — never do arithmetic mixing `grid_T` / `grid_U` / `grid_V` by
  index.** They share the same integer `(y, x)` dims but sit half a cell apart, so
  xarray combines them with **no error** and the result is quietly wrong (e.g.
  `speed = sqrt(uo**2 + vo**2)` pairs points that aren't co-located). Move fields to
  a common point first with `xgcm` / `xnemogcm`. Likewise an unweighted `.mean` over
  `(y, x)` is biased — weight by cell area `e1t*e2t` (and `e3t` for volumes) and
  apply `tmask`.

## Derived quantities on the C-grid (xgcm / xnemogcm)

Open the `grid_*` files together with the domain file and build an xgcm `Grid`:

```python
from xnemogcm import open_nemo_and_domain_cfg
import xgcm
ds = open_nemo_and_domain_cfg(nemo_files=[...], domcfg_files=["mesh_mask.nc"])
metrics = {("X",): ["e1t", "e1u", "e1v", "e1f"],   # zonal widths [m]
           ("Y",): ["e2t", "e2u", "e2v", "e2f"],   # meridional widths [m]
           ("Z",): ["e3t_0", "e3u_0", "e3v_0", "e3f_0", "e3w_0"]}  # thicknesses [m]
grid = xgcm.Grid(ds, metrics=metrics, periodic=False)
bd = {"boundary": "fill", "fill_value": 0.0}
```

**Relative vorticity / curl** ζ = ∂v/∂x − ∂u/∂y, evaluated at F-points:

```python
u = ds.uo.isel(z_c=0); v = ds.vo.isel(z_c=0)
zeta = (grid.diff(v * ds.e2v, "X", **bd) - grid.diff(u * ds.e1u, "Y", **bd)) \
       / (ds.e1f * ds.e2f) * ds.fmaskutil        # lives on (x_f, y_f)
```

**Meridional overturning streamfunction (z-coordinates)** ψ(y, z) in Sv —
meridional volume transport, summed zonally, integrated over depth from the sea
floor upward:

```python
vtrsp = ds.vo * ds.e1v * (ds.e3v_0 * ds.vmask)          # m^3/s per cell
Vz = vtrsp.sum("x_c")                                    # zonal integral -> (z_c, y_f)
psi = -Vz.isel(z_c=slice(None, None, -1)).cumsum("z_c").isel(z_c=slice(None, None, -1)) / 1e6
```

Sanity check: the Atlantic (AMOC) cell should come out **positive** (order +15 Sv
near 1000 m) — sign and integration direction are conventions, so verify it. Under a
non-linear free surface (z\*/vvl) use the **time-varying `e3v(t)`**, not `e3v_0`.
Dim names (`x_c`/`x_f`, `z_c`) are xnemogcm's; raw files use `x`, `y`, `deptht`,
`time_counter`. Field names are `uo` / `vo` / `thetao` / `so` in NEMO 4+ and CMEMS.

## Sources

- NEMO reference manual — [C-grid & scale factors](https://www.nemo-ocean.eu/doc/node19.html) ·
  [ORCA tripolar grid](https://www.nemo-ocean.eu/doc/node108.html)
- NEMO user guide — <https://sites.nemo-ocean.io/user-guide/>
- xgcm NEMO example — <https://xgcm.readthedocs.io/en/stable/xgcm-examples/04_nemo_idealized.html>
- xnemogcm — <https://xnemogcm.readthedocs.io/>
- MOC algorithm reference: CDFTOOLS `cdfmoc` — <https://github.com/meom-group/CDFTOOLS>
