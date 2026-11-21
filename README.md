# EZR and RStudio runtime environment, standalone edition (R 4.6.1)

The repository for distributing, as a Zip, an environment for using [EZR](https://www.jichi.ac.jp/usr/hema/EZR/statmed.html) and RStudio in the browser (English edition). Nothing is installed on the user's computer: Python and QEMU in the Zip run a small Linux virtual machine, and Docker Engine inside it runs R, RStudio and EZR.

> This environment is an unofficial distribution and is not affiliated with the developer of EZR. It was not made, checked or endorsed by the EZR developer. Please send questions about this environment to the person who gave it to you, not to the EZR developer.

## How to use

Extract the Zip you received (`EZR_Standalone_en_r461_<version>.zip`) and open the guide in it. With photos, it explains everything from starting, through opening EZR and analysing, to finishing.

| Computer | Guide |
|---|---|
| Mac | `HOW_TO_USE_Mac.html` |
| Windows | `HOW_TO_USE_Windows.html` |

## What you can do

- Open EZR with clicks only.
- Create a "project" for each study, and keep its data (CSV, Excel) and records apart from the others.
- The records of what you do in EZR (R script, R Markdown, output, graphs) are kept automatically, and when you close EZR, a report with the figures (`markdown.html`) is made. The fingerprints (SHA-256) of the data used and the versions of R and the packages are kept too.

## How it works

EZR (the R package RcmdrPlugin.EZR) is opened in a Docker container inside a Linux virtual machine, in a plain R separate from RStudio, as in the official instructions. The EZR screen is drawn on a virtual display inside the container, and appears in a separate browser tab through the RStudio Server proxy.

```
Browser ─ http://localhost:<port> (RStudio Server)
launcher/standalone.py (Python in the Zip)
  └─ QEMU
      Linux (runtime/linux/engine-<arm64|amd64>.qcow2 + .state/disk.qcow2) ─ Docker Engine
        /mnt/project = app/ (shared over SMB; written directly to the folder on the computer)
        Container (/app = app/)
          ├─ RStudio's R ─ the "Open EZR" window → ezr_open()
          ├─ Xvnc :1 + fluxbox ─ the EZR R (a plain R) ─ R Commander + EZR
          ├─ websockify :6080 (noVNC) ─ to the browser through the RStudio proxy /p/<key>/
          └─ projects/<name>/ ─ data/, outputs/<YYYYMMDDHHMM>_<4 digits>/
```

On the first start, the EZR image is built inside the virtual machine (this needs the internet). From the second start on, the built image is used, and it is rebuilt only when what the environment is made from (`Dockerfile`, `DESCRIPTION`, `renv.lock`, `R/` and so on in `app/`) has changed. After building, it checks that `renv.lock` matches `DESCRIPTION` and rebuilds it if not.

## Projects and records

A project is `app/projects/<name>/`; data chosen in the window is copied to `data/` (CSV or Excel, up to 15 MiB each; never overwritten). Each time EZR opens, one record folder `outputs/<YYYYMMDDHHMM>_<4 digits>/` is made. "Records folder" in the window opens `app/projects`.

| File | What |
|---|---|
| `script.R`, `markdown.Rmd`, `output.txt` | Copies of EZR's panes (written whenever they change) |
| `plots/` | Graphs as PNG |
| `console.log` | Output of the EZR R |
| `meta.json` | Environment, SHA-256 of the data, random state, hashes of the records |
| `markdown.html` | The report made when EZR closes (`markdown.log` if it cannot be made) |

"Stop" waits until the record hashes and the report are ready. For a session cut off before "Stop" (the computer turned off, or "Stop without waiting"), what was written stays, but the hashes are not finalized and the report is not made again.

## Distribution

| Item | What |
|---|---|
| Making it | `ezr_dist/tools/standalone/make_zip.py bundle r461 en` (outside Git) makes the Zip from the committed HEAD (the tools: `ezr_dist/tools/README.md`) |
| In it | The same shape as this repository (at the top: the launcher files, `launcher/`, the guides, `README.md`, `CITATION.cff`, `LICENSE`, `LICENSE-docs`; in `app/`: the analysis folder), plus `runtime/` (Python, QEMU, the Linux bases and the list of SHA-256 of the files), `Start EZR.app`, `THIRD_PARTY.md` (with the licence texts in `runtime/licenses/`) and `app/TEMPLATE_VERSION.txt` |
| Not in it | `tests/test_standalone.py`, `launcher/MacLauncher.swift`, the development settings (`.github/`, `.githooks/`, `.devcontainer/`, `.vscode/`, `.editorconfig`, the top `.gitignore`, `app/tools/precommit_checks.R`) |
| Handing it over | Download or USB |

## Startup records

| Record | What |
|---|---|
| `.state/console.log` | Output of Linux in the virtual machine |
| `.state/image.json` | The built image and the commit it was made from |
| `.state/session.json` | The RStudio address, the time preparation took and the memory of the virtual machine |
| `.state/engine.sha256` | The SHA-256 of the base of the virtual machine's disk (`runtime/linux/engine-<arm64|amd64>.qcow2`); the disk is made again when the base changes |

## Running from the repository

The repository has the same shape as the Zip: the launcher files, `launcher/`, the guides, `README.md` and `CITATION.cff` at the top, and the analysis folder in `app/`. `runtime/`, `Start EZR.app` and `THIRD_PARTY.md` are not in Git; `ezr_dist/tools/standalone/make_zip.py local r461 en` (outside Git) puts them in place. `runtime/` is a link to `ezr_dist/tools/standalone/runtime/`, shared by the four repositories. After that, start from the launcher file as with the Zip. To try only the container part, use Docker on the computer in `app/`: `docker build --target dev -t ezr-standalone-r461en:dev .` and `docker compose up -d dev` (maintainer commands: `make help` in `app/`).

## Tests

`make test` in `app/` (also in `check` and `verify`) runs all of `app/tests/testthat`. In `test-project_ezr.R`, 13 tests check the launcher files at the top (`start_*`, `launcher/`); they are skipped inside the container, where those files are not visible, and run with R on the computer. The standalone start flow is tested by `make ezr-test-launcher` (`tests/test_standalone.py` at the top; no virtual machine is started).

## Code notes

Comments are only in `app/R/project_ezr.R`, `launcher/standalone.py` and their tests (`app/tests/testthat/test-project_ezr.R`, `tests/test_standalone.py`), one line per function and per test.

| File | Role |
|---|---|
| `start_mac.command`, `start_windows.bat` | The launcher files. They show the window, and run `launcher/standalone.py` when the window calls them |
| `launcher/standalone.py` | Starts and stops the virtual machine, the share and the container. Checks the SHA-256 of `runtime/` at every start |
| `launcher/MacLauncher.swift` | The source of the Mac window (`Start EZR.app`), made into the app when the Zip is made |
| `launcher/windows_gui.ps1` | The Windows window |
| `launcher/start_messages.txt` | The list of launcher and window texts |
| `app/ezr_start.R` | Shows the "Open EZR" window |
| `app/R/project_ezr.R` | The functions that open EZR and keep the records |
| The template's extension points in `app/` (`docker/project_*`, `project.mk`, the end of `.Rprofile` and so on) | The packages, settings and commands EZR needs |
| `app/tests/testthat/test-project_ezr.R` | Tests of `app/R/project_ezr.R` |
| `tests/test_standalone.py` | Tests of the standalone start flow |

## License and citation

- The code is under [MIT](https://opensource.org/license/mit) (`LICENSE`).
- The guides for users (`HOW_TO_USE_*.html` and the photos in them) are under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/deed.en) (`LICENSE-docs`). The rights to the software screens shown in the photos remain with their respective owners.
- `runtime/` in the Zip contains Python, QEMU, Linux (Alpine) and Docker Engine. They follow the terms of their own authors. The version and licence of each part are in `THIRD_PARTY.md` in the Zip, and the licence texts in `runtime/licenses/`. The person who distributes this environment keeps the sources of the GPL, LGPL, MPL and similar parts and hands them over on request. What is downloaded on the first start (R, the R packages including EZR, RStudio Server and so on) is not included in what is distributed.
- To cite this environment, use the information in `CITATION.cff`. The contact for the author is also in `CITATION.cff`.

## Use of AI

The code and documentation were written with AI coding assistants as tools. The standalone launcher was first made with OpenAI's Codex, and was then reworked with [Claude Opus 5.5](https://www.anthropic.com/claude/opus) by Anthropic (used through [Claude Code](https://code.claude.com/docs/en/overview)).

## If something goes wrong

| If this happens | Do this |
|---|---|
| The EZR tab does not open and RStudio shows "Popup Blocked" | The browser blocked the new tab. Press "Try Again" in the window, and the EZR tab opens. |
| It stays at preparing for a long time | The first start builds the image and takes time. Keep the "EZR Standalone" window open and wait. |
| It says "Could not build the EZR environment" | Check that you are connected to the internet and that you have free disk space, then press "Start" (on a network that needs a proxy, the computer's proxy setting is used; it may not be built on a network that inspects the contents of the traffic). |
| RStudio does not open in the browser | Press "Open browser" in the "EZR Standalone" window. If it still does not open, press "Copy address", then right-click the address bar of your browser and choose "Paste and go" ("Paste and Go" in Safari). |
| The RStudio or EZR tab stopped loading | Press reload in that tab. |
| The EZR screen froze, or a window cannot be found | Open `ezr_start.R` from RStudio's Files, press "Source" and choose the same project. If that does not fix it, stop with "Stop", then start again with "Start" (the records are kept). |
| After you chose another project, the bottom left of RStudio (Console) says in red that the previous EZR cannot be closed | The previous EZR has a window open, such as a file chooser, or is in the middle of a computation. Close that window in the EZR tab (or wait for the computation to end), and the previous EZR closes; then choose again (the records are kept). |
| The "Open EZR" window says in red "The report of the previous session (markdown.html) is being made. …" | Wait a little until the report of the previous session is made, then press "Open EZR" again. |
| After you chose another project, the bottom left of RStudio (Console) says "The report of the previous session is being made. "…" opens when it is done…", and it does not open at once | It opens by itself when the report of the previous session is made. Just wait. |
| You tried to close the "EZR Standalone" window during preparation or stopping, and it says "Please wait for preparation or stopping to finish" | Press "Back" on a Mac, or "OK" on Windows, and wait until it finishes. |
| "Stop" does not stop it | Close EZR with ×, wait a little and press "Stop" again. |
| It says "Stopping failed." | Check what the box at the bottom of the "EZR Standalone" window shows, then press "Stop" again. |
| You pressed "Restart R Commander" in EZR's "Tools" → "Options..." | Press OK for "Exit?", and "No" for "Save script file?" and similar questions. When EZR opens again with the new settings, choose the data again with the "Data set:" button (the data and the records go on). |
| On a Mac, `start_mac.command` was blocked the first time you opened it | Open it with method A or B in the guide. If a warning still appears from the second time on, tell the person who gave you this environment exactly what it said. |
| On a Mac, it says "This app cannot start on its own." | Start from `start_mac.command`, not from `Start EZR.app`. It also appears if only the app was copied somewhere else. |
| On Windows, it says "Windows protected your PC" | Press "More info", then press the "Run anyway" button that appears. |
| On Windows, it says "This folder is already running." | Go back to the open "EZR Standalone" window (it is on the taskbar). |
| The RStudio tab shows "R Session Disconnected" | RStudio connects to only one browser tab. Opening RStudio in another tab turns the earlier tab into this. Close this tab. If the "Open EZR" window does not appear, press "Source" for `ezr_start.R`. If the Console does not respond, first press the red stop button at the top right of the Console. |
| RStudio shows "R is taking longer to start than usual" and does not go on | Press "Reload". |
| After reloading the RStudio page, or closing its tab and opening it again, while the "Open EZR" window was shown, the window does not appear and the Console does not respond | Press the red stop button at the top right of the Console, then press "Source" for `ezr_start.R`. The window appears again. |
| The browser offers to translate the page | Do not translate it; close the offer with ×. |
| On a narrow screen, RStudio's "Source" or [Render] label is not shown | The button is shown as an arrow icon only. Press the arrow icon, not the checkbox next to it ("Source on Save" or "Render on Save"). |
| You want to change the packages (dependencies) | Leave the current `EZR_Standalone_en_r461` folder as it is; extract the Zip you received again to make a new `EZR_Standalone_en_r461` folder, and make the change there. When it starts, the environment is rebuilt to match the change. The analyses in the current folder can go on with the same packages as before. |
| It says "Launch or stop failed (exit code …)" | If the box at the bottom says what to do (such as "Press Start again"), do that. If it does not, or that does not help, tell the person who gave you this environment exactly what the box at the bottom of the "EZR Standalone" window shows. |
