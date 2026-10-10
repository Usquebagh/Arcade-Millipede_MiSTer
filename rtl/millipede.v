//============================================================================
//  Atari Millipede (1982) - game board 038874, schematic package SP-217
//
//  Single clock domain: clk is the 12.096 MHz master clock (Y1 on sheet 3B).
//  Every board flip-flop is modelled on its real clock edge, expressed as a
//  clock enable decoded from the horizontal counter (pre-edge values), so the
//  timing relationships of the original TTL are preserved.
//
//  Chip references (e.g. "7H", "9B") are board locations from SP-217.
//============================================================================

`timescale 1 ps / 1 ps
`default_nettype none

module millipede
(
	input  wire        clk,           // 12.096 MHz
	input  wire        reset,
	input  wire        pause,

	// ROM download: 0000-3FFF program, 4000-47FF 107 (5R), 4800-4FFF 106 (5P),
	// 5000-50FF sync PROM 136001-213 (7E)
	input  wire [15:0] dn_addr,
	input  wire  [7:0] dn_data,
	input  wire        dn_wr,

	// Player controls, active high
	input  wire        coin_l,
	input  wire        coin_r,
	input  wire        coin_aux,
	input  wire        slam,
	input  wire        self_test,
	input  wire        upright,       // cabinet switch: 1 = upright
	input  wire        start1,
	input  wire        start2,
	input  wire        fire1,
	input  wire        fire2,
	input  wire  [3:0] joy1,          // {up, down, left, right}
	input  wire  [3:0] joy2,
	input  wire        tb1_hclk, tb1_hdir, tb1_vclk, tb1_vdir,
	input  wire        tb2_hclk, tb2_hdir, tb2_vclk, tb2_vdir,

	// Option switches, values as the CPU reads them (MAME port values)
	input  wire  [7:0] dsw0,          // 5D, read through POKEY 4D ALLPOT ($0408)
	input  wire  [7:0] dsw1,          // 5B, read through POKEY 4B ALLPOT ($0808)
	input  wire  [7:0] dsw2,          // 8P, loaded into the trackball counters

	input  wire        palette_mame,  // 1: MAME colour weights, 0: board DAC model
	input  wire        audio_board,   // 1: board output stage, 0: MAME linear mix

	// Video
	output reg   [7:0] red,
	output reg   [7:0] green,
	output reg   [7:0] blue,
	output reg         hsync,
	output reg         vsync,
	output reg         hblank,
	output reg         vblank,
	output wire        ce_pix,

	// Audio
	output wire signed [15:0] audio,

	output wire  [4:1] led,           // {start2, start1, coin R, coin L}
	output wire        flip,          // VIDROT: picture turned for player 2 (cocktail)

	// EAROM (high score table) access for the hiscore/NVRAM system
	input  wire  [5:0] hs_address,
	input  wire  [7:0] hs_data_in,
	output wire  [7:0] hs_data_out,
	input  wire        hs_write
);

//----------------------------------------------------------------------------
// Horizontal sync chain (sheet 3B, 6D/6E/6F LS163)
//
// hc[0] = 6MHZ, hc[1] = 1H ... hc[9] = 256H.  The chain counts 128H..511H:
// hc runs 0x100..0x3FF, 768 master clocks = 384 pixels per line.
//----------------------------------------------------------------------------
reg  [9:0] hc = 10'h100;
wire       h1   = hc[1];
wire       h2   = hc[2];
wire       h4   = hc[3];
wire       h256 = hc[9];
wire [8:0] H    = hc[9:1];

// Clock-edge enables (true when this clk edge is the named edge)
wire e6r   = ~hc[0];                       // 6MHZ rising
wire e6f   =  hc[0];                       // 6MHZ falling
wire e1hf  = (hc[1:0] == 2'b11);           // 1H falling (= /1H rising)
wire e2hr  = (hc[2:0] == 3'b011);          // 2H rising
wire e4hr  = (hc[3:0] == 4'b0111);         // 4H rising
wire e4hf  = (hc[3:0] == 4'b1111);         // 4H falling, end of an 8-pixel slot
wire eline = (hc == 10'h3FF);              // 256H falling, start of a line

wire pload_n = ~(h1 & h2 & h4);            // 5F LS10

assign ce_pix = e6f;

always @(posedge clk)
	hc <= eline ? 10'h100 : hc + 10'd1;

// 2HD (8H LS74) and 4HD (7H LS109): 2H/4H re-timed on 6MHZ rising
reg hd2, hd4;
always @(posedge clk)
	if (e6r) begin
		hd2 <= h2;
		hd4 <= h4;
	end

// 256HD / 256H2D (10D LS74), VBLANKD (9H): clocked once per slot
reg h256d, h256d2, vblankd;
always @(posedge clk)
	if (e4hf) begin
		h256d  <= h256;
		h256d2 <= h256d;
		vblankd <= vblank_r;
	end

//----------------------------------------------------------------------------
// Vertical sync chain (sheet 3B, 7C/7D LS163, sync PROM 7E, latch 8E)
//----------------------------------------------------------------------------
reg  [7:0] V;
reg  [3:0] vprom_r;                        // {vblank, vreset, -, vsync}
wire       vblank_r = vprom_r[3];
wire [3:0] vprom_q;

wire       prom_wr = dn_wr && dn_addr[15:8] == 8'h50;
wire [7:0] vprom_a = {vblank_r, V[7], V[6], V[5], V[3:0]};

dpram #(8,4) sync_prom
(
	.clock_a(clk), .enable_a(1'b1), .wren_a(prom_wr),
	.address_a(dn_addr[7:0]), .data_a(dn_data[3:0]), .q_a(),
	.clock_b(clk), .enable_b(1'b1), .wren_b(1'b0),
	.address_b(vprom_a), .data_b(4'd0), .q_b(vprom_q)
);

always @(posedge clk)
	if (eline) begin
		vprom_r <= vprom_q;
		V <= vprom_r[2] ? 8'd0 : V + 8'd1;
	end

// HSYNC (8H/9H LS74)
reg hs_ff, hsync_r;
always @(posedge clk) begin
	if (h256) hs_ff <= 1'b1;
	else if (hc[6:0] == 7'b0111111) hs_ff <= H[6];        // 32H rising
	if (hs_ff) hsync_r <= 1'b0;
	else if (hc[4:0] == 5'b01111) hsync_r <= H[5];        // 8H rising
end

//----------------------------------------------------------------------------
// Microprocessor (sheet 4A)
//----------------------------------------------------------------------------
wire [15:0] ab;
wire  [7:0] cpu_dout;
wire        cpu_we;
wire        rw_n = ~cpu_we;
reg   [7:0] cpu_din;           // data bus, combinational from ab
reg   [7:0] cpu_di;            // latched at the end of each CPU cycle
reg         phi0 = 1'b0;
reg         irq_ff;
wire        cpu_reset;

// Address decoders (1B LS42, 3E LS139, 4H LS139, 3F LS42); A15 is not decoded
wire mos    = ab[14:12] == 3'b000;
wire scram  = ab[14:12] == 3'b001;
wire io     = ab[14:12] == 3'b010;
wire rom    = ab[14];
wire zram   = mos && ab[11:10] == 2'b00;
wire ios0   = mos && ab[11:10] == 2'b01;     // POKEY 4D
wire ios1   = mos && ab[11:10] == 2'b10;     // POKEY 4B
wire inputs = io  && ab[11:10] == 2'b00;
wire outputs= io  && ab[11:10] == 2'b01;
wire in0    = inputs && ab[5:4] == 2'b00;    // $2000/$2001
wire in1    = inputs && ab[5:4] == 2'b01;    // $2010/$2011
wire earomrd= inputs && ab[5:4] == 2'b11;    // $2030
wire coloram  = outputs && ab[9:7] == 3'd1;  // $2480
wire out0     = outputs && ab[9:7] == 3'd2;  // $2500
wire irqres   = outputs && ab[9:7] == 3'd4;  // $2600
wire watchdog = outputs && ab[9:7] == 3'd5;  // $2680
wire earomcon = outputs && ab[9:7] == 3'd6;  // $2700
wire earomwr  = outputs && ab[9:7] == 3'd7;  // $2780

// CPU clock (7H LS109): J = SCRAM | 4HD, /K = /2HD, clocked by /1H.
// Normally phi0 follows 2H; a playfield access holds phi0 low until 4HD.
wire phi_j  = ~scram | hd4;
wire phi_kn = ~hd2;
reg  phi0_next;
always @* begin
	case ({phi_j, phi_kn})
		2'b00: phi0_next = 1'b0;
		2'b01: phi0_next = phi0;
		2'b10: phi0_next = ~phi0;
		2'b11: phi0_next = 1'b1;
	endcase
end

// One CPU cycle ends on each phi0 falling edge
wire cpu_end = e1hf & phi0 & ~phi0_next;
wire cpu_ce  = cpu_end & ~pause & ~cpu_reset;
wire cpu_wr  = cpu_ce & ~rw_n;

always @(posedge clk)
	if (e1hf) phi0 <= phi0_next;

// 6502 (Arlet Ottens core, RDY used as the cycle enable).  The core takes the
// data for a cycle's address during the following cycle, so the bus is
// latched at the end of every cycle.
always @(posedge clk)
	if (cpu_ce) cpu_di <= cpu_din;

cpu cpu
(
	.clk(clk),
	.reset(cpu_reset),
	.AB(ab),
	.DI(cpu_di),
	.DO(cpu_dout),
	.WE(cpu_we),
	.IRQ(irq_ff),
	.NMI(1'b0),
	.RDY(cpu_ce)
);

// IRQ (3H LS74): D = 32V clocked by 16V, cleared by IRQRES
reg v16_d;
always @(posedge clk) begin
	v16_d <= V[4];
	if (cpu_reset || (cpu_wr && irqres)) irq_ff <= 1'b0;
	else if (V[4] & ~v16_d) irq_ff <= V[5];
end

// Power-on reset and watchdog (9F LS90 counting VBLANK, reset by WATCHDOG).
// RESET holds the counter at 9, so the CPU is released on the next VBLANK.
reg [3:0] wd_cnt = 4'd9;
reg       vblank_d;
always @(posedge clk) begin
	vblank_d <= vblank_r;
	if (reset) wd_cnt <= 4'd9;
	else if (cpu_wr && watchdog) wd_cnt <= 4'd0;
	else if (vblank_r & ~vblank_d) wd_cnt <= (wd_cnt == 4'd9) ? 4'd0 : wd_cnt + 4'd1;
end
assign cpu_reset = wd_cnt[3];

//----------------------------------------------------------------------------
// Program memory (sheet 4B) and RAM
//----------------------------------------------------------------------------
wire [7:0] rom_q, ram_q;

dpram #(14,8) prog_rom
(
	.clock_a(clk), .enable_a(1'b1), .wren_a(dn_wr && dn_addr[15:14] == 2'b00),
	.address_a(dn_addr[13:0]), .data_a(dn_data), .q_a(),
	.clock_b(clk), .enable_b(1'b1), .wren_b(1'b0),
	.address_b(ab[13:0]), .data_b(8'd0), .q_b(rom_q)
);

dpram #(10,8) ram
(
	.clock_a(clk), .enable_a(1'b1), .wren_a(cpu_wr && zram),
	.address_a(ab[9:0]), .data_a(cpu_dout), .q_a(ram_q),
	.clock_b(clk), .enable_b(1'b0), .wren_b(1'b0),
	.address_b(10'd0), .data_b(8'd0), .q_b()
);

//----------------------------------------------------------------------------
// Output latch (12E LS259, $2500-$2507, data bit 7)
//----------------------------------------------------------------------------
reg [7:0] outlatch;
always @(posedge clk)
	if (cpu_reset) outlatch <= 8'd0;
	else if (cpu_wr && out0) outlatch[ab[2:0]] <= cpu_dout[7];

wire tben     = outlatch[5];
wire vidrot   = outlatch[6];
wire cntrlsel = outlatch[7];
assign led  = outlatch[4:1];
assign flip = vidrot;

//----------------------------------------------------------------------------
// Playfield memory (sheet 5A): 256 words x 32 bits (2101 x 8).
// CPU byte lane = AB5..AB4, word = {AB9..AB6, AB3..AB0}.
//----------------------------------------------------------------------------
wire [7:0] pfa = h256 ? {V[7:4], H[6:3]} : {4'hF, H[6:3]};
wire [31:0] pfd;
wire [7:0]  pf_cpu_q[0:3];

genvar lane;
generate
	for (lane = 0; lane < 4; lane = lane + 1) begin : pf_lane
		dpram #(8,8) pf_ram
		(
			.clock_a(clk), .enable_a(1'b1),
			.wren_a(cpu_wr && scram && ab[5:4] == lane),
			.address_a({ab[9:6], ab[3:0]}), .data_a(cpu_dout), .q_a(pf_cpu_q[lane]),
			.clock_b(clk), .enable_b(1'b1), .wren_b(1'b0),
			.address_b(pfa), .data_b(8'd0), .q_b(pfd[lane*8 +: 8])
		);
	end
endgenerate

// Playfield code multiplexer (3J-3M LS153): video lane = {8V, 128H} on the
// playfield, lane 0 (picture) in the motion-object area.
wire [1:0] pf_lane_sel = h256 ? {V[3], H[7]} : 2'b00;
wire [7:0] pf_code = pfd[pf_lane_sel*8 +: 8];

//----------------------------------------------------------------------------
// Motion object control (sheet 5B) and picture latches
//----------------------------------------------------------------------------
reg  [7:0] pic;            // 4R LS273 (4H)
reg        pic7d, pic6d;   // 9J LS74 (/4H)
reg  [3:0] msum;           // 6L LS174 (4H)
reg        vmatch_n;
reg  [7:0] hpos;           // 5E LS273 (4H)
reg  [7:0] mocol_k;        // 7K LS273 (4H)
reg  [7:0] mocol_j;        // 7J LS273 (/4H)

wire [7:0] vsum = V + pfd[15:8];           // 6H/6J LS83

always @(posedge clk) begin
	if (e4hr) begin
		pic      <= pf_code;
		msum     <= vsum[3:0];
		vmatch_n <= ~&vsum[7:4];
		hpos     <= pfd[23:16];
		mocol_k  <= pfd[31:24];
	end
	if (e4hf) begin
		mocol_j <= mocol_k;
		pic7d   <= pic[7];
		pic6d   <= pic[6];
	end
end

// 6M / 7N LS157, 6N / 7P LS86
wire [3:0] m_row  = h256 ? {pic[0], V[2:0]} : msum;
wire       vflip  = (h256 ? 1'b0 : pic[7]) ^ vidrot;
wire       horrot = (h256 ? 1'b0 : pic[6]) ^ vidrot;
wire       match_n= h256 ? 1'b0 : vmatch_n;
wire       mga10  = h256 ? pic[6] : pic[0];
wire [3:0] mga    = {m_row[3] ^ (vflip & ~h256), m_row[2:0] ^ {3{vflip}}};

wire [10:0] gfx_a = {mga10, h256, pic[5:1], mga};
wire  [7:0] gfx0_q, gfx1_q;

// 5R (136013-107) -> AREA0, 5P (136013-106) -> AREA1
dpram #(11,8) gfx_rom0
(
	.clock_a(clk), .enable_a(1'b1), .wren_a(dn_wr && dn_addr[15:11] == 5'b01000),
	.address_a(dn_addr[10:0]), .data_a(dn_data), .q_a(),
	.clock_b(clk), .enable_b(1'b1), .wren_b(1'b0),
	.address_b(gfx_a), .data_b(8'd0), .q_b(gfx0_q)
);

dpram #(11,8) gfx_rom1
(
	.clock_a(clk), .enable_a(1'b1), .wren_a(dn_wr && dn_addr[15:11] == 5'b01001),
	.address_a(dn_addr[10:0]), .data_a(dn_data), .q_a(),
	.clock_b(clk), .enable_b(1'b1), .wren_b(1'b0),
	.address_b(gfx_a), .data_b(8'd0), .q_b(gfx1_q)
);

function [7:0] rev8(input [7:0] d);
	rev8 = {d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7]};
endfunction

// Picture shift registers 7R / 5L (LS166), loaded on PLOAD at 6MHZ rising.
// 6P/6R and 5M/5N select the bit order (HORROT); /MATCH blanks them.
reg [7:0] sh0, sh1;
always @(posedge clk)
	if (e6r) begin
		if (!pload_n) begin
			sh0 <= match_n ? 8'd0 : (horrot ? rev8(gfx0_q) : gfx0_q);
			sh1 <= match_n ? 8'd0 : (horrot ? rev8(gfx1_q) : gfx1_q);
		end else begin
			sh0 <= {sh0[6:0], 1'b0};
			sh1 <= {sh1[6:0], 1'b0};
		end
	end

wire [1:0] area = {sh1[7], sh0[7]};

//----------------------------------------------------------------------------
// Horizontal position counter (8D/8C LS163) and line buffer (8B 93422)
//----------------------------------------------------------------------------
reg  [7:0] lb_addr;
reg  [3:0] lbuf [0:255];     // {MOCB1, MOCB0, GRY1, GRY0}
reg  [7:0] b9;               // 9B LS273 (/6MHZ): {MOCB, GRY, AREA1D, AREA0D, -, -}
wire [1:0] mocb_d = b9[7:6];
wire [1:0] gry_d  = b9[5:4];
wire [1:0] area_d = b9[3:2];

// Motion object colour selectors (8J / 7B S153), disabled by 256HD
reg  [1:0] gry_sel;
always @* begin
	case (area_d)
		2'd0: gry_sel = gry_d;
		2'd1: gry_sel = mocol_j[1:0];
		2'd2: gry_sel = mocol_j[3:2];
		2'd3: gry_sel = mocol_j[5:4];
	endcase
end
wire [1:0] mocb_sel = (area_d == 2'd0) ? mocb_d : mocol_j[7:6];
wire [3:0] lb_wdata = h256d ? 4'd0 : {mocb_sel, gry_sel};

wire lb_load = ~pload_n & ~h256;               // 9D: LD
wire lb_clr  = ~pload_n &  h256 & ~h256d;      // 9D/10E: C

always @(posedge clk) begin
	if (e6r) begin
		lbuf[lb_addr] <= lb_wdata;                // /WE = 6MHZ low
		if (lb_clr) lb_addr <= 8'd0;
		else if (lb_load) lb_addr <= hpos;
		else lb_addr <= lb_addr + 8'd1;
	end
	if (e6f) b9 <= {lbuf[lb_addr], area, 2'b00};
end

//----------------------------------------------------------------------------
// Colour memory (sheet 6A): 10A/10B/11B/11C 82S25, 32 x 8, output inverted.
// $2480-$248F playfield ("stamp") colours, $2490-$249F motion object colours.
//----------------------------------------------------------------------------
wire       mo_sel = |gry_d & h256 & h256d2;     // 9D / 9E
wire [4:0] acr    = mo_sel ? {1'b1, mocb_d, gry_d} : {1'b0, pic7d, pic6d, area_d};
reg  [7:0] cram [0:31];
always @(posedge clk)
	if (cpu_wr && coloram) cram[ab[4:0]] <= cpu_dout;

// Colour output latch (12A LS273, /6MHZ), cleared during blanking
// The exact HBLANK inputs of 9B/9D are not legible on the scan; the window is
// 256HD, which puts the first playfield column on the first displayed pixel.
reg  [7:0] col_out;
always @(posedge clk)
	if (e6f) begin
		col_out <= (h256d & ~vblankd) ? ~cram[acr] : 8'd0;
		// Output blanking for the scaler: exactly 256 pixels per line, and
		// VBLANK only changes at the start of horizontal blanking
		hblank  <= ~h256d;
		if (~h256d & ~hblank) vblank <= vblankd;
		hsync   <= hsync_r;
		vsync   <= vprom_r[0];
	end

// Colour DAC.  MAME weights, or the board network: 470/1k/1.8k into a 6.8k
// pull-up to +15V, with green's low bit and part of blue tied to +5V.
wire [2:0] r3 = col_out[7:5];
wire [1:0] g2 = col_out[4:3];
wire [2:0] b3 = col_out[2:0];

function [7:0] w3(input [2:0] v);
	w3 = (v[0] ? 8'h21 : 8'h00) + (v[1] ? 8'h47 : 8'h00) + (v[2] ? 8'h97 : 8'h00);
endfunction

wire [7:0] dac_r, dac_g, dac_b;
millipede_dac dac(.r(r3), .g(g2), .b(b3), .r8(dac_r), .g8(dac_g), .b8(dac_b));

always @(posedge clk) begin
	red   <= palette_mame ? w3(r3)         : dac_r;
	green <= palette_mame ? w3({g2, 1'b0}) : dac_g;
	blue  <= palette_mame ? w3(b3)         : dac_b;
end

//----------------------------------------------------------------------------
// Trak-Ball input (sheet 6B): 10P LS157 selects player by CNTRLSEL, 10R LS74
// latches direction, 9P/8N LS191 count.  While TBEN is low the counters are
// held loaded with option switch bank 8P.
//----------------------------------------------------------------------------
wire tb_hclk = cntrlsel ? tb2_hclk : tb1_hclk;
wire tb_hdir = cntrlsel ? tb2_hdir : tb1_hdir;
wire tb_vclk = cntrlsel ? tb2_vclk : tb1_vclk;
wire tb_vdir = cntrlsel ? tb2_vdir : tb1_vdir;

reg  [3:0] tb_hcnt, tb_vcnt;
reg        hdir, vdir, tb_hclk_d, tb_vclk_d;
always @(posedge clk) begin
	tb_hclk_d <= tb_hclk;
	tb_vclk_d <= tb_vclk;
	if (tb_hclk & ~tb_hclk_d) begin
		hdir <= tb_hdir;
		tb_hcnt <= hdir ? tb_hcnt - 4'd1 : tb_hcnt + 4'd1;
	end
	if (tb_vclk & ~tb_vclk_d) begin
		vdir <= tb_vdir;
		tb_vcnt <= vdir ? tb_vcnt - 4'd1 : tb_vcnt + 4'd1;
	end
	if (!tben) begin
		tb_hcnt <= dsw2[3:0];
		tb_vcnt <= {1'b0, dsw2[6:4]};
	end
end

// Control panel (10L LS257), coin door (10K LS257), joystick (9M LS257)
wire [3:0] joy_sel = cntrlsel ? {joy2[2], joy2[3], joy2[0], joy2[1]} : joy1;
wire [7:0] in0_q = ab[0] ? {vdir, 1'b0,   ~start2, ~fire2, tb_vcnt}
                         : {hdir, vblank_r, ~start1, ~fire1, tb_hcnt};
wire [7:0] in1_q = ab[0] ? {~self_test, 1'b0, upright, 1'b1, ~joy_sel}
                         : {~coin_r, ~coin_l, ~coin_aux, ~slam, ~joy_sel};

//----------------------------------------------------------------------------
// High-score table (sheet 4B, ER2055 EAROM)
//----------------------------------------------------------------------------
reg  [5:0] earom_addr;
reg  [7:0] earom_in;
reg  [3:0] earom_ctrl;
wire [7:0] earom_out;

always @(posedge clk)
	if (reset) earom_ctrl <= 4'b0010;
	else if (cpu_wr) begin
		if (earomwr) begin
			earom_addr <= ab[5:0];
			earom_in   <= cpu_dout;
		end
		if (earomcon) earom_ctrl <= {cpu_dout[3:2], ~cpu_dout[1], cpu_dout[0]};
	end

dpram #(6,8) earom
(
	.clock_a(clk), .enable_a(earom_ctrl[3]), .wren_a(~earom_ctrl[1]),
	.address_a(earom_addr), .data_a(earom_ctrl[2] ? 8'h00 : earom_in), .q_a(earom_out),
	.clock_b(clk), .enable_b(1'b1), .wren_b(hs_write),
	.address_b(hs_address), .data_b(hs_data_in), .q_b(hs_data_out)
);

//----------------------------------------------------------------------------
// Audio (sheet 7A): two POKEYs clocked by PHI2B OR 2H, which is a steady 2H.
// Option switches 5D/5B are read through ALLPOT at $0408/$0808.
//----------------------------------------------------------------------------
wire       pokey_ce = e2hr & ~pause;
wire [7:0] pokey0_q, pokey1_q;
wire [3:0] p0c0, p0c1, p0c2, p0c3, p1c0, p1c1, p1c2, p1c3;

pokey pokey0
(
	.clk(clk), .enable_179(pokey_ce), .addr(ab[3:0]), .data_in(cpu_dout),
	.wr_en(cpu_wr && ios0), .reset_n(~cpu_reset),
	.keyboard_scan_enable(1'b0), .keyboard_scan(), .keyboard_response(2'b11),
	.pot_in(8'h00), .sio_in1(1'b1), .sio_in2(1'b1), .sio_in3(1'b1),
	.data_out(pokey0_q),
	.channel_0_out(p0c0), .channel_1_out(p0c1), .channel_2_out(p0c2), .channel_3_out(p0c3),
	.irq_n_out(), .sio_out1(), .sio_out2(), .sio_out3(),
	.sio_clockin_in(1'b1), .sio_clockin_out(), .sio_clockin_oe(), .sio_clockout(),
	.pot_reset()
);

pokey pokey1
(
	.clk(clk), .enable_179(pokey_ce), .addr(ab[3:0]), .data_in(cpu_dout),
	.wr_en(cpu_wr && ios1), .reset_n(~cpu_reset),
	.keyboard_scan_enable(1'b0), .keyboard_scan(), .keyboard_response(2'b11),
	.pot_in(8'h00), .sio_in1(1'b1), .sio_in2(1'b1), .sio_in3(1'b1),
	.data_out(pokey1_q),
	.channel_0_out(p1c0), .channel_1_out(p1c1), .channel_2_out(p1c2), .channel_3_out(p1c3),
	.irq_n_out(), .sio_out1(), .sio_out2(), .sio_out3(),
	.sio_clockin_in(1'b1), .sio_clockin_out(), .sio_clockin_oe(), .sio_clockout(),
	.pot_reset()
);

millipede_audio audio_out
(
	.clk(clk),
	.board(audio_board),
	.vol({p1c3, p1c2, p1c1, p1c0, p0c3, p0c2, p0c1, p0c0}),
	.out(audio)
);

//----------------------------------------------------------------------------
// CPU data bus
//----------------------------------------------------------------------------
always @* begin
	cpu_din = 8'hFF;
	if (rom)                             cpu_din = rom_q;
	else if (zram)                       cpu_din = ram_q;
	else if (ios0) cpu_din = (ab[3:0] == 4'h8) ? dsw0 : pokey0_q;
	else if (ios1) cpu_din = (ab[3:0] == 4'h8) ? dsw1 : pokey1_q;
	else if (scram)                      cpu_din = pf_cpu_q[ab[5:4]];
	else if (in0)                        cpu_din = in0_q;
	else if (in1)                        cpu_din = in1_q;
	else if (earomrd)                    cpu_din = earom_out;
end

endmodule
