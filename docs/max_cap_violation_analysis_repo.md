# Max-Capacitance Violations: Step-by-Step Analysis (tt corner)


At the typical corner (tt_025C_5v00), qspi_chip_top has 68 max-capacitance violations. All 68 are clock-tree buffers, the worst load is 0.72 pF against the 0.25 pF constraint set in our configuration, and the cell library's own limits for these buffers are 3.813 pF and 4.756 pF.

## Result at a glance

| Item | Value (tt_025C_5v00, nominal parasitics) |
| --- | --- |
| Violating pins | 68 |
| Where they are | 1 root buffer (clkbuf_0, a clkbuf_16), 4 level-2 buffers (clkbuf_2_*, clkbuf_20), 63 level-6 buffers (clkbuf_6_*, clkbuf_20) |
| Worst load | 0.72 pF on clkbuf_2_0_0_clk, slack -0.47 |
| Limit applied to the design | 0.25 pF, from MAX_CAPACITANCE_CONSTRAINT: 0.25 in the config, written into the final SDC |
| Library limit, clkbuf_16 | 3.813 pF |
| Library limit, clkbuf_20 | 4.756 pF |
| Worst load as a share of the clkbuf_20 library limit | about 15% |

## Step 1: Open the container

Run these two commands in the Terminal (not inside the container). The design tools and the project folder at /foss/designs exist only inside the Docker container named gf180.

```bash
docker start gf180
docker exec -it gf180 bash
```


## Step 2: Go to the run folder

The run folder is the folder that contains the final folder. Inside the container it is under /foss/designs, for example /foss/designs/<project>/librelane/runs/<run_tag>.

```bash
cd /foss/designs/<project>/librelane/runs/<run_tag>
ls final
```

## Step 3: Write the check script

Run this inside the container, in the run folder. It creates a small OpenROAD script named capcheck.tcl:

```bash
cat > capcheck.tcl << 'EOF'
read_db final/odb/qspi_chip_top.odb
read_liberty /foss/pdks/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib
read_spef [lindex [glob final/spef/nom/*.spef] 0]
read_sdc [lindex [glob final/sdc/*.sdc] 0]
set_max_capacitance 0.25 [current_design]
report_check_types -max_capacitance -violators -verbose
EOF
```

What each line does:

| Line | Purpose |
| --- | --- |
| read_db final/odb/qspi_chip_top.odb | Loads the finished layout database, with every cell, buffer and wire. |
| read_liberty ...tt_025C_5v00.lib | Loads the cell timing models for the typical corner (tt, 25 C, 5.0 V). |
| read_spef [lindex [glob final/spef/nom/*.spef] 0] | Loads the extracted wire parasitics for the nominal corner. The glob finds the file name automatically. |
| read_sdc [lindex [glob final/sdc/*.sdc] 0] | Loads the final timing constraints. |
| set_max_capacitance 0.25 [current_design] | Sets the 0.25 pF limit for this OpenROAD session only. Nothing is saved. |
| report_check_types -max_capacitance -violators -verbose | Lists every pin whose load is over the limit, with its load and slack. |

## Step 4: Run the script and read the report

```bash
openroad -no_splash -exit capcheck.tcl > cap_violators.txt
head -60 cap_violators.txt
```

The first command runs the script and saves the full report to cap_violators.txt. The second prints the first 60 lines. Result, exactly as it printed (10 entries, worst first; the last entry is cut off by head -60):

```text
max capacitance

Pin clkbuf_2_0_0_clk/Z ^
max capacitance    0.25
capacitance        0.72
-----------------------
Slack             -0.47 (VIOLATED)

Pin clkbuf_2_3_0_clk/Z ^
max capacitance    0.25
capacitance        0.70
-----------------------
Slack             -0.45 (VIOLATED)

Pin clkbuf_2_2_0_clk/Z ^
max capacitance    0.25
capacitance        0.70
-----------------------
Slack             -0.45 (VIOLATED)

Pin clkbuf_2_1_0_clk/Z ^
max capacitance    0.25
capacitance        0.67
-----------------------
Slack             -0.42 (VIOLATED)

Pin clkbuf_6_31_0_clk/Z ^
max capacitance    0.25
capacitance        0.53
-----------------------
Slack             -0.28 (VIOLATED)

Pin clkbuf_6_53_0_clk/Z ^
max capacitance    0.25
capacitance        0.51
-----------------------
Slack             -0.26 (VIOLATED)

Pin clkbuf_6_55_0_clk/Z ^
max capacitance    0.25
capacitance        0.50
-----------------------
Slack             -0.25 (VIOLATED)

Pin clkbuf_6_52_0_clk/Z ^
max capacitance    0.25
capacitance        0.50
-----------------------
Slack             -0.25 (VIOLATED)

Pin clkbuf_6_30_0_clk/Z ^
max capacitance    0.25
capacitance        0.49
-----------------------
Slack             -0.24 (VIOLATED)

Pin clkbuf_6_62_0_clk/Z ^
max capacitance    0.25
capacitance        0.48
-----------------------
```

How to read an entry: Pin is the output pin of the buffer. max capacitance is the limit (0.25 pF), capacitance is the load that pin actually drives, and Slack is the limit minus the load (negative means over the limit). Every violator in this list is a clock buffer (clkbuf_*_clk).

## Step 5: Count the violators and group them by clock-tree level

```bash
grep -c "^Pin" cap_violators.txt
grep "^Pin" cap_violators.txt | awk '{print $2}' | cut -d/ -f1 | awk -F_ '{print $1"_"$2}' | sort | uniq -c
```

Result:

```text
68
      1 clkbuf_0
      4 clkbuf_2
     63 clkbuf_6
```

The first command counts the lines that start with Pin, so one per violator: 68. The second takes each violating pin's instance name, keeps only its first two name parts (clkbuf plus the tree level) and counts how many violators fall in each level. All 68 are clock buffers: 1 at level 0 (the root), 4 at level 2 and 63 at level 6, the level just before the flip-flops.

## Step 6: Rerun without our extra limit line

The aim was to see whether the 0.25 pF limit came only from the line we added to the script. The copy of the script below has every line containing set_max_capacitance removed:

```bash
sed '/set_max_capacitance/d' capcheck.tcl > capcheck_lib.tcl
openroad -no_splash -exit capcheck_lib.tcl > cap_violators_lib.txt
grep -c "^Pin" cap_violators_lib.txt
head -12 cap_violators_lib.txt
```

Result:

```text
68
max capacitance

Pin clkbuf_2_0_0_clk/Z ^
max capacitance    0.25
capacitance        0.72
-----------------------
Slack             -0.47 (VIOLATED)

Pin clkbuf_2_3_0_clk/Z ^
max capacitance    0.25
capacitance        0.70
-----------------------
```

The count is still 68 and the limit is still 0.25. So the limit does not come from the line we added. It also comes from the final SDC file, which the script loads, as step 7 shows. This step therefore did not separate our limit from the library's own limit; steps 7 and 8 do that.

## Step 7: Find where the 0.25 pF limit comes from

```bash
grep -i "max_cap" final/sdc/*.sdc
```

Result:

```text
set_max_capacitance 0.2500 [current_design]
```

The final SDC file already contains the 0.25 pF limit. It is written by the flow from MAX_CAPACITANCE_CONSTRAINT: 0.25 in config.yaml, so the 0.25 pF figure is the limit we chose for the design, not a limit of the cells.

## Step 8: Look up the library's own limits for the clock buffers

```bash
L=/foss/pdks/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__tt_025C_5v00.lib
awk '/^[ \t]*cell *\(/ {name=$0} /max_capacitance/ && name ~ /clkbuf_(8|12|16|20)[")]/ && !seen[name]++ {print name; print $0}' $L
```

Result:

```text
  cell(gf180mcu_fd_sc_mcu7t5v0__clkbuf_8) {
      max_capacitance : 1.819 ;
  cell(gf180mcu_fd_sc_mcu7t5v0__clkbuf_12) {
      max_capacitance : 2.865 ;
  cell(gf180mcu_fd_sc_mcu7t5v0__clkbuf_16) {
      max_capacitance : 3.813 ;
  cell(gf180mcu_fd_sc_mcu7t5v0__clkbuf_20) {
      max_capacitance : 4.756 ;
```

The .lib file is the cell library's timing model. Each cell has a max_capacitance value: the largest load the cell was characterized to drive. The awk command remembers the current cell name while it reads the file and prints the first max_capacitance line for each of clkbuf_8, clkbuf_12, clkbuf_16 and clkbuf_20.

To look up one other cell, change the name in the pattern, or use this shorter form for a single cell:

```bash
grep -n -A60 "cell(gf180mcu_fd_sc_mcu7t5v0__clkbuf_20)" $L | grep -m1 max_capacitance
```

## Step 9: Find which buffer type is used at each clock-tree level

```bash
cat > celltype.tcl << 'EOF'
read_db final/odb/qspi_chip_top.odb
set blk [ord::get_db_block]
foreach n {clkbuf_0_clk clkbuf_2_0_0_clk clkbuf_6_31_0_clk} {
  set i [$blk findInst $n]
  if {$i eq "NULL"} {puts "$n not found"} else {puts "$n [[$i getMaster] getName]"}
}
EOF
openroad -no_splash -exit celltype.tcl
```

Result:

```text
clkbuf_0_clk gf180mcu_fd_sc_mcu7t5v0__clkbuf_16
clkbuf_2_0_0_clk gf180mcu_fd_sc_mcu7t5v0__clkbuf_20
clkbuf_6_31_0_clk gf180mcu_fd_sc_mcu7t5v0__clkbuf_20
```

The script looks up one buffer from each level in the layout database and prints its cell type (its master). The root buffer is a clkbuf_16 and the buffers at levels 2 and 6 are clkbuf_20, so the library limits to compare against are 3.813 pF and 4.756 pF.

## Conclusion

The 68 violations exceed only the 0.25 pF limit we set in the configuration. The load on every one of these buffers is below the capacitance limit of the library cells themselves: the worst load is 0.72 pF, against 3.813 pF for a clkbuf_16 and 4.756 pF for a clkbuf_20.
