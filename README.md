# Chipathon 2026 Team A30 SILICON_RISC-V 

- **TITLE**: 32-bit RISC-V (RV32I) microcontroller using TL-Verilog and Librelane-ORFS Flow
- **DESCRIPTION**:The project aims to design and implement a basic **32-bit RISC-V processor** compliant with the RV32I base instruction set. Two prime objective of this project:
  - **TL-Verilog (TLV)** from [Redwood EDA](https://redwoodeda.com) will be used to develop the RISC-V core. TLV's transaction-level modeling and timing abstraction will enable for faster development and better architectural insight. The [MakeChip IDE](https://makerchip.com) overs interactive documentation and a very powerful visualization code that makes design and verification of the designs like RISC-V processor very efficient. We believe this is the first time TLV is used Chipathon. A design methodology involving TLV will be good value addition to the open-source ecosystem.
  - **QSPI Flash and RAM as Reusable IP**: When designing small RISC-V cores, adding SRAM for instruction and data is usually not practical. Instead, accessing an extrnal FLASH and RAM through a QSPI protocol is a great choice is speed is not an issue. Although there are few RISCV in the open-source community, they are embedded in designs which makes it diffcult for designers to drop it in their design as an _reusable IP_. The aim of this project is to create such an resuable IP.
  - **UART and SPI as Reusable IP**: UART and SPI allows a RISCV core to interact with external world and create a tiny microcontroller-type device. The UART can be used to interact with a terminla and SPI display can be used as the monitor.


---
# qspi_chip_top — Full Design, Verification & Tapeout Flow

RV32I core + QSPI + UART chip, targeting the GF180MCU process (Chipathon 2026, Team A30). This document covers the full path from RTL source through functional verification, physical implementation, and sign-off — written so someone unfamiliar with this project can reproduce every step.

**A note on paths used throughout this document:** `<PROJECT_ROOT>` means wherever you keep this project's `librelane/` folder (on your own machine, or inside the container — see `GETTING_STARTED.md` for the full mount setup). Paths starting with `/foss/` are fixed, container-internal paths that don't change regardless of where `<PROJECT_ROOT>` lives on your host machine.

---

## 1. Source Files (`src/`)

| File | Role |
|---|---|
| `qspi_chip_top.sv` | Top-level chip module — instantiates the core and peripherals, connects them to the physical I/O pads (the `_IN`/`_OUT`/`_OE`/`_PU`/`_PD`/`_SL`/`_CS`/`_IE` pad-cell ports). Contains the `_unused` tie-off for 8 input-side signals on output-only pads, and the `cyc_cnt_unused` simulation-only cycle counter. |
| `top_gen.sv` | Generated top-level wiring, produced from `top.tlv` (TL-Verilog source) via the Makerchip/sandpiper toolchain. |
| `top.tlv` | TL-Verilog source for the generated core wiring — the human-edited source that `top_gen.sv` is compiled from. |
| `rv32i_core.sv` | The RV32I RISC-V processor core. |
| `rv32i_qspi_mem.v` | Memory-mapped interface connecting the core to QSPI flash/RAM access. |
| `spi_riscv_if.v` | Bridge between the RISC-V core's bus and the SPI controller. |
| `uart_riscv_if.v` | Bridge between the RISC-V core's bus and the UART controller. |
| `qspi_ctrl.v` | QSPI protocol controller. |
| `spi_ctrl.v` | Plain SPI protocol controller. |
| `uart_tx.v` / `uart_rx.v` | UART transmit and receive shift-register logic. |
| `latch_reg.v` | Latch-based register used in one of the peripheral/interface paths. |
| `pseudo_rand_stub.sv` | Pseudo-random stimulus/stub module, used in verification. |

Standard cell library used for all synthesis/place-and-route: `gf180mcu_fd_sc_mcu7t5v0`.

---

## 2. Functional Verification (cocotb Testbench)

Run **before** any physical design work, and again after any RTL change (this runs on your host machine, not inside Docker):

```bash
cd <PATH_TO_TESTBENCH_DIR>
make clean
make
```

Testbench driver: `cocotb/chip_top_tb.py`

Must PASS all required tests:

- `test_top`
- `test_top_full`
- `test_top_qspi_uart`
- `test_top_qspi_uart_spi`
- `test_top_uart_echo`
- `test_top_uart_rw`
- `test_top_spi_rw`

Only proceed to physical implementation once every test passes.

---

## 3. Environment for Physical Design

All physical-design tools (LibreLane, OpenROAD, Yosys, Magic, KLayout, netgen) run inside a Docker container. See `GETTING_STARTED.md` for full setup instructions (image/container creation, mounting your project folder).

```bash
docker start <container_name>
docker exec -it <container_name> bash
```

- Mount: your chosen `<PROJECT_ROOT>` on the host ↔ `/foss/designs/` inside the container
- PDK: `gf180mcuD`
- Working directory used throughout this document: `/foss/designs/<your_project>/librelane/`

---

## 4. Running the LibreLane Flow

```bash
cd /foss/designs/<your_project>/librelane
source <PATH_TO_PDK_SETUP_SCRIPT>/sak-pdk-script.sh gf180mcuD gf180mcu_fd_sc_mcu7t5v0
librelane config.yaml --pdk gf180mcuD --pdk-root /foss/pdks --manual-pdk --run-tag <run_tag>
```

### Flow stages, in order

1. **Synthesis** — RTL → gate-level netlist (Yosys)
2. **Floorplanning** — die/core area, row structure
3. **PDN generation** — power grid (stripes, rails, core ring)
4. **Global placement** — rough cell placement
5. **Post-placement repair** — buffer/resize fixes for slew/cap
6. **Detailed placement** — legalizes exact cell positions
7. **Clock tree synthesis (CTS)** — builds the clock distribution network
8. **Post-CTS repair** — further buffer/resize fixes
9. **Global routing** — coarse routing
10. **Detailed routing** — final, exact metal routing
11. **Fill insertion** — fills empty space with fill/decap cells, backfills blockage zones
12. **Parasitic extraction (RCX)** — real RC values from the routed layout
13. **Static timing analysis (STA)** — final timing across all corners
14. **GDSII streamout** — writes the final layout file (KLayout)
15. **Sign-off checks** — DRC (Magic + KLayout), LVS (netgen), antenna, manufacturability report

### What's in `runs/<run_tag>/final/`

| Folder/file | Contents |
|---|---|
| `gds/qspi_chip_top.gds` | The finished physical layout — final deliverable for tapeout/integration. |
| `def/qspi_chip_top.def` | Placement + routing database (pins, rows, nets, special nets) in DEF format. |
| `nl/qspi_chip_top.nl.v` | Logical gate-level netlist — functional cells only, **no** fill/tap/decap. |
| `pnl/qspi_chip_top.pnl.v` | Physical netlist — includes fill/tap/decap cells actually present in the GDS. **Use this one for LVS.** |
| `spice/qspi_chip_top.spice` | SPICE netlist extracted from the GDS (magic), used as the LVS comparison side. |
| `lib/` | Per-corner timing/liberty views of the finished design. |
| `sdc/` | Final timing constraints. |
| `spef/{min,nom,max}/` | Extracted parasitics per corner group, used in STA and standalone violator checks. |
| `metrics.json` / `metrics.csv` | Every reported metric from every stage — DRC/LVS error counts, slew/cap/fanout violation counts, timing WNS/TNS per corner, antenna results, etc. |
| `mag/`, `mag_gds/`, `klayout_gds/` | Layout also saved in Magic and KLayout-native formats. |
| `vh/`, `json_h/` | Verilog header / JSON hierarchy views. |

---

## 5. Timing / DRV Tuning (Slew & Capacitance)

PDK defaults are conservative, well below the library's real characterized limits:

| Constraint | PDK default | Real physical limit |
|---|---|---|
| `MAX_TRANSITION_CONSTRAINT` | 3 ns | 8.9 ns |
| `MAX_CAPACITANCE_CONSTRAINT` | 0.2 pF | — |

Per LibreLane's own documentation: *"Violating maximum capacitance and maximum transition constraints are OK if you don't have setup/hold violations."* Setup/hold were 0 across all 9 corners throughout.

**Use `MAX_TRANSITION_CONSTRAINT`, not `SYNTH_MAX_TRAN`** (deprecated, only affects the Yosys synthesis stage, not the real STA constraint applied via `set_max_transition`).

Repair-effort margins used (how hard the resizer works on each violation, not the pass/fail bar):
```yaml
DESIGN_REPAIR_MAX_SLEW_PCT: 40       # default 20
GRT_DESIGN_REPAIR_MAX_SLEW_PCT: 40   # default 10
DESIGN_REPAIR_MAX_CAP_PCT: 68        # default 20
GRT_DESIGN_REPAIR_MAX_CAP_PCT: 68    # default 10
```

### Tuning progression (all rows: DRC 0, LVS 0, setup/hold 0/0)

| `MAX_TRANSITION_CONSTRAINT` | Cap margin | Slew violations | Cap violations | Antenna |
|---|---|---|---|---|
| 3 ns (PDK default, implicit) | 40% | 4046 | 128 | 0 |
| 4 ns | 40% | 2100 | 314 | 0 |
| 5 ns | 40% | 1476 | 397 | 0 |
| 6 ns | 40% | 808 | 404 | 0 |
| 8 ns | 60% | 16 | 105 | **0** ✅ |
| 8 ns | 68%, `MAX_CAP`=0.25 | **0** | **69** | **0** ✅ — final |
| 8 ns | 70% | 0 | 69 | **1** ⚠️ regression |
| 8 ns | 80% | 0 | 69 | **1** ⚠️ regression |
| 8.9 ns | 68%, `MAX_CAP`=0.25 | 0 | 69 | 0 (confirms plateau past 8ns) |

**Do not raise the cap margin past ~68%** — it reintroduces antenna violations by changing buffer placement/routing.

### Final config values
```yaml
CLOCK_PERIOD: 160
MAX_FANOUT_CONSTRAINT: 17
PL_TARGET_DENSITY_PCT: 45
MAX_TRANSITION_CONSTRAINT: 8.9
MAX_CAPACITANCE_CONSTRAINT: 0.25
DESIGN_REPAIR_MAX_SLEW_PCT: 40
GRT_DESIGN_REPAIR_MAX_SLEW_PCT: 40
DESIGN_REPAIR_MAX_CAP_PCT: 68
GRT_DESIGN_REPAIR_MAX_CAP_PCT: 68
```

---

## 6. Standalone DRC & LVS

Run these from `runs/<run_tag>/final/gds/`.

**DRC:**
```bash
cd /foss/designs/<your_project>/librelane/runs/<run_tag>/final/gds
magic -rcfile /foss/pdks/gf180mcuD/libs.tech/magic/gf180mcuD.magicrc -noconsole -dnull << 'EOF'
gds read qspi_chip_top.gds
load qspi_chip_top
select top cell
drc check
drc why
quit -noprompt
EOF
```
Expected: `No errors found.`

**Common mistake:** `load` must use the cell's real internal name (see the `Reading "<name>".` line printed during `gds read`), not the filename. Loading a name that doesn't exist silently creates an empty cell and DRC reports "no errors" on nothing.

**LVS:**
```bash
cd /foss/designs/<your_project>/librelane/runs/<run_tag>/final/gds

# extract SPICE from the GDS
magic -rcfile /foss/pdks/gf180mcuD/libs.tech/magic/gf180mcuD.magicrc -noconsole -dnull << 'EOF'
gds read qspi_chip_top.gds
load qspi_chip_top
select top cell
extract all
ext2spice lvs
ext2spice
quit -noprompt
EOF

# compare against the physical netlist (.pnl.v, not .nl.v)
netgen -batch lvs \
  "qspi_chip_top.spice qspi_chip_top" \
  "../pnl/qspi_chip_top.pnl.v qspi_chip_top" \
  /usr/local/lib/python3.12/dist-packages/librelane/scripts/netgen/setup.tcl \
  lvs_result.out
cat lvs_result.out
```
(`setup.tcl` also exists at `/foss/pdks/gf180mcuD/libs.tech/netgen/setup.tcl` — both valid.)

Expected: `Circuits match uniquely.`

---

## 7. Verifying Placement Blockages Are Backfilled

Any placement-stage blockage zones used during floorplanning/PDN setup should end up populated with fill/tap cells by the fill-insertion stage, not left empty in the final GDS. Confirm this directly:
```python
import klayout.db as db
layout = db.Layout(); layout.read('qspi_chip_top.gds')
top = layout.top_cell()
region = db.DBox(x1, y1, x2, y2).to_itype(layout.dbu)   # zone in microns
count = sum(1 for inst in top.each_inst() if inst.bbox().overlaps(region))
print('Instances:', count)
```
Checked zones (all populated, 30–50 instances each): VSS blockage, VDD blockage, CTS trouble-zone.

---


## 8. Preparing the Tapeout Copy (PCell Context)

KLayout can embed live references back to PCells/libraries when saving. If an integrator's environment resolves those references differently, geometry can silently change. Keep two copies:

- **Editing copy** — normal save, keeps PCell/library references.
- **Tapeout copy** — `File → Save As`, uncheck **"Store PCell and library context information"**. This is the file to hand off for integration.

Verify:
```python
import klayout.db as db
layout = db.Layout(); layout.read('qspi_chip_top.gds')
proxies = [c.name for c in layout.each_cell() if c.is_proxy()]
print('Proxy/PCell cells:', len(proxies))   # expect 0 for a tapeout copy
print('DBU:', layout.dbu)                   # expect 0.001 (0.005 is too coarse for reliable integrated-chip DRC)
```

---

## 9. Final Verified State

- **Functional:** all 9 cocotb tests pass
- **DRC:** 0 errors (magic, whole-chip)
- **LVS:** Circuits match uniquely (vs. `.pnl.v`)
- **Timing:** 0 setup/hold violations, all 9 PVT corners
- **Slew violations:** 0 (from 4046 at PDK-default constraints)
- **Cap violations:** 69 (from 128)
- **Fanout violations:** 0
- **Antenna:** 0/0/0
- **GDS database unit:** 0.001 µm
- **PCell context:** none embedded (tapeout-safe)
---
- [Original README for this repo template](docs/repo-README.md)
---
## License

Apache-2.0, inherited from upstream. See `LICENSE` for the full text,
`NOTICE` for attribution of third-party material, and `AUTHORS.md`
for the list of copyright holders.
