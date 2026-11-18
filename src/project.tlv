\m5_TLV_version 1d --inlineGen --fmtFlatSignals: tl-x.org
\m5
   /**
   This template is for developing Tiny Tapeout designs using Makerchip.
   Verilog, SystemVerilog, and/or TL-Verilog can be used.
   Use of Tiny Tapeout Demo Boards (as virtualized in the VIZ tab) is supported.
   See the corresponding Git repository for build instructions.
   **/

   use(m5-1.0)  // See M5 docs in Makerchip IDE Learn menu.

   // ---SETTINGS---
   var(my_design, tt_um_stevehoover_pit_jumper)  /// Change tt_um_example to tt_um_<your-github-username>_<name-of-your-project>. (See README.md.)
   var(target, ASIC) /// Use "FPGA" for TT03 Demo Boards (without bidirectional I/Os).
   var(in_fpga, 1)   /// 1 to include the demo board visualization. (Note: Logic will be under /fpga_pins/fpga.)
   var(vga, 1)       /// 1 for a VGA design on the Tiny VGA Pmod (uo_out): drive R, G and B (all [1:0]; see tt_vga() in tiny_tapeout_lib.tlv)
                     /// Enables VGA features in Makerchip.
   var(vga_makerchip_scale, 1)
                     /// In Makerchip only, divide the VGA timing by this (e.g. 8 for 80x60), so whole frames fit in the
                     /// simulation (and its VIZ). Makerchip's TT VGA view then shows the small frame too.
   var(gamepad, 1)   /// 1 or 2: controllers on the Gamepad Pmod (ui_in[6:4]); read gamepad_up, etc. (see tt_gamepad()).
   var(debounce_inputs, 0)
                     /// Legal values:
                     ///   1: Provide synchronization and debouncing on all input signals.
                     ///   0: Don't provide synchronization and debouncing.
                     ///   m5_if_defined_as(MAKERCHIP, 1, 0, 1): Debounce unless in Makerchip.
   // --------------

   // If debouncing, your top module is wrapped within a debouncing module, so it has a different name.
   var(user_module_name, m5_if(m5_debounce_inputs, my_design, m5_my_design))
   var(debounce_cnt, m5_if_defined_as(MAKERCHIP, 1, 8'h03, 8'hff))
   // No TT lab outside of Makerchip.
   if_defined_as(MAKERCHIP, 1, [''], ['m5_set(in_fpga, 0)'])
   var(vga_scale, m5_if_defined_as(MAKERCHIP, 1, m5_vga_makerchip_scale, 1))  // (Read by the library.)
\SV
   // Include Tiny Tapeout Lab.
   m4_include_lib(['https://raw.githubusercontent.com/os-fpga/Virtual-FPGA-Lab/f18361f1ebbf39c6a910cfcee7b40bc1979360fd/tlv_lib/tiny_tapeout_lib.tlv'])

// Your design, in scope /_top (/fpga, in the TT demo board's FPGA, or /top), with the VGA and gamepad support its
// settings ask for.
\TLV my_design(/_top)
   m5_if(m5_vga, ['m5+tt_vga(0)'])  // 0: the pixel latency (see tt_vga()).
   m5_if(m5_gamepad, ['m5+tt_gamepad(/_top, m5_gamepad)'])

   //   #####  #            #   #      #   #  #####  ####   #####
   //     #    #            #   #      #   #  #      #   #  #
   //     #    #      ###   #   #      #####  ####   ####   ####
   //     #    #             # #       #   #  #      #  #   #
   //     #    #####          #        #   #  #####  #   #  #####
   //
   // Your TL-Verilog logic, if any, and optionally \viz_js (for TL-Verilog or Verilog logic), which overlays the
   // demo board's FPGA chip. Inputs: *ui_in[7:0], *uio_in[7:0] (the bits where uio_oe[7:0] is 0). From deeper
   // scopes, reach this one's signals as /_top$sig.

   // =====================================================================================================
   // Pit Jumper: parachute down an endless pit, viewed from above, steering with the gamepad's D-pad to stay
   // within its walls. After a crash, A or start restarts. A 640x480 VGA picture (tt_vga()) and the Gamepad
   // Pmod (tt_gamepad()).
   //
   // The pit is a series of circular openings (rings), evenly spaced in depth, with meandering centers. The
   // nearest 4 are drawn in perspective: a pixel shows the wall of the nearest ring whose opening it is
   // outside of (else the black abyss), shaded by that ring's depth (dithered between the 4 grays).
   //
   // Geometry, in "ray space": the pixel at offset g from the screen's center sees, at depth z, the lateral
   // position player + g * z / 32. It is within ring k's opening (radius 512, center a_k) if
   // |g * z_k / 32 - b_k| < 512, where b_k = a_k - player. Along a line, S_k = g.x * z_k / 32 is a running
   // sum, so each pixel needs just two comparisons per ring, with the line's span of the opening,
   // (Lo_k, Hi_k) = b_k.x -/+ sqrt(512^2 - V_k^2), where V_k = g.y * z_k / 32 - b_k.y. These are computed
   // for the next line during horizontal blanking, with a square-root table. Depths: z_k = z0 + 64k, with z0 in
   // [16, 80), so a ring's radius on screen (16384 / z) grows to 1024 pixels before it passes.
   // The game state changes once per frame, as vertical blanking starts ($step).
   // =====================================================================================================
   $reset = *reset;
   $step = $line_end && $Vpos == 10'd479;
   $restart = $reset || ($Crashed && (/gamepad[0]$start || /gamepad[0]$a));
   $play = $step && ! $Crashed;

   // ---- Falling ----
   // z0, the nearest ring's depth, in 1/16ths. As it passes 16, that ring passes the player ($pass), and
   // the next becomes the nearest. Each level of 512 rings falls faster.
   $speed[5:0] = 6'd12 + {1'b0, $Level, $Ring[8:6]};
   $z_next[10:0] = $Depth - {5'b0, $speed};
   $pass = $z_next < 11'd256;
   $Depth[10:0] <= $restart ? 11'd1279 : ! $play ? $RETAIN : $pass ? $z_next + 11'd1024 : $z_next;
   $z0[15:0] = {9'b0, $Depth[10:4]};
   // Rings passed (the depth meter; its low 8 bits identify the nearest ring), and levels completed.
   $Ring[8:0] <= $restart ? 9'd0 : $play && $pass ? $Ring + 9'd1 : $RETAIN;
   $Level[1:0] <= $restart ? 2'd0 :
                  $play && $pass && $Ring == 9'd511 && $Level != 2'd3 ? $Level + 2'd1 : $RETAIN;
   // A crash: passing a ring with the player (the screen's center pixel) outside its opening.
   $CenterWall <= $Hpos == 10'd320 && $Vpos == 10'd240 ? ! /ring[0]$inside : $RETAIN;
   $Crashed <= $restart ? 1'b0 : $play && $pass && $CenterWall ? 1'b1 : $RETAIN;

   // ---- The player ----
   // Position (x, y), in ray-space units (mod 2048), starting at the first ring's center. The D-pad sets the
   // velocity: 12 units per frame (an opening's radius is 512).
   /axis[1:0]
      $neg = #axis ? /_top/gamepad[0]$up : /_top/gamepad[0]$left;
      $pos = #axis ? /_top/gamepad[0]$down : /_top/gamepad[0]$right;
      $Pos[10:0] <= /_top$restart ? (#axis ? 11'd892 : 11'd256) :
                    ! /_top$play || $pos == $neg ? $RETAIN :
                    $pos ? $Pos + 11'd12 : $Pos - 11'd12;

   // ---- Ring spans for the next line, computed during horizontal blanking ----
   // Pixels 640-647: for each ring k, two cycles: V_k and the opening's half-width (y), then its span (x).
   $span_cyc = $Hpos[9:3] == 7'b1010000;
   $k[1:0] = $Hpos[2:1];
   $x_cyc = $Hpos[0];
   // Ring centers: sums of two triangle waves of the ring's index, n: 8 * tri(17n) + 4 * tri(5n + 64) for x,
   // and the same with phases 80 and 128 later for y.
   $n[7:0] = $Ring[7:0] + {6'b0, $k};
   $ph1[7:0] = {$n[7:4] + $n[3:0] + ($x_cyc ? 4'd0 : 4'd5), $n[3:0]};
   $ph2[7:0] = {$n[7:2] + $n[5:0] + ($x_cyc ? 6'd16 : 6'd48), $n[1:0]};
   $tri1[6:0] = $ph1[7] ? ~$ph1[6:0] : $ph1[6:0];
   $tri2[6:0] = $ph2[7] ? ~$ph2[6:0] : $ph2[6:0];
   $center[10:0] = {{1'b0, $tri1, 1'b0} + {2'b0, $tri2}, 2'b0};
   $b[10:0] = $center - ($x_cyc ? /axis[0]$Pos : /axis[1]$Pos);  // b_k.x or b_k.y (signed)
   // V_k, from $Gy = g.y * z0 for the next line.
   $Gy[15:0] <= $reset || ($line_end && $Vpos == 10'd523) ? ($z0 << 4) - ($z0 << 8) :  // -240 * z0, for line 0
                $line_end ? $Gy + $z0 : $RETAIN;
   $gy[11:0] = $Vpos == 10'd524 ? -12'd240 : {2'b0, $Vpos} - 12'd239;  // g.y of the next line
   $gy2k[11:0] = $k == 2'd0 ? 12'd0 :
                 $k == 2'd1 ? $gy << 1 :
                 $k == 2'd2 ? $gy << 2 :
                              ($gy << 1) + ($gy << 2);
   // (12 bits suffice: |V_k| < 3072 in visible lines, so it doesn't wrap into (-512, 512).)
   $vy[11:0] = {$Gy[15], $Gy[15:5]} + $gy2k - {$b[10], $b};
   // The half-width, sqrt(512^2 - V_k^2) (from a table, for |V_k| / 4), or 0 if the line misses the opening.
   $u[6:0] = $vy[8:2] ^ {7{$vy[11]}};  // |V_k| / 4 (about)
   $miss = $vy[11:9] != {3{$vy[11]}};
   $Width[8:0] <= $span_cyc && ! $x_cyc ? ($miss ? 9'd0 : SQRT_TABLE[$u * 9 +: 9]) : $RETAIN;
   $lo[12:0] = {{2{$b[10]}}, $b} - {4'b0, $Width};
   $hi[12:0] = {{2{$b[10]}}, $b} + {4'b0, $Width};
   \SV_plus
      // floor(sqrt(512^2 - 1 - (4i + 3/2)^2)), 9 bits each, for i = 0..127.
      function automatic [128*9-1:0] sqrt_table();
         integer i, r;
         begin
            sqrt_table = '0;
            for (i = 0; i < 128; i = i + 1) begin
               r = 0;
               while ((r + 1) * (r + 1) <= 262141 - 16 * i * i - 12 * i) r = r + 1;
               sqrt_table[i * 9 +: 9] = r[8:0];
            end
         end
      endfunction
      localparam [128*9-1:0] SQRT_TABLE = sqrt_table();

   // ---- Pixels ----
   // S_0 = g.x * z0 / 32, from $Ax = g.x * z0. S_k = S_0 + 2k * g.x, the farther rings' at lower precision
   // (S_1 / 2, S_2 / 8, S_3 / 8), as they need less.
   $Ax[15:0] <= $line_end ? 16'd0 - ($z0 << 8) - ($z0 << 6) : $Ax + $z0;  // From -320 * z0.
   $gx[11:0] = {2'b0, $Hpos} - 12'd320;
   $s1[11:0] = {{2{$Ax[15]}}, $Ax[15:6]} + $gx;
   $s2[11:0] = {{4{$Ax[15]}}, $Ax[15:8]} + {$gx[11], $gx[11:1]};
   $s3[11:0] = $s2 + {{2{$gx[11]}}, $gx[11:2]};
   /ring[3:0]
      $write = /_top$span_cyc && /_top$x_cyc && /_top$k == #ring;
      $Lo[11:0] <= ! $write ? $RETAIN :
                   #ring == 0 ? /_top$lo[11:0] : #ring == 1 ? /_top$lo[12:1] : {{2{/_top$lo[12]}}, /_top$lo[12:3]};
      $Hi[11:0] <= ! $write ? $RETAIN :
                   #ring == 0 ? /_top$hi[11:0] : #ring == 1 ? /_top$hi[12:1] : {{2{/_top$hi[12]}}, /_top$hi[12:3]};
      $s[11:0] = #ring == 0 ? {/_top$Ax[15], /_top$Ax[15:5]} : #ring == 1 ? /_top$s1 : #ring == 2 ? /_top$s2 : /_top$s3;
      // Lo < S < Hi (signed).
      $inside = {~$s[11], $s[10:0]} > {~$Lo[11], $Lo[10:0]} && {~$s[11], $s[10:0]} < {~$Hi[11], $Hi[10:0]};
   // The visible wall (4: the abyss).
   $wall[2:0] = ! /ring[0]$inside ? 3'd0 : ! /ring[1]$inside ? 3'd1 :
                ! /ring[2]$inside ? 3'd2 : ! /ring[3]$inside ? 3'd3 : 3'd4;
   // Its shade, lighter as it nears: (272 - z) / 4 for its depth, z, capped at 63; 4 grays (bits 5:4), each
   // dithered toward the next (bits 3:0, against a 4x4 Bayer matrix).
   $shade_base[6:0] = 7'd68 - {2'b0, $Depth[10:6]};
   $shade_raw[6:0] = $shade_base - {$wall[1:0], 4'b0};
   $shade[5:0] = $shade_raw[6] ? 6'd63 : $shade_raw[5:0];
   $bayer[3:0] = {$Hpos[0] ^ $Vpos[0], $Vpos[0], $Hpos[1] ^ $Vpos[1], $Vpos[1]};
   $gray[1:0] = $shade[5:4] + {1'b0, $shade[5:4] != 2'd3 && $shade[3:0] > $bayer};
   // The depth meter, at x 16-31: the rings passed this level (1 pixel each, up to 480), colored by level.
   $meter = $Hpos[9:4] == 6'd1;
   $fill_height[8:0] = $Ring - {4'b0, $Ring[8:4]};
   $filled = {1'b0, $Vpos} + {2'b0, $fill_height} >= 11'd480;
   $level_color[5:0] = $Level == 2'd0 ? 6'b00_01_11 :
                       $Level == 2'd1 ? 6'b00_11_01 :
                       $Level == 2'd2 ? 6'b11_11_00 : 6'b11_00_11;
   // Colors (2 bits each of red, green and blue). The pit turns red after a crash.
   {*R, *G, *B} =
      $meter ? ($filled ? $level_color : 6'b10_10_10) :
      $wall == 3'd4 ? 6'b00_00_00 :
      $Crashed ? {$gray, 4'b0} :
      {$gray, $gray, $gray};

   /*
   // Connect Tiny Tapeout outputs
   // Uncomment outputs here, and comment/delete them at the end of this file.
   m5_if(m5_vga, ['// (uo_out is driven by tt_vga().)'], ['*uo_out = 8'b0;'])
   *uio_out = 8'b0;
   *uio_oe = 8'b0;
   */


// Set up the Tiny Tapeout lab environment.
\TLV tt_lab()
   /* verilator lint_off UNOPTFLAT */
   // Connect Tiny Tapeout I/Os to Virtual FPGA Lab.
   m5+tt_connections()

   // Instantiate the Virtual FPGA Lab.
   m5+board(/top, /fpga, 7, $, , my_design)
   // Label the switch inputs [0..7] (1..8 on the physical switch panel) (bottom-to-top).
   m5+tt_input_labels_viz(['"UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED", "UNUSED"'])

\SV


// ================================================
// A simple Makerchip Verilog test bench driving random stimulus.
// Modify the module contents to your needs.
// Only Makerchip's simulation defines MAKERCHIP, so other tools compiling this file (e.g. VGA Playground) skip it.
// ================================================

`ifdef MAKERCHIP
module top(input logic clk, input logic reset, input logic [31:0] cyc_cnt, output logic passed, output logic failed);
   // Tiny tapeout I/O signals.
   logic [7:0] ui_in, uio_in, uo_out, uio_out, uio_oe;
   logic [31:0] r;
   always @(posedge clk) r <= m5_if_defined_as(MAKERCHIP, 1, ['$urandom()'], ['0']);
   assign ui_in = r[7:0];
   assign uio_in = r[15:8];
   wire ena = 1'b1;  // High while the design is selected.
   wire rst_n = ! reset;

   /*
   // Or, to provide specific inputs at specific times...
   // BE SURE TO COMMENT THE ASSIGNMENT OF INPUTS ABOVE.
   // BE SURE TO DRIVE THESE ON THE B-PHASE OF THE CLOCK (ODD STEPS).
   // Driving on the rising clock edge creates a race with the clock that has unpredictable simulation behavior.
   initial begin
      #1  // Drive inputs on the B-phase.
         ui_in = 8'h0;
      #10 // Step past reset.
         ui_in = 8'hFF;
      // ...etc.
   end
   */

   // Instantiate the Tiny Tapeout module.
   m5_my_design tt(.*);

   assign passed = m5_if(m5_vga, ['cyc_cnt > m5_vga_sim_cycles'], ['cyc_cnt > 100']);
   assign failed = 1'b0;
endmodule
`endif

// Provide a wrapper module to debounce input signals if requested.
// TODO: The debounce module is conditioned for TT03.
m5_if(m5_debounce_inputs, ['m5_tt_top(m5_my_design)'])
// The above macro expands to multiple lines. We enter a new \SV block to reset line tracking.
\SV



// The Tiny Tapeout module.
module m5_user_module_name (
    input  wire [7:0] ui_in,    // Dedicated inputs - connected to the input switches
    output wire [7:0] uo_out,   // Dedicated outputs - connected to the 7 segment display
    input  wire [7:0] uio_in,   // IOs: Bidirectional Input path
    output wire [7:0] uio_out,  // IOs: Bidirectional Output path
    output wire [7:0] uio_oe,   // IOs: Bidirectional Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // will go high when the design is enabled
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

   wire reset = ! rst_n;

   // List all potentially-unused inputs to prevent warnings
   (* keep *) wire _unused = &{ena, clk, reset, ui_in, uio_in, 1'b1};

\TLV
   m5_if(m5_in_fpga, ['m5+tt_lab()'], ['m5+my_design(/top)'])
   m5_if(m5_vga, ['m5+tt_vga_viz()'])

\SV_plus

   //   #   #  #####  ####   ###  #       ###    ####      #   #  #####  ####   #####
   //   #   #  #      #   #   #   #      #   #  #          #   #  #      #   #  #
   //   #   #  ####   ####    #   #      #   #  #  ##      #####  ####   ####   ####
   //    # #   #      #  #    #   #      #   #  #   #      #   #  #      #  #   #
   //     #    #####  #   #  ###  #####   ###    ####      #   #  #####  #   #  #####
   //
   // Your (System)Verilog logic, if any. (Module interface above.)



   // Connect Tiny Tapeout outputs
   m5_if(m5_vga, ['// (uo_out is driven by tt_vga().)'], ['assign uo_out = 8'b0;'])
   assign uio_out = 8'b0;
   assign uio_oe = 8'b0;

endmodule
