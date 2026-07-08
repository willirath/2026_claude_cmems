# Example session — CMEMS North Atlantic surface analysis

A condensed transcript of a short agent-coding session, meant as a suggestion
for what a simple analysis session with Claude Code can look like. User prompts
are quoted; the agent's actions follow in shorthand. (Project conventions such
as "use cmocean colormaps where they fit" live in `CLAUDE.md`, so the agent
applies them without being asked.)

---

**User:** "Create a plot of North Atlantic sea-surface temperature today from the
Copernicus analysis/forecast product. Trim the color limits to the actual data range."

> **AGENT:**
> - set up the python environment for the project: `uv init` + `uv add copernicusmarine
  xarray matplotlib cartopy cmocean netcdf4`
> - created script `scripts/sst_north_atlantic.py`
> - executed it → `figures/sst_north_atlantic_map.png`

---

**User:** "Now add a second plot with sea-surface salinity (SSS)."

> **AGENT:**
> - created script `scripts/sss_north_atlantic.py`
> - executed it → `figures/sss_north_atlantic_map.png`

---

**User:** "Finally, create a T–S plot based on the same SSS and SST fields."

> **AGENT:**
> - created script `scripts/ts_north_atlantic.py`
> - executed it → `figures/ts_north_atlantic_diagram.png`

---

### Result

```
scripts/                          figures/
  sst_north_atlantic.py    →        sst_north_atlantic_map.png
  sss_north_atlantic.py    →        sss_north_atlantic_map.png
  ts_north_atlantic.py     →        ts_north_atlantic_diagram.png
```

### Takeaways for a new user

- Let the agent handle setup (`uv`, deps, dataset ids).
- Indicate the data source in human language and let the agent figure out the details.
- The agent renders each figure and reacts to what it sees (clims, outliers) —
  steer it the same way you'd steer a colleague.
