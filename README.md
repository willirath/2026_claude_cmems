# Agent-assisted ocean-data analysis — getting started

A short guide to install the [Claude Code](https://docs.claude.com/en/docs/claude-code)
CLI on a fresh macOS machine and set up a first project for exploring
[Copernicus Marine (CMEMS)](https://marine.copernicus.eu/) ocean data with agent
assistance.

---

## 1. Install Claude Code on a fresh macOS

You need a terminal (the built-in **Terminal.app** is fine) and an Anthropic
account with Claude Code access (Claude Pro/Max subscription or an API account).

### 1a. Install the claude command-line interface

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Then restart your terminal so the `claude` command is on your `PATH`. Verify the
install:

```bash
claude --version
claude doctor      # checks your setup and reports any problems
```

### 1b. First launch & authentication

Start Claude Code from any directory and follow the login prompt:

```bash
claude
```

On first run it opens a browser to authenticate. Choose the option that matches
your account (Claude subscription or Anthropic API/Console). After login you drop
into an interactive session — type `/help` to see commands, and `/exit` to quit.

Keep it updated over time with:

```bash
claude update
```

### 1c. Install uv (Python package manager)

[`uv`](https://docs.astral.sh/uv/) is a simple package manager for python environments and dependencies.
Install it once:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart your terminal (or `source` your shell profile) so `uv` is on your
`PATH`, then verify:

```bash
uv --version
```

You don't need to create environments or install packages by hand — the agent
runs `uv init` and `uv add <package>` for you as the analysis grows (see the
example session below). You just need `uv` itself available.

---

## 2. Install VS Code

Download and install Visual Studio Code from the official page:

<https://code.visualstudio.com/download>

Open the downloaded app, then use **File → Open Folder…** and navigate to your
project directory (see below) to start working there.

---

## 3. Set up your first CMEMS project

First create a dedicated working directory for the project:

```bash
mkdir -p "$HOME/projects/cmems_claude_first_steps"
```

Then open that folder in VS Code (**File → Open Folder…**) so you can view and
edit its files as you go.

### Add the project guidelines

An example [`CLAUDE.md`](docs/CLAUDE.md) with working conventions for this kind of
project (Python via `uv`, plotting and analysis style, a figure-naming scheme)
lives alongside this guide. Claude Code loads a `CLAUDE.md` from the project
root automatically each session, so it will pick these up without you having to
repeat them.

Grab the contents of the example [`CLAUDE.md`](docs/CLAUDE.md) and save them as a
file named `CLAUDE.md` in your project directory, then read through it to see
what the agent will follow.

### Launch Claude Code

Claude Code works best when launched from the root of the project it should
reason about, so start it from inside the project directory:

```bash
cd "$HOME/projects/cmems_claude_first_steps"
claude
```

### Suggested first steps inside the session

Once Claude Code is running, drive the analysis by asking it in plain language.
These are the actual prompts that drove the example session:

- *"Create a plot of North Atlantic sea-surface temperature today from the
  Copernicus analysis/forecast product. Trim the color limits to the actual data
  range."*
- *"Now add a second plot with sea-surface salinity (SSS)."*
- *"Finally, create a T–S plot based on the same SSS and SST fields."*

The agent will propose commands and file edits and ask for your approval before
running them. For a walk-through of what it does with each prompt — from
environment setup through the rendered figures — see the annotated
[example session](docs/example_session.md).

### Turning scripts into notebooks (jupytext)

Start with the flat scripts above. When you want to work in a real Jupyter
notebook, just ask — the agent uses [jupytext](https://jupytext.readthedocs.io/)
so you get the best of both: it keeps a plain `.py` file as the source it edits
(clean, readable diffs) and pairs it with a `.ipynb` you open and run in Jupyter
or VS Code. You don't need to learn jupytext yourself; the conventions in
`CLAUDE.md` tell the agent how to keep the two in sync.

### Add domain & system factsheets

As the analysis moves past the basics — native **NEMO** model output, the **nesh**
HPC cluster, larger-than-memory files — the agent does better with a little grounded
reference material on hand. This repo ships short **factsheets** in
[`docs/factsheets/`](docs/factsheets/):

- [`cmems.md`](docs/factsheets/cmems.md) — the Copernicus Marine toolbox
  (`copernicusmarine`): login, catalogue search, opening data lazily vs.
  downloading, and the ARCO geo-/time-series stores.
- [`model-outputs.md`](docs/factsheets/model-outputs.md) — inspecting netCDF with
  CDL, on-disk chunking/compression and the read penalty, and staying lazy on big
  files.
- [`nemo.md`](docs/factsheets/nemo.md) — NEMO/ORCA output: the staggered C-grid,
  `grid_T/U/V/W` files, curvilinear coordinates, and worked curl / overturning
  examples.
- [`nesh.md`](docs/factsheets/nesh.md) — the nesh cluster: SLURM, partitions, the
  internet proxy, and the shared filesystems.
- [`remote-work.md`](docs/factsheets/remote-work.md) — reaching a compute-node
  JupyterLab from your laptop through an SSH/SOCKS tunnel.

Copy the sheets you need into a **`factsheets/`** directory in your project —
wherever the agent actually runs. If you run Claude on nesh in a project directory,
that `factsheets/` directory goes there, next to the agent, not on your laptop. The
example `CLAUDE.md` already tells the agent to read them, so it consults the
relevant sheet on its own and treats it as the source of truth for that area. Edit
them to match your setup — some values (proxy address, partitions, quotas) are
site-specifics worth confirming on your account.

### A couple of tips

- **Run one project per directory.** Keep unrelated analyses in separate folders
  under `$HOME/projects/` so each has its own context.
- **Keep the `CLAUDE.md` up to date.** It's loaded automatically each session and
  is the best place to record conventions, data locations, and goals — edit it
  as the project grows.
- **You need CMEMS credentials** to download data. Register (free) at
  <https://marine.copernicus.eu/> and log in once with
  `copernicusmarine login` — the agent can walk you through this.

---

## 4. Moving to the nesh HPC cluster

When you outgrow the laptop and want to work against model output on
**nesh** (the CAU Kiel / GEOMAR cluster), the data lives *there* — so run the agent
there too, right next to it. The flow, which you drive by hand:

1. **SSH to a login node** (off-campus, connect the CAU or GEOMAR VPN first; a
   `~/.ssh/config` alias can shorten this to `ssh nesh`):

   ```bash
   ssh <username>@nesh-login.rz.uni-kiel.de
   ```

2. **Grab an interactive allocation** on the general-purpose `base` partition —
   compute belongs in a scheduler job, never on the login node:

   ```bash
   srun --pty --time=04:00:00 --mem=16G --cpus-per-task=4 --partition=base /bin/bash
   ```

3. **Set the proxy** so downloads *and Claude's own API traffic* can reach the
   internet from the compute node (this is the usual reason a job "can't connect"):

   ```bash
   export http_proxy=http://10.0.7.235:3128
   export https_proxy=http://10.0.7.235:3128
   ```

4. **Launch Claude in your project on `$WORK` and drive everything from there:**

   ```bash
   cd "$WORK/projects/nemo_cmems_analysis" && claude
   ```

   Put the project on **`$WORK`**, not `$HOME`: the model output and analysis I/O are
   large and belong on the TB-scale work filesystem (the small, backed-up `$HOME`
   would fill up), and the code is safe in git regardless. Working inside the
   allocation lets the agent open real files, read chunk shapes, and render fields as
   it iterates — the whole point of keeping it next to the data. (First time: create
   the project directory under `$WORK` and install `uv` as in the laptop steps above;
   the login node has direct internet for that.)

For a **JupyterLab** notebook, run it on the compute node and reach it from your
laptop browser through an **SSH tunnel**: you don't know which compute node your job
lands on until it starts, and it's only reachable *through* the login node, so the
tunnel lets an isolated browser reach the node's internal address. The
[`remote-work`](docs/factsheets/remote-work.md) factsheet has the full recipe.

Copy the factsheets relevant to this stage into your project's `factsheets/`
directory (see above) so the agent has the cluster, scheduler, filesystem, and
model-output specifics on hand. Some values (proxy address, partitions, quotas) are
site-specifics worth confirming on your account.
