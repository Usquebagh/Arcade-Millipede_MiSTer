//============================================================================
//  Arcade: Millipede (Atari, 1982)
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign FB_FORCE_BLANK = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];
wire       no_rotate = status[2] | direct_video;

assign VIDEO_ARX = (!ar) ? (no_rotate ? 12'd4 : 12'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (no_rotate ? 12'd3 : 12'd4) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"A.MILLIPED;;",
	"-;",
	"O[2],Orientation,Vertical,Horizontal;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"O[13:11],Trackball Speed,100%,200%,400%,25%,50%;",
	"O[8],Cabinet,Upright,Cocktail;",
	"-;",
	"DIP;",
	"-;",
	"O[27],Autosave Hiscores,Off,On;",
	"P1,Pause Options;",
	"P1O[25],Pause when OSD is open,On,Off;",
	"P1O[26],Dim video after 10s,On,Off;",
	"P2,Advanced;",
	"P2O[10],Colours,Board,MAME;",
	"P2O[14],Audio Output,Board,MAME;",
	"P2O[9],Self Test,Off,On;",
	"-;",
	"R[0],Reset;",
	"J1,Fire,Start 1P,Start 2P,Coin,Pause;",
	"jn,A,Start,Select,R,L;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys;   // 12.096 MHz: the board's master clock
wire pll_locked;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(),
	.outclk_1(),
	.outclk_2(clk_sys),
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [127:0] status;
wire   [1:0] buttons;
wire         forced_scandoubler;
wire         direct_video;
wire  [21:0] gamma_bus;

wire         ioctl_download;
wire         ioctl_upload;
wire         ioctl_upload_req;
wire         ioctl_wr;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire   [7:0] ioctl_din;
wire  [15:0] ioctl_index;

wire  [31:0] joy0, joy1;
wire  [24:0] ps2_mouse;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),
	.direct_video(direct_video),

	.buttons(buttons),
	.status(status),
	.status_menumask({direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),

	.joystick_0(joy0),
	.joystick_1(joy1),
	.ps2_mouse(ps2_mouse)
);

wire rom_download   = ioctl_download && ioctl_index == 0;
wire nvram_download = ioctl_download && ioctl_index == 4;
wire reset = RESET | status[0] | buttons[1] | rom_download | ~pll_locked;

// DIP switches from the MRA (ioctl index 254): byte 0 = 5D ($0408), byte 1 = 5B ($0808),
// byte 2 = 8P (trackball counters)
reg [7:0] sw[3];
always @(posedge clk_sys)
	if (ioctl_wr && ioctl_index == 254 && ioctl_addr[24:2] == 0 && ioctl_addr[1:0] != 3)
		sw[ioctl_addr[1:0]] <= ioctl_dout;

////////////////////   INPUTS   ///////////////////

wire [31:0] joy = joy0 | joy1;
wire m_fire1  = joy0[4] | ps2_mouse[0];
wire m_fire2  = joy1[4] | ps2_mouse[0];
wire m_start1 = joy[5];
wire m_start2 = joy[6];
wire m_coin   = joy[7];
wire m_pause  = joy[8];

// Mouse as Trak-Ball; both players share it (the board selects the active one)
wire tb_vdir, tb_vclk, tb_hdir, tb_hclk;
trackball trackball
(
	.clk(clk_sys),
	.flip(1'b0),
	.mouse_speed(status[13:11]),
	.ps2_mouse(ps2_mouse),
	.v_dir(tb_vdir),
	.v_clk(tb_vclk),
	.h_dir(tb_hdir),
	.h_clk(tb_hclk)
);

////////////////////   CORE   ///////////////////

wire [7:0] r, g, b;
wire       hs, vs, hbl, vbl, ce_pix, flip;
wire signed [15:0] audio;
wire       pause_cpu;
wire [23:0] rgb_out;
wire [5:0] hs_address;
wire [7:0] hs_data_out;
wire       hs_pause;

millipede millipede
(
	.clk(clk_sys),
	.reset(reset),
	.pause(pause_cpu),

	.dn_addr(ioctl_addr[15:0]),
	.dn_data(ioctl_dout),
	.dn_wr(ioctl_wr & rom_download),

	.coin_l(m_coin),
	.coin_r(1'b0),
	.coin_aux(1'b0),
	.slam(1'b0),
	.self_test(status[9]),
	.upright(~status[8]),
	.start1(m_start1),
	.start2(m_start2),
	.fire1(m_fire1),
	.fire2(m_fire2),
	.joy1(joy0[3:0]),
	.joy2(joy1[3:0]),
	// Direction sense as in the Centipede core (same counter hardware and axes)
	.tb1_hclk(tb_hclk), .tb1_hdir(~tb_hdir), .tb1_vclk(tb_vclk), .tb1_vdir(~tb_vdir),
	.tb2_hclk(tb_hclk), .tb2_hdir(~tb_hdir), .tb2_vclk(tb_vclk), .tb2_vdir(~tb_vdir),

	.dsw0(sw[0]),
	.dsw1(sw[1]),
	.dsw2(sw[2]),

	.palette_mame(status[10]),
	.audio_board(~status[14]),

	.red(r),
	.green(g),
	.blue(b),
	.hsync(hs),
	.vsync(vs),
	.hblank(hbl),
	.vblank(vbl),
	.ce_pix(ce_pix),

	.audio(audio),
	.led(),
	.flip(flip),

	.hs_address(ioctl_download ? ioctl_addr[5:0] : hs_address),
	.hs_data_in(ioctl_dout),
	.hs_data_out(hs_data_out),
	.hs_write(ioctl_wr & nvram_download)
);

pause #(8,8,8,12) pause
(
	.clk_sys(clk_sys),
	.reset(reset),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[26:25]),
	.OSD_STATUS(OSD_STATUS),
	.r(r),
	.g(g),
	.b(b),
	.pause_cpu(pause_cpu),
	.rgb_out(rgb_out)
);

// High scores (EAROM contents) saved to /media/fat/config/nvram/
nvram #(
	.DUMPWIDTH(6),
	.DUMPINDEX(4),
	.PAUSEPAD(2)
) hi (
	.clk(clk_sys),
	.paused(pause_cpu),
	.reset(reset),
	.autosave(status[27]),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr[24:0]),
	.ioctl_index(ioctl_index[7:0]),
	.ioctl_din(ioctl_din),
	.ioctl_dout(ioctl_dout),
	.OSD_STATUS(OSD_STATUS),
	.nvram_address(hs_address),
	.nvram_data_out(hs_data_out),
	.pause_cpu(hs_pause)
);

////////////////////   VIDEO / AUDIO   ///////////////////

arcade_video #(256, 24) arcade_video
(
	.clk_video(clk_sys),
	.ce_pix(ce_pix),

	.RGB_in(rgb_out),
	.HBlank(hbl),
	.VBlank(vbl),
	.HSync(hs),
	.VSync(vs),

	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),
	.VGA_SL(VGA_SL),

	.fx(status[5:3]),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus)
);

// ROT270 (MAME): rotate anticlockwise.  In cocktail mode the game turns the
// whole picture for player 2 (VIDROT); rotate the other way to keep it upright.
screen_rotate screen_rotate
(
	.CLK_VIDEO(CLK_VIDEO),
	.CE_PIXEL(CE_PIXEL),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_HS(VGA_HS),
	.VGA_VS(VGA_VS),
	.VGA_DE(VGA_DE),

	.rotate_ccw(~flip),
	.no_rotate(no_rotate),
	.flip(1'b0),
	.video_rotated(),

	.FB_EN(FB_EN),
	.FB_FORMAT(FB_FORMAT),
	.FB_WIDTH(FB_WIDTH),
	.FB_HEIGHT(FB_HEIGHT),
	.FB_BASE(FB_BASE),
	.FB_STRIDE(FB_STRIDE),
	.FB_VBL(FB_VBL),
	.FB_LL(FB_LL),

	.DDRAM_CLK(DDRAM_CLK),
	.DDRAM_BUSY(DDRAM_BUSY),
	.DDRAM_BURSTCNT(DDRAM_BURSTCNT),
	.DDRAM_ADDR(DDRAM_ADDR),
	.DDRAM_DIN(DDRAM_DIN),
	.DDRAM_BE(DDRAM_BE),
	.DDRAM_WE(DDRAM_WE),
	.DDRAM_RD(DDRAM_RD)
);

assign AUDIO_L   = audio;
assign AUDIO_R   = audio;
assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_USER = ioctl_download;

endmodule
