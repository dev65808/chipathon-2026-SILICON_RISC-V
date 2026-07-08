# Chipathon 2026 Team A30 SILICON_RISC-V 

- **Project Title**: 32-bit RISC-V (RV32I) microcontroller using TL-Verilog and Librelane-ORFS Flow
- **Project Description**:The project aims to design and implement a basic 32-bit RISC-V processor compliant with the RV32I base instruction set. TL-Verilog (TLV) will be the main design language, enabling transaction-level modeling and timing abstraction for faster development and better architectural insight. TLV descriptions will be translated into SystemVerilog using Sandpiper. A simple APB bus will connect to external serial memory and integrate an on-chip ADC and DAC, forming a minimal microcontroller platform.


# chipathon-2026-gf180mcu-padring

Chipathon 2026 workshop fork of the wafer-space `gf180mcu-project-template`.
Adds a new LibreLane slot, `workshop`, that mirrors Juan Moya's
standalone workshop padring as a native LibreLane slot definition so
participants can take the flow all the way to GDS with the stock
template Makefile.

No PRs are planned against upstream; all chipathon-specific material
stays in this fork.

## Credits

This repository is a **derivation**. The template, Nix flake, and
LibreLane flow are the work of Leo Moser and the wafer-space
contributors; the workshop pad layout is a port of Juan Moya's
`padring_gf180`. Both are Apache-2.0.

- Upstream template — https://github.com/wafer-space/gf180mcu-project-template
  pinned at commit `8bd0f6ff28947bf222c5288343f8f3ee1fc04632`
  (`chore: update flake to librelane 3.0`, 2026-03-26).
- Workshop pad layout — https://github.com/JuanMoya/padring_gf180
  (`Workshop_CASS/padring/workshop_padring.cfg`).

See `CREDITS.md` for the per-artifact attribution and `NOTICE` for
the formal Apache-2.0 notice.

## What this fork changes vs upstream

Exactly 6 files (one commit on top of pinned upstream):

| File | Change |
|------|--------|
| `src/slot_defines.svh` | add `SLOT_WORKSHOP` block (NUM_INPUT=1, BIDIR=20, ANALOG=60, 4/4 DVDD/DVSS) |
| `src/chip_core.sv` | replace example counter with a 20-bit counter driving the 20 bidir pads; analog pads float through |
| `librelane/slots/slot_workshop.yaml` | **new** slot (DIE 2935x2935 um, CORE 2051x2051 um, VERILOG_DEFINES=SLOT_WORKSHOP) |
| `librelane/config.yaml` | drop SRAM `MACROS` entry and PDN macro connections - not used in this slot |
| `librelane/pdn_cfg.tcl` | drop SRAM-specific `define_pdn_grid` blocks |
| `Makefile` | `AVAILABLE_SLOTS += workshop` |

`git log upstream/main..main` shows the single derivation commit;
`git diff upstream/main..main` shows the delta.

## Workshop slot - pad map at a glance

- Die: **2935 x 2935 um** (same as Juan Moya's reference).
- **60 x analog** (`gf180mcu_fd_io__asig_5p0`)
- **20 x bidir** (`gf180mcu_fd_io__bi_24t`)
- **4 x DVDD** + **4 x DVSS** (`gf180mcu_ws_io__dvdd` / `__dvss`)
- **clk_pad** (`gf180mcu_fd_io__in_s`), **rst_n_pad** (`gf180mcu_fd_io__in_c`)
- **1 x input_pad** - Yosys zero-width-vector workaround; chipathon
  participants can ignore it (documented in `docs/workshop-slot-spec.md`).
- **4 x corner** (`gf180mcu_fd_io__cor`, inserted by LibreLane).

Pad ordering in `PAD_NORTH` and `PAD_WEST` is **reversed** relative to
Juan Moya's standalone `workshop_padring.cfg` because LibreLane reads
pad lists clockwise from the SW corner. Full pad-by-pad mapping in
`docs/workshop-slot-spec.md`.

## Quickstart

### Build the workshop slot (native, nix-shell)

```bash
git clone <this-repo-url> chipathon-2026-gf180mcu-padring
cd chipathon-2026-gf180mcu-padring
nix-shell               # provides LibreLane 3.0.0
make clone-pdk          # clones wafer-space/gf180mcu @ 1.8.0
SLOT=workshop make librelane
```

Runtime on a modern laptop: **~2h 15m** for the full signoff run
(Magic DRC + KLayout DRC + LVS + antenna + STA across 3 corners).

Final artifacts land in `final/`:
- `final/gds/chip_top.gds` (~85 MB)
- `final/metrics.csv` (signoff metrics)
- `final/*.log` (per-stage logs)

### Inspect a built GDS (Docker, hpretl/iic-osic-tools)

`scripts/run_docker_iic.sh` spawns the iic-osic-tools container with
this repo mounted; inside the container run `klayout final/gds/chip_top.gds`
or `magic -T .../gf180mcuD.magicrc ...`.

See `docs/reproducing-native.md` and `docs/reproducing-docker.md` for
the detailed walkthroughs.

### Use the workshop slot for your own RTL

Swap `src/chip_core.sv` with your design, keeping the port list
(NUM_INPUT=1, NUM_BIDIR=20, NUM_ANALOG=60, clk, rst_n), and re-run
`SLOT=workshop make librelane`. Padring stays fixed.

## Verification

The repository was validated **end-to-end** against a known-good
reference build. To re-run the pragmatic check (byte-compare the
six tracked files against the reference tree):

```bash
scripts/verify_workshop_slot.sh /path/to/reference/template
```

The reference build (DRC/LVS/antenna/STA signoff on 2026-04-23 with
LibreLane 3.0 + wafer-space PDK 1.8.0) is the source of truth for
"clean". As long as the fork's six files byte-match that reference,
a fresh build on a compatible host will reproduce the same result.

If you do not have the reference tree, the repo itself is the ground
truth - this fork *is* those six files.

## Repository layout

```
.
|-- README.md                       # this file
|-- NOTICE                          # Apache-2.0 attribution
|-- CREDITS.md                      # detailed credits
|-- AUTHORS.md                      # copyright holders (upstream + fork)
|-- LICENSE                         # Apache-2.0
|-- docs/
|   |-- workshop-slot-spec.md       # full pad-by-pad mapping
|   |-- reproducing-native.md       # nix-shell walkthrough
|   `-- reproducing-docker.md       # iic-osic-tools walkthrough
|-- examples/
|   `-- rtl2gds_chipathon_padring.ipynb   # standalone notebook
|-- scripts/
|   |-- run_docker_iic.sh           # iic-osic-tools launcher
|   `-- verify_workshop_slot.sh     # pragmatic end-to-end check
|-- librelane/
|   |-- config.yaml                 # top-level LibreLane config (patched)
|   |-- pdn_cfg.tcl                 # PDN generator (patched)
|   |-- chip_top.sdc                # upstream, unchanged
|   `-- slots/
|       |-- slot_0p5x0p5.yaml       # upstream, unchanged
|       |-- slot_0p5x1.yaml         # upstream, unchanged
|       |-- slot_1x0p5.yaml         # upstream, unchanged
|       |-- slot_1x1.yaml           # upstream, unchanged
|       `-- slot_workshop.yaml      # new (this fork)
|-- src/
|   |-- chip_top.sv                 # upstream, unchanged
|   |-- chip_core.sv                # patched (counter->bidir)
|   `-- slot_defines.svh            # patched (SLOT_WORKSHOP)
|-- Makefile                        # patched (AVAILABLE_SLOTS += workshop)
`-- (upstream infra: flake.nix, gf180mcu/, ip/, cocotb/, scripts/, ...)
```

## License

Apache-2.0, inherited from upstream. See `LICENSE` for the full text,
`NOTICE` for attribution of third-party material, and `AUTHORS.md`
for the list of copyright holders.
