
# Copyright 2025 LibreLane Contributors
# Adapted from OpenLane
# Copyright 2020-2022 Efabless Corporation
# Licensed under the Apache License, Version 2.0

source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set secondary []
foreach vdd $::env(VDD_NETS) gnd $::env(GND_NETS) {
    if { $vdd != $::env(VDD_NET)} {
        lappend secondary $vdd
        set db_net [[ord::get_db_block] findNet $vdd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $vdd]
            $net setSpecial
            $net setSigType "POWER"
        }
    }
    if { $gnd != $::env(GND_NET)} {
        lappend secondary $gnd
        set db_net [[ord::get_db_block] findNet $gnd]
        if {$db_net == "NULL"} {
            set net [odb::dbNet_create [ord::get_db_block] $gnd]
            $net setSpecial
            $net setSigType "GROUND"
        }
    }
}

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET) \
    -secondary_power $secondary

if { $::env(PDN_MULTILAYER) == 1 } {
    set arg_list [list]
    if { $::env(PDN_ENABLE_PINS) } {
        lappend arg_list -pins "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"
    }
    define_pdn_grid -name stdcell_grid -starts_with POWER -voltage_domain CORE {*}$arg_list

    set arg_list [list]
    append_if_equals arg_list PDN_EXTEND_TO "core_ring" -extend_to_core_ring
    append_if_equals arg_list PDN_EXTEND_TO "boundary" -extend_to_boundary

    add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_VERTICAL_LAYER) \
        -width $::env(PDN_VWIDTH) -pitch $::env(PDN_VPITCH) -offset $::env(PDN_VOFFSET) \
        -spacing $::env(PDN_VSPACING) -starts_with POWER {*}$arg_list

    add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_HORIZONTAL_LAYER) \
        -width $::env(PDN_HWIDTH) -pitch $::env(PDN_HPITCH) -offset $::env(PDN_HOFFSET) \
        -spacing $::env(PDN_HSPACING) -starts_with POWER {*}$arg_list

    add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"
} else {
    set arg_list [list]
    if { $::env(PDN_ENABLE_PINS) } {
        lappend arg_list -pins "$::env(PDN_VERTICAL_LAYER)"
    }
    define_pdn_grid -name stdcell_grid -starts_with POWER -voltage_domain CORE {*}$arg_list

    set arg_list [list]
    append_if_equals arg_list PDN_EXTEND_TO "core_ring" -extend_to_core_ring
    append_if_equals arg_list PDN_EXTEND_TO "boundary" -extend_to_boundary

    add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_VERTICAL_LAYER) \
        -width $::env(PDN_VWIDTH) -pitch $::env(PDN_VPITCH) -offset $::env(PDN_VOFFSET) \
        -spacing $::env(PDN_VSPACING) -starts_with POWER {*}$arg_list
}

if { $::env(PDN_ENABLE_RAILS) == 1 } {
    add_pdn_stripe -grid stdcell_grid -layer $::env(PDN_RAIL_LAYER) \
        -width $::env(PDN_RAIL_WIDTH) -followpins
    add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_RAIL_LAYER) $::env(PDN_VERTICAL_LAYER)"
}

# Core ring — REQUIRED for the bridge builder below to have something to
# bridge to. 

if { $::env(PDN_CORE_RING) == 1 } {
    if { $::env(PDN_MULTILAYER) == 1 } {
        set arg_list [list]
        append_if_flag arg_list PDN_CORE_RING_ALLOW_OUT_OF_DIE -allow_out_of_die
        append_if_flag arg_list PDN_CORE_RING_CONNECT_TO_PADS -connect_to_pads
        append_if_equals arg_list PDN_EXTEND_TO "boundary" -extend_to_boundary

        set pdn_core_vertical_layer $::env(PDN_VERTICAL_LAYER)
        set pdn_core_horizontal_layer $::env(PDN_HORIZONTAL_LAYER)
        if { [info exists ::env(PDN_CORE_VERTICAL_LAYER)] } {
            set pdn_core_vertical_layer $::env(PDN_CORE_VERTICAL_LAYER)
        }
        if { [info exists ::env(PDN_CORE_HORIZONTAL_LAYER)] } {
            set pdn_core_horizontal_layer $::env(PDN_CORE_HORIZONTAL_LAYER)
        }

        add_pdn_ring -grid stdcell_grid \
            -layers "$pdn_core_vertical_layer $pdn_core_horizontal_layer" \
            -widths "$::env(PDN_CORE_RING_VWIDTH) $::env(PDN_CORE_RING_HWIDTH)" \
            -spacings "$::env(PDN_CORE_RING_VSPACING) $::env(PDN_CORE_RING_HSPACING)" \
            -core_offset "$::env(PDN_CORE_RING_VOFFSET) $::env(PDN_CORE_RING_HOFFSET)" \
            {*}$arg_list

        if { [info exists ::env(PDN_CORE_VERTICAL_LAYER)] } {
            add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_CORE_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"
        }
        if { [info exists ::env(PDN_CORE_HORIZONTAL_LAYER)] } {
            add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_CORE_HORIZONTAL_LAYER) $::env(PDN_VERTICAL_LAYER)"
        }
        if { [info exists ::env(PDN_CORE_VERTICAL_LAYER)] && [info exists ::env(PDN_CORE_HORIZONTAL_LAYER)] } {
            add_pdn_connect -grid stdcell_grid -layers "$::env(PDN_CORE_VERTICAL_LAYER) $::env(PDN_CORE_HORIZONTAL_LAYER)"
        }
    } else {
        throw APPLICATION "PDN_CORE_RING cannot be used when PDN_MULTILAYER is set to false."
    }
}

define_pdn_grid -macro -default -name macro -starts_with POWER \
    -halo "$::env(PDN_HORIZONTAL_HALO) $::env(PDN_VERTICAL_HALO)"
add_pdn_connect -grid macro -layers "$::env(PDN_VERTICAL_LAYER) $::env(PDN_HORIZONTAL_LAYER)"

# Padframe power bridge (A30: VSS on west edge, VDD on north/top edge)


set ::_PG_BRIDGE_W_UM   2.0
set ::_PG_M2_LAND_UM    2.0
set ::_PG_M3_EDGE_UM    0.20
set ::_PG_VIA_ROWS      3
set ::_PG_VIA_COLS      3

proc _pg_template_path {} {
    if {[info exists ::env(FP_DEF_TEMPLATE)] && [file readable $::env(FP_DEF_TEMPLATE)]} {
        return $::env(FP_DEF_TEMPLATE)
    }
    if {![info exists ::env(PDN_CFG)]} {
        error "power-bridge: cannot locate template (no FP_DEF_TEMPLATE, no PDN_CFG)"
    }
    set cfgdir [file dirname $::env(PDN_CFG)]
    set cfg    [file join $cfgdir config.yaml]
    if {[file readable $cfg]} {
        set fh [open $cfg r]; set txt [read $fh]; close $fh
        if {[regexp {FP_DEF_TEMPLATE:\s*dir::(\S+)} $txt -> rel]} {
            set p [file normalize [file join $cfgdir $rel]]
            if {[file readable $p]} { return $p }
        }
    }
    error "power-bridge: could not resolve FP_DEF_TEMPLATE from $cfg"
}

# Returns {tdbu {{y1 y2 x1 x2} ...}} for every Metal2 stub row of $net_name

proc _pg_template_pin_rows {net_name} {
    set fh [open [_pg_template_path] r]
    set tdbu 200
    set rows {}
    set in 0
    while {[gets $fh line] >= 0} {
        if {[regexp {UNITS\s+DISTANCE\s+MICRONS\s+(\d+)} $line -> u]} { set tdbu $u; continue }
        if {[regexp {^-\s+(\S+)\s+\+\s+NET\s+(\S+)} $line -> pn nn]} {
            set in [expr {$nn eq $net_name}]; continue
        }
        if {$in} {
            if {[regexp {LAYER\s+Metal2\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)} \
                     $line -> x1 y1 x2 y2]} {
                lappend rows [list $y1 $y2 $x1 $x2]
            }
            if {[string first ";" $line] >= 0} { set in 0 }
        }
    }
    close $fh
    return [list $tdbu $rows]
}

# Find nearest ring leg: for west/east edges look for a tall vertical stripe;
# for north/south edges look for a wide horizontal stripe. Returns {lo hi}.


proc _pg_ring_leg {net edge} {
    set best ""
    foreach sw [$net getSWires] {
        foreach box [$sw getWires] {
            if {[$box isVia]} { continue }
            set ly [$box getTechLayer]
            if {$ly eq "NULL"} { continue }
            set lname [$ly getName]
            set w [expr {[$box xMax] - [$box xMin]}]
            set h [expr {[$box yMax] - [$box yMin]}]
            if {$edge eq "west" || $edge eq "east"} {
                if {$lname ne "Metal2" || $h < 5 * $w} { continue }
                if {$edge eq "west"} {
                    if {$best eq "" || [$box xMin] < [lindex $best 0]} {
                        set best [list [$box xMin] [$box xMax]]
                    }
                } else {
                    if {$best eq "" || [$box xMax] > [lindex $best 1]} {
                        set best [list [$box xMin] [$box xMax]]
                    }
                }
            } else {
                if {$lname ne "Metal3" || $w < 5 * $h} { continue }
                if {$edge eq "north"} {
                    if {$best eq "" || [$box yMax] > [lindex $best 1]} {
                        set best [list [$box yMin] [$box yMax]]
                    }
                } else {
                    if {$best eq "" || [$box yMin] < [lindex $best 0]} {
                        set best [list [$box yMin] [$box yMax]]
                    }
                }
            }
        }
    }
    return $best
}

proc _pg_make_stack_via {block name viarule_candidates bot cut top nrow ncol} {
    set v [odb::dbVia_create $block $name]
    set rule "NULL"
    set tried {}
    foreach vr $viarule_candidates {
        lappend tried $vr
        set rule [[$block getTech] findViaGenerateRule $vr]
        if {$rule ne "NULL"} { break }
    }
    if {$rule eq "NULL"} {
        error "power-bridge: none of these via generate rules exist in the tech: $tried"
    }
    $v setViaGenerateRule $rule
    set cs [expr {($nrow >= 4 || $ncol >= 4) ? 720 : 520}]
    set p  [$v getViaParams]
    $p setBottomLayer $bot
    $p setCutLayer    $cut
    $p setTopLayer    $top
    $p setXCutSize 520 ; $p setYCutSize 520
    $p setXCutSpacing $cs ; $p setYCutSpacing $cs
    $p setXBottomEnclosure 120 ; $p setYBottomEnclosure 120
    $p setXTopEnclosure    120 ; $p setYTopEnclosure    120
    $p setNumCutRows $nrow ; $p setNumCutCols $ncol
    $v setViaParams $p
    return $v
}

proc _pg_avoid_routing_trouble_zone {} {
    if {[info exists ::_PG_AVOID_DONE]} { return }
    set ::_PG_AVOID_DONE 1
    set block [ord::get_db_block]
    set dbu   [$block getDbUnitsPerMicron]
   
    set zx1 [expr {int(739.0 * $dbu)}]
    set zx2 [expr {int(779.0 * $dbu)}]
    set zy1 [expr {int(277.0 * $dbu)}]
    set zy2 [expr {int(317.0 * $dbu)}]
    set margin [expr {int(0.5 * $dbu)}]

    
    set fixed_boxes {}
    foreach inst [$block getInsts] {
        if {![$inst isFixed]} { continue }
        set bbox [$inst getBBox]
        set ix1 [$bbox xMin]; set ix2 [$bbox xMax]
        set iy1 [$bbox yMin]; set iy2 [$bbox yMax]
        if {$ix2 < $zx1 || $ix1 > $zx2 || $iy2 < $zy1 || $iy1 > $zy2} { continue }
        lappend fixed_boxes [list [expr {$ix1 - $margin}] [expr {$iy1 - $margin}] [expr {$ix2 + $margin}] [expr {$iy2 + $margin}]]
    }

    if {[llength $fixed_boxes] == 0} {
        odb::dbBlockage_create $block $zx1 $zy1 $zx2 $zy2
        puts "\[INFO\] power-bridge: placement blockage (full, no fixed cells found) to steer CTS away from known DRT-0073 trouble zone ($zx1,$zy1)-($zx2,$zy2)"
        return
    }

    set xcuts {}
    foreach fb $fixed_boxes {
        lassign $fb fx1 fy1 fx2 fy2
        lappend xcuts $fx1
        lappend xcuts $fx2
    }
    lappend xcuts $zx1
    lappend xcuts $zx2
    set xcuts [lsort -integer -unique $xcuts]

    set nb 0
    set n [llength $xcuts]
    for {set idx 0} {$idx < $n - 1} {incr idx} {
        set a [lindex $xcuts $idx]
        set b [lindex $xcuts [expr {$idx + 1}]]
        if {$a < $zx1} { set a $zx1 }
        if {$b > $zx2} { set b $zx2 }
        if {$b <= $a} { continue }
        set mid [expr {($a + $b) / 2}]
        set inside 0
        foreach fb $fixed_boxes {
            lassign $fb fx1 fy1 fx2 fy2
            if {$mid >= $fx1 && $mid <= $fx2} { set inside 1; break }
        }
        if {$inside} { continue }
        odb::dbBlockage_create $block $a $zy1 $b $zy2
        incr nb
    }
    puts "\[INFO\] power-bridge: placement blockage ($nb strip(s), avoiding [llength $fixed_boxes] existing fixed cell(s)) to steer CTS away from known DRT-0073 trouble zone"
}

proc _pg_build_power_bridges {} {
    if {[info exists ::_PG_DONE]} { return }
    set ::_PG_DONE 1
    set block [ord::get_db_block]
    set tech  [ord::get_db_tech]
    set dbu   [$block getDbUnitsPerMicron]
    set m2    [$tech findLayer Metal2]
    set v2    [$tech findLayer Via2]
    set m3    [$tech findLayer Metal3]
    set v3    [$tech findLayer Via3]
    set m4    [$tech findLayer Metal4]
    if {$m2 eq "NULL" || $v2 eq "NULL" || $m3 eq "NULL"} {
        error "power-bridge: Metal2/Via2/Metal3 not found in tech"
    }
    if {$v3 eq "NULL" || $m4 eq "NULL"} {
        error "power-bridge: Via3/Metal4 not found in tech (needed to jump over VSS's own ring leg)"
    }
    set bw    [expr {int($::_PG_BRIDGE_W_UM * $dbu)}]
    set landx [expr {int($::_PG_M2_LAND_UM  * $dbu)}]
    set m3x0  [expr {int($::_PG_M3_EDGE_UM  * $dbu)}]

    set vdd [$block findNet VDD]
    set vss [$block findNet VSS]
    if {$vdd eq "NULL" || $vss eq "NULL"} { error "power-bridge: VDD/VSS net missing" }

    set colv  [_pg_make_stack_via $block PG_V2_COL {Via2_GEN_HH} $m2 $v2 $m3 $::_PG_VIA_ROWS $::_PG_VIA_COLS]
   
    set colv3 [_pg_make_stack_via $block PG_V3_COL {Via3_GEN_HH Via3_GEN VIA3_GEN_HH Via3_GEN_VH} $m3 $v3 $m4 1 1]

    set die_x2 [expr {[[$block getDieArea] xMax]}]
    set die_y2 [expr {[[$block getDieArea] yMax]}]

    #  VSS: west edge, Metal2 bridge 

    set vss_leg [_pg_ring_leg $vss west]
    if {$vss_leg eq ""} { error "power-bridge: could not find VSS west ring leg" }
    lassign $vss_leg vssL vssR
    lassign [_pg_template_pin_rows VSS] tdbu rows
    if {[llength $rows] == 0} { error "power-bridge: no VSS Metal2 stubs in template" }
    set sc [expr {double($dbu) / $tdbu}]
    set sw [odb::dbSWire_create $vss "ROUTED"]
    set vss_minY ""
    set vss_maxY ""
    foreach r $rows {
        lassign $r y1 y2 x1 x2
        set cy [expr {int(($y1 + $y2) * 0.5 * $sc)}]
        set loY [expr {$cy - $bw / 2}]
        set hiY [expr {$cy + $bw / 2}]
        odb::dbSBox_create $sw $m2 0 $loY $vssR $hiY "STRIPE"
        if {$vss_minY eq "" || $loY < $vss_minY} { set vss_minY $loY }
        if {$vss_maxY eq "" || $hiY > $vss_maxY} { set vss_maxY $hiY }
    }
    puts "\[INFO\] power-bridge: VSS  [llength $rows] Metal2 bridges (west edge)"

 
    set margin [expr {int(0.5 * $dbu)}]
    set vssBxLo 0
    set vssBxHi [expr {$vssR + $margin}]
    set vssByLo [expr {$vss_minY - $margin}]
    set vssByHi [expr {$vss_maxY + $margin}]
    
    odb::dbBlockage_create $block $vssBxLo $vssByLo $vssBxHi $vssByHi
    odb::dbObstruction_create $block $m2 $vssBxLo $vss_minY $vssR $vss_maxY
    puts "\[INFO\] power-bridge: VSS blockage/obstruction (restored) ($vssBxLo,$vssByLo)-($vssBxHi,$vssByHi)"

    #  VDD: north/top edge


    set vdd_leg [_pg_ring_leg $vdd north]
    if {$vdd_leg eq ""} { error "power-bridge: could not find VDD north ring leg" }
    lassign $vdd_leg vddB vddT
    lassign [_pg_template_pin_rows VDD] tdbu rows
    if {[llength $rows] == 0} { error "power-bridge: no VDD Metal2 stubs in template" }
    set sc [expr {double($dbu) / $tdbu}]
    set sw [odb::dbSWire_create $vdd "ROUTED"]

 
    set ring_near [expr {($vddB > $vddT) ? $vddB : $vddT}]
    set ring_far  [expr {($vddB > $vddT) ? $vddT : $vddB}]
    if {$ring_near >= $die_y2} {
        error "power-bridge: VDD ring leg (near=$ring_near) is at/above die edge ($die_y2) -- geometry error"
    }



    set vss_north_leg [_pg_ring_leg $vss north]
    if {$vss_north_leg eq ""} {
        error "power-bridge: could not find VSS north ring leg (needed to route VDD's bridge around it)"
    }
    lassign $vss_north_leg vssNorthLo vssNorthHi
    if {!($ring_near < $vssNorthLo && $vssNorthHi < $die_y2)} {
        error "power-bridge: VSS north leg ($vssNorthLo..$vssNorthHi) is not cleanly between VDD's ring (near=$ring_near) and the die edge ($die_y2) -- geometry assumption broken"
    }

    
    set ov [expr {int(0.5 * $dbu)}]
    
    set via3_half [expr {520 / 2 + 120}]
    # Minimum real clearance from VSS's edge to the via's own body edge.
    set via3_clear [expr {int(0.8 * $dbu)}]

    set m2_land_bottom [expr {$die_y2 - $landx}]
   
    set m3_edge_y  [expr {$m2_land_bottom + $m3x0}]
    set via_top_y  [expr {int(($m2_land_bottom + $m3_edge_y) * 0.5)}]

    
    set via3_top_y [expr {$vssNorthHi + $via3_clear + $via3_half}]
    set m3u_bottom [expr {$via3_top_y - $via3_half - $ov}]
    set m3u_top    $m3_edge_y
    if {$m3u_bottom >= $m3u_top} {
        error "power-bridge: VDD upper Metal3 stub inverted (bottom=$m3u_bottom >= top=$m3u_top) -- not enough room between the edge landing pad and VSS's leg for this via"
    }

    
    set m4_top    [expr {$via3_top_y + $via3_half + $ov}]
    set via3_bottom_y [expr {$vssNorthLo - $via3_clear - $via3_half}]
    set m4_bottom [expr {$via3_bottom_y - $via3_half - $ov}]

    set m4_overlap [expr {int(0.3 * $dbu)}]
    set m4_floor   [expr {$ring_far - $m4_overlap}]
    if {$m4_bottom > $m4_floor} { set m4_bottom $m4_floor }

    set m3l_top    [expr {$via3_bottom_y + $via3_half + $ov}]
    set m3l_bottom $ring_far
    if {$m3l_bottom >= $m3l_top} {
        error "power-bridge: VDD lower Metal3 stub inverted (bottom=$m3l_bottom >= top=$m3l_top) -- not enough room between VSS's leg and VDD's own ring for this via"
    }

    puts "\[INFO\] power-bridge: VDD span die_y2=$die_y2 ring=($ring_far..$ring_near) vss_leg=($vssNorthLo..$vssNorthHi) m3u=($m3u_bottom..$m3u_top) m4=($m4_bottom..$m4_top) m3l=($m3l_bottom..$m3l_top)"

    set nv 0
    set vdd_minX ""
    set vdd_maxX ""
    foreach r $rows {
        lassign $r y1 y2 x1 x2
        set cx [expr {int(($x1 + $x2) * 0.5 * $sc)}]
        set lo [expr {$cx - $bw / 2}]
        set hi [expr {$cx + $bw / 2}]
       
        set m4_shift [expr {int(0.4 * $dbu)}]
        set m4_lo [expr {$lo - $m4_shift}]
        set m4_hi [expr {$hi - $m4_shift}]
        odb::dbSBox_create $sw $m2 $lo $m2_land_bottom $hi $die_y2 "STRIPE"
        odb::dbSBox_create $sw $m3 $lo $m3u_bottom $hi $m3u_top "STRIPE"
        odb::dbSBox_create $sw $m4 $m4_lo $m4_bottom $m4_hi $m4_top "STRIPE"
        odb::dbSBox_create $sw $m3 $lo $m3l_bottom $hi $m3l_top "STRIPE"
        odb::dbSBox_create $sw $colv  $cx $via_top_y "STRIPE"
        odb::dbSBox_create $sw $colv3 $cx $via3_top_y "STRIPE"
        odb::dbSBox_create $sw $colv3 $cx $via3_bottom_y "STRIPE"
        incr nv 3
        if {$vdd_minX eq "" || $lo < $vdd_minX} { set vdd_minX $lo }
        if {$vdd_maxX eq "" || $hi > $vdd_maxX} { set vdd_maxX $hi }
    }
    puts "\[INFO\] power-bridge: VDD  [llength $rows] bridges, $nv via stacks (north edge, jumps over VSS ring via Metal4)"
    set m3_bottom_y $m3l_bottom

    set margin2 [expr {int(0.5 * $dbu)}]
    set vddBxLo [expr {$vdd_minX - $margin2}]
    set vddBxHi [expr {$vdd_maxX + $margin2}]
    set vddByLo [expr {$m3_bottom_y - $margin2}]
    set vddByHi $die_y2
    if {$vddBxLo < 0} { set vddBxLo 0 }
    if {$vddBxHi > $die_x2} { set vddBxHi $die_x2 }
    odb::dbBlockage_create $block $vddBxLo $vddByLo $vddBxHi $vddByHi
    odb::dbObstruction_create $block $m3 $vdd_minX $m3u_bottom $vdd_maxX $m3u_top
    odb::dbObstruction_create $block $m4 $vdd_minX $m4_bottom  $vdd_maxX $m4_top
    odb::dbObstruction_create $block $m3 $vdd_minX $m3l_bottom $vdd_maxX $m3l_top
    odb::dbObstruction_create $block $m2 $vdd_minX $m2_land_bottom $vdd_maxX $die_y2
    puts "\[INFO\] power-bridge: VDD blockage/obstruction (restored, covers full M4 jump) ($vddBxLo,$vddByLo)-($vddBxHi,$vddByHi)"
}

if {[info commands pdngen] ne "" && [info commands _pg_pdngen_real] eq ""} {
    rename pdngen _pg_pdngen_real
    proc pdngen {args} {
        set rc [uplevel 1 [list _pg_pdngen_real {*}$args]]
        if {[catch {_pg_build_power_bridges} emsg]} {
            puts stderr "\[ERROR\] power-bridge builder failed: $emsg"
            puts stderr $::errorInfo
        }
        if {[catch {_pg_avoid_routing_trouble_zone} emsg2]} {
            puts stderr "\[ERROR\] trouble-zone blockage failed: $emsg2"
            puts stderr $::errorInfo
        }
        return $rc
    }
}
