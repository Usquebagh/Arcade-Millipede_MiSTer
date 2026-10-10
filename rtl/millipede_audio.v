//============================================================================
//  Millipede audio output stage (SP-217 sheet 7A)
//
//  Both POKEYs (4B, 4D) sink current from one node.  The node is fed from the
//  TL084 virtual +5V through R153 (220R) and has C63 (0.22uF) to ground; the
//  current through R153 is converted to voltage by 11F with R155 (1k).  A
//  0.22uF / 39k coupling (C37/R156, ~18.5Hz) follows before the two inverting
//  stages that drive AUD1/AUD2.
//
//  Each POKEY channel is a set of open-drain sinks weighted 90k/26.5k/8.05k/
//  3.4k (the values MAME uses for the chip), so the node is solved here as
//      C dV/dt = (5 - V)/220 - V*G
//  with G the sum of all eight channel conductances, stepped at 189 kHz.
//  This gives the real low-pass corner (3.3 kHz quiet, higher when loud),
//  the compression of large sums and the op-amp clipping.
//
//  board = 0 gives MAME's linear sum of the eight volumes instead.
//============================================================================

`timescale 1 ps / 1 ps
`default_nettype none

module millipede_audio
(
	input  wire        clk,     // 12.096 MHz
	input  wire        board,
	input  wire [31:0] vol,     // eight 4-bit channel volumes
	output reg  signed [15:0] out
);

// Channel conductance in 0.25uS units: bits 90k, 26.5k, 8.05k, 3.4k
function [10:0] gch(input [3:0] v);
	gch = (v[0] ? 11'd44 : 11'd0) + (v[1] ? 11'd151 : 11'd0) +
	      (v[2] ? 11'd497 : 11'd0) + (v[3] ? 11'd1176 : 11'd0);
endfunction

reg [5:0] div;
always @(posedge clk) div <= div + 6'd1;
wire step = (div == 6'd0);      // 189 kHz

reg  [13:0] g_q;                // total conductance, 0.25uS units
reg  [6:0]  lin;                // linear sum of volumes
integer k;
always @(posedge clk) begin
	g_q <= gch(vol[3:0])   + gch(vol[7:4])   + gch(vol[11:8])  + gch(vol[15:12]) +
	       gch(vol[19:16]) + gch(vol[23:20]) + gch(vol[27:24]) + gch(vol[31:28]);
	lin <= vol[3:0] + vol[7:4] + vol[11:8] + vol[15:12] +
	       vol[19:16] + vol[23:20] + vol[27:24] + vol[31:28];
end

// Node voltage, volts in Q16 (5V = 327680)
localparam [19:0] V5 = 20'd327680;
reg  [19:0] vq = V5;
wire [19:0] vdiff = V5 - vq;
wire [31:0] i1 = (vdiff * 32'd4545) >> 16;          // uA through R153
wire [33:0] i2 = (vq * {20'd0, g_q}) >> 18;         // uA into the POKEYs
wire signed [33:0] di = $signed({2'b00, i1}) - $signed(i2);
// dt/C = 5.29us / 0.22uF -> 24.05e-6 V/uA -> 1.576 Q16 units per uA
wire signed [33:0] dv = (di * 34'sd1614) >>> 10;

always @(posedge clk)
	if (step) vq <= vq + dv[19:0];

// 11F output: 1k * i1 above the +5V bias, clipping near the +15V rail
wire [15:0] i_clip = (i1 > 32'd8500) ? 16'd8500 : i1[15:0];
wire [31:0] board_x = (i_clip * 32'd985) >> 8;      // 8.5mA -> ~32700
wire [31:0] mame_x  = lin * 32'd273;                // 120 -> 32760
wire [15:0] x = board ? board_x[15:0] : mame_x[15:0];

// C37/R156 coupling: ~18.5 Hz high-pass (DC removal)
reg  signed [33:0] lp = 34'sd0;               // Q16
wire signed [33:0] x_q = $signed({2'b00, x, 16'd0});
always @(posedge clk)
	if (step) lp <= lp + ((x_q - lp) >>> 11);

wire signed [17:0] y = $signed({2'b00, x}) - lp[33:16];
always @(posedge clk)
	out <= (y > 18'sd32767) ? 16'sd32767 : (y < -18'sd32768) ? -16'sd32768 : y[15:0];

endmodule
