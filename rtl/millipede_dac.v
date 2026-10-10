//============================================================================
//  Millipede colour output (SP-217 sheet 6A, Q2-Q4 emitter followers)
//
//  Levels solved from the resistor network (470/1k/1.8k from 12A, 6.8k to
//  +15V, R51/R56/R62 1.8k to ground, R171/R172 1.8k to +5V on green/blue),
//  with the constant black offset of green and blue removed and each gun
//  normalised to full scale, as a monitor's cutoff and gain setup would do.
//============================================================================

`timescale 1 ps / 1 ps
`default_nettype none

module millipede_dac
(
	input  wire [2:0] r,
	input  wire [1:0] g,
	input  wire [2:0] b,
	output reg  [7:0] r8,
	output reg  [7:0] g8,
	output reg  [7:0] b8
);

always @* begin
	case (r)
		3'd0: r8 = 8'd0;   3'd1: r8 = 8'd27;  3'd2: r8 = 8'd59;  3'd3: r8 = 8'd100;
		3'd4: r8 = 8'd142; 3'd5: r8 = 8'd182; 3'd6: r8 = 8'd215; 3'd7: r8 = 8'd255;
	endcase
	case (g)
		2'd0: g8 = 8'd0;   2'd1: g8 = 8'd82;  2'd2: g8 = 8'd173; 2'd3: g8 = 8'd255;
	endcase
	case (b)
		3'd0: b8 = 8'd0;   3'd1: b8 = 8'd39;  3'd2: b8 = 8'd70;  3'd3: b8 = 8'd107;
		3'd4: b8 = 8'd148; 3'd5: b8 = 8'd187; 3'd6: b8 = 8'd216; 3'd7: b8 = 8'd255;
	endcase
end

endmodule
