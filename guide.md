# Getting Started — Setting Up This Project From Scratch

Follow it top to bottom on a fresh machine.

**A note on paths used throughout this guide:** wherever you see `<PROJECT_ROOT>`, that means "wherever you choose to keep this project on your own computer" — pick any folder, then use that same path consistently everywhere below. Wherever you see `/foss/designs/...` or `/foss/pdks/...`, that's a path *inside* the Docker container — it's fixed by the container's own setup and doesn't change no matter where `<PROJECT_ROOT>` lives on your machine, as long as the mount (Step 3) is set up correctly.

---

## 1. Install Docker Desktop

Docker runs all the chip-design tools (LibreLane, OpenROAD, Yosys, Magic, KLayout, netgen) inside an isolated container, so you don't need to install any of them individually.

1. Download Docker Desktop: https://www.docker.com/products/docker-desktop/
2. Install it like any normal app.
3. Open it once — wait for the whale icon (Mac menu bar / system tray) to settle to steady (not animating). This confirms Docker's background engine is running.
4. Confirm it's working:
   ```bash
   docker info
   ```
   If this prints real system info (not a connection error), you're ready to continue.

---

## 2. Choose Where This Project Lives, Then Clone It

Pick any folder on your machine to hold this project — call it `<PROJECT_ROOT>` for the rest of this guide.

```bash
mkdir -p <PROJECT_ROOT>
cd <PROJECT_ROOT>
git clone <repo_url>
```

**Why the exact folder matters:** the Docker container needs to be told which local folder to "see." Whatever folder you choose here, you must point Docker's mount at that same folder in Step 3 — the two have to match.

---

## 3. Get the Docker Container Running

The container image bundles LibreLane, OpenROAD, Yosys, Magic, KLayout and netgen along with the GF180MCU PDK. Build or pull that image using whichever method your team's repo documents (a `Dockerfile` to build locally, or a registry image to pull), then start the container with your chosen `<PROJECT_ROOT>` mounted in:

```bash
docker run -it --name <container_name> -v <PROJECT_ROOT>:/foss/designs <image_name> bash
```

- `-v <PROJECT_ROOT>:/foss/designs` — this is the mount: your local folder on the left, the fixed container-side path on the right. **This is the one piece you must customize** to match wherever you put the project in Step 2. Everything else in this guide (and the technical README) assumes files live under `/foss/designs/...` once inside the container — that part never changes.
- `<container_name>` — pick any name you like for the container (e.g. `chipflow`).
- `<image_name>` — the Docker image for this project's toolchain.

**For subsequent sessions** (once the container already exists), you don't need `docker run` again — just:
```bash
docker start <container_name>
docker exec -it <container_name> bash
```

Confirm the mount worked, from inside the container:
```bash
ls /foss/designs/
```
This should show the project folder(s) you cloned in Step 2.

**If Docker ever stops responding** (common after your disk fills up, or after a restart):
```bash
open -a Docker              # (Mac) relaunch Docker Desktop, wait ~30 seconds
docker start <container_name>
```

---

## 4. Explore the Project Layout

Once inside the container, the key folders are:

```
/foss/designs/<your_project>/
├── src/                    RTL source files (Verilog/SystemVerilog)
├── cocotb/                 Functional testbench
└── librelane/
    ├── config.yaml          Flow configuration — clock period, density, constraints, etc.
    ├── pdn_cfg.tcl           Power-grid generation script
    ├── A30_A.def             Organizer-provided floorplan template (pin positions)
    ├── gds/                  Any manually-edited GDS files
    └── runs/<run_tag>/       Output of each LibreLane run — one folder per run
        └── final/            Finished GDS, netlists, metrics for that run
```

---

## 5. Run Functional Verification First

Before touching physical design, confirm the RTL itself is correct. This step runs **on your host machine directly**, not inside Docker — cocotb doesn't need the container.

```bash
cd <PATH_TO_TESTBENCH_DIR>   # wherever the cocotb testbench + Makefile live in the cloned repo
make clean
make
```

**What `make` actually does here:** it invokes cocotb's simulation flow — compiling/elaborating the RTL with a Verilog simulator, then running each Python-based test in the testbench against it, reporting PASS/FAIL per test. `make clean` clears any previous build/simulation artifacts first, so you're always testing a fresh build.

All  tests should report PASS before you proceed.

---

## 6. Run the LibreLane Flow

Inside the container:
```bash
cd /foss/designs/<your_project>/librelane
source <PATH_TO_PDK_SETUP_SCRIPT>/sak-pdk-script.sh gf180mcuD gf180mcu_fd_sc_mcu7t5v0
librelane config.yaml --pdk gf180mcuD --pdk-root /foss/pdks --manual-pdk --run-tag <choose_a_run_name>
```

This will take a while (tens of minutes to a couple of hours, depending on your machine). It runs synthesis → floorplan → placement → CTS → routing → sign-off, automatically.

Once it finishes, your output is at:
```
/foss/designs/<your_project>/librelane/runs/<choose_a_run_name>/final/
```

**For the full technical breakdown of what happens in each stage, the config settings used, and how to verify the result (standalone DRC/LVS, etc.) — see the main project README (`README.md`), which covers the complete flow in detail.**

---

## 7. Common First-Time Issues

| Problem | Fix |
|---|---|
| `docker info` fails / "cannot connect" | Docker Desktop isn't fully started — open it, wait, retry. |
| Files you created aren't visible inside the container | Your files aren't under the folder you mounted in Step 3 (`-v <PROJECT_ROOT>:/foss/designs`) — move them there, or double-check the mount path matches. |
| Docker becomes totally unresponsive | Check your disk space — Docker can crash if the disk is nearly full. Free up space, then restart Docker Desktop and the container. |
| A `librelane` run fails partway through | Check the specific stage's log file inside `runs/<run_tag>/<stage_number>-<stage_name>/` for the actual error message. |
