# Agent-assisted ocean-data analysis — getting started

A short guide to setting up [Claude Code](https://docs.claude.com/en/docs/claude-code)
on a fresh macOS machine and using it to explore
[Copernicus Marine (CMEMS)](https://marine.copernicus.eu/) ocean data — first on
your laptop, later next to model output on the **nesh** HPC cluster.

It is written for someone comfortable in a shell and on remote machines, but new
(or returning after some years away) to the current Python data stack, Jupyter,
and agent-assisted coding. You don't need to re-learn that stack up front: the
agent writes and runs the code, and you pick up each concept at the point where
you actually need it. The guide follows that order:

1. [Install the tools](#1-install-the-tools) — Claude Code, `uv`, VS Code, and
   what each one is for.
2. [First analysis](#2-first-analysis-you-steer-the-agent-codes) — you prompt,
   the agent writes scripts and renders figures.
3. [Taking the wheel: notebooks](#3-taking-the-wheel-jupyter-notebooks) — when
   tuning by prompt gets slower than turning the knobs yourself.
4. [Moving to the data: nesh](#4-moving-to-the-data-the-nesh-hpc-cluster) — the
   same workflow, run next to the model output on the cluster.
5. [Notebooks on nesh](#5-notebooks-on-nesh) — the same move as step 3, plus
   one networking wrinkle.

---

## 1. Install the tools

Three installs on the laptop, each with a distinct role:

- **Claude Code** — the agent itself: a command-line program you talk to in
  plain language. It writes code, runs it, looks at the results, and asks for
  your approval along the way.
- **`uv`** — the Python package manager the agent uses to create environments
  and install libraries. You install it once; the agent drives it from there.
- **VS Code** — your window into what the agent produces: the scripts, the
  figures, and (later) the notebooks.

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

### 1c. Install uv

Install [`uv`](https://docs.astral.sh/uv/) once:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

Restart your terminal (or `source` your shell profile) so `uv` is on your
`PATH`, then verify:

```bash
uv --version
```

You won't create environments or install packages by hand — the agent runs
`uv init` and `uv add <package>` for you as the analysis grows. You just need
`uv` itself available.

### 1d. Install VS Code

Download and install Visual Studio Code from the official page:

<https://code.visualstudio.com/download>

You'll use it to look at the project as it grows — **File → Open Folder…** on
the project directory you create next.

---

## 2. First analysis: you steer, the agent codes

The working mode at this stage: you describe what you want in plain language;
the agent sets up the Python environment, writes a script, runs it, looks at
the figure it produced, and fixes what it sees. You steer it the same way you'd
steer a colleague — you never have to touch the Python yourself.

### Create the project

Create a dedicated working directory:

```bash
mkdir -p "$HOME/projects/cmems_claude_first_steps"
```

Then open that folder in VS Code (**File → Open Folder…**) so you can watch the
files appear as you go.

### Add the project guidelines

An example [`CLAUDE.md`](docs/CLAUDE.md) with working conventions for this kind
of project (Python via `uv`, plotting and analysis style, a figure-naming
scheme) lives alongside this guide. Claude Code loads a `CLAUDE.md` from the
project root automatically each session, so it will pick these up without you
having to repeat them.

Grab the contents of the example [`CLAUDE.md`](docs/CLAUDE.md) and save them as
a file named `CLAUDE.md` in your project directory, then read through it to see
what the agent will follow.

### Get CMEMS credentials

You need CMEMS credentials to access the data. Register (free) at
<https://marine.copernicus.eu/> and log in once with `copernicusmarine login` —
the agent can walk you through this when the first download needs it.

### Launch Claude Code and drive the analysis

Claude Code works best when launched from the root of the project it should
reason about, so start it from inside the project directory:

```bash
cd "$HOME/projects/cmems_claude_first_steps"
claude
```

Then ask for what you want in plain language. These are the actual prompts that
drove the example session:

- *"Create a plot of North Atlantic sea-surface temperature today from the
  Copernicus analysis/forecast product. Trim the color limits to the actual data
  range."*
- *"Now add a second plot with sea-surface salinity (SSS)."*
- *"Finally, create a T–S plot based on the same SSS and SST fields."*

The agent will propose commands and file edits and ask for your approval before
running them. Following the conventions in `CLAUDE.md`, it writes analysis
scripts into `scripts/` and figures into `figures/`, named so they are easy to
match up — browse both in VS Code as they appear. For a walk-through of what it
does with each prompt — from environment setup through the rendered figures —
see the annotated [example session](docs/example_session.md).

### Give the agent reference material: factsheets

The agent does better with a little grounded reference material on the services
and systems it works against. This repo ships short **factsheets** in
[`docs/factsheets/`](docs/factsheets/); copy the relevant ones into a
**`factsheets/`** directory in your project. The example `CLAUDE.md` already
tells the agent to read them, so it consults the relevant sheet on its own and
treats it as the source of truth for that area.

For this laptop stage you need one, maybe two:

- [`cmems.md`](docs/factsheets/cmems.md) — the Copernicus Marine toolbox
  (`copernicusmarine`): login, catalogue search, opening data lazily vs.
  downloading, and the ARCO geo-/time-series stores.
- [`model-outputs.md`](docs/factsheets/model-outputs.md) — worth adding once
  files get big: inspecting netCDF with CDL, on-disk chunking/compression and
  the read penalty, and staying lazy on larger-than-memory files.

The remaining sheets cover the HPC stage and appear in sections 4 and 5.

### A couple of tips

- **Run one project per directory.** Keep unrelated analyses in separate folders
  under `$HOME/projects/` so each has its own context.
- **Keep the `CLAUDE.md` up to date.** It's loaded automatically each session and
  is the best place to record conventions, data locations, and goals — edit it
  as the project grows.

---

## 3. Taking the wheel: Jupyter notebooks

After a while, steering by prompt hits a limit: asking the agent to nudge a
color limit, shift a date range, or try a different region is slower than doing
it yourself. That's the moment for a **Jupyter notebook** — the standard
interactive front end of the Python data world. A notebook is a document of
code cells with their figures and notes inline; you run cells one at a time,
tweak a value, re-run, and see the result immediately. It's the natural place
for *you* to iterate, while the agent keeps owning the heavier code work.

When you reach that point, just ask — e.g. *"turn the SST script into a
notebook I can run and tweak myself."* Behind the scenes the agent uses
[jupytext](https://jupytext.readthedocs.io/), so you get the best of both: it
keeps a plain `.py` file as the source it edits (clean, readable diffs) and
pairs it with a `.ipynb` notebook for you. You don't need to learn jupytext
yourself; the conventions in `CLAUDE.md` tell the agent how to keep the two in
sync. When you change something in the notebook that should stick, tell the
agent and it folds the change back into the `.py` source.

Open the notebook either directly in VS Code (it renders `.ipynb` files
natively) or in the browser with:

```bash
uv run jupyter lab
```

On the laptop that's all there is to it: the notebook server and your browser
run on the same machine. Keep that detail in mind — it's the one thing that
changes on the cluster (section 5).

---

## 4. Moving to the data: the nesh HPC cluster

When you outgrow the laptop and want to work against model output on
**nesh** (the CAU Kiel / GEOMAR cluster), the data lives *there* — so run the
agent there too, right next to it. Your shell and SSH experience carries over
directly; what's new is a handful of site facts: compute goes through the
**SLURM** scheduler rather than running on the login node, compute nodes reach
the internet only through a **proxy**, and large data belongs on the **`$WORK`**
filesystem. The flow, which you drive by hand:

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

   Put the project on **`$WORK`**, not `$HOME`: the model output and analysis I/O
   are large and belong on the TB-scale work filesystem (the small, backed-up
   `$HOME` would fill up), and the code is safe in git regardless. Working inside
   the allocation lets the agent open real files, read chunk shapes, and render
   fields as it iterates — the whole point of keeping it next to the data.
   (First time: create the project directory under `$WORK` and install `uv` as
   in the laptop steps above; the login node has direct internet for that.)

The session itself then works exactly as in section 2: same prompting, same
`CLAUDE.md` conventions, same `scripts/` and `figures/` layout — only now
against the real model output.

### Factsheets for this stage

Copy the sheets for this environment into the project's **`factsheets/`**
directory *on `$WORK`* — wherever the agent actually runs, not on your laptop:

- [`nesh.md`](docs/factsheets/nesh.md) — the nesh cluster: SLURM, partitions,
  the internet proxy, and the shared filesystems.
- [`nemo.md`](docs/factsheets/nemo.md) — NEMO/ORCA output: the staggered C-grid,
  `grid_T/U/V/W` files, curvilinear coordinates, and worked curl / overturning
  examples.
- [`model-outputs.md`](docs/factsheets/model-outputs.md) — inspecting netCDF
  with CDL, on-disk chunking/compression and the read penalty, and staying lazy
  on big files.
- [`remote-work.md`](docs/factsheets/remote-work.md) — reaching a compute-node
  JupyterLab from your laptop through an SSH/SOCKS tunnel (section 5).

Edit them to match your setup — some values (proxy address, partitions, quotas)
are site-specifics worth confirming on your account.

---

## 5. Notebooks on nesh

At some point on the cluster you'll want the same agency as in section 3: a
notebook you run and tweak yourself. The workflow is identical — ask the agent,
it sets up the jupytext-paired notebook, you run it in **JupyterLab** — with one
new complication: the notebook server now runs on the compute node, next to the
data and the agent, while your browser stays on the laptop.

Two facts stand between the browser and the server: you don't know which
compute node your job lands on until it starts, and that node is only reachable
*through* the login node — never directly from your laptop. The fix is an
**SSH/SOCKS tunnel** through the login node plus a browser that uses it. This
leg runs on your laptop, where no agent is around to help, so this repo ships
it as a ready-made script,
[`bin/remote_tunnel_chrome.sh`](bin/remote_tunnel_chrome.sh). Download it once:

```bash
curl -fsSL https://raw.githubusercontent.com/willirath/2026_claude_cmems/main/bin/remote_tunnel_chrome.sh -o remote_tunnel_chrome.sh
chmod +x remote_tunnel_chrome.sh
```

A notebook session then takes two steps:

1. **On nesh**, ask the agent to launch JupyterLab as a batch job and hand you
   the token URL from the job's output file — with `remote-work.md` in the
   project's `factsheets/` directory it knows the recipe. The URL looks like
   `http://nesh-clk399:8888/?token=…` and names the compute node the job
   landed on.

2. **In a second terminal on the laptop**, hand that URL to the tunnel script:

   ```bash
   ./remote_tunnel_chrome.sh <username>@nesh-login.rz.uni-kiel.de 'http://nesh-clk399:8888/?token=…'
   ```

   It opens the SOCKS tunnel through the login node and launches an isolated
   Chrome/Chromium routed through it, already pointed at the notebook.

The script runs on macOS, Linux, and Windows (there: in Git Bash) and finds
Chrome or Chromium on its own; set `BROWSER_BIN` if yours lives somewhere
unusual. When something doesn't connect, the
[`remote-work`](docs/factsheets/remote-work.md) factsheet explains the
mechanism and lists the usual causes.

Everything else — running cells, tweaking values, having the agent fold keeper
changes back into the `.py` source — works exactly as on the laptop.
