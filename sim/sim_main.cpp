// Verilator testbench for the Millipede core (top = millipede).
// Downloads roms/rom.bin through the download port, runs N frames, dumps frames as PPM,
// records audio (48 kHz signed 16-bit mono, audio.raw) and logs POKEY accesses.
// Usage: Vmillipede <frames> <dump_every>
// Environment:
//   DUMP_FROM=n        also dump every frame from n on
//   INPUTS=f:v,...     from frame f, drive the controls with hex v (active high):
//                      bit0 coin L, 1 coin R, 2 start1, 3 start2, 4 fire1, 5 fire2, 6 self test,
//                      bits 11:8 joy1 {up,down,left,right}, bit 12 trackball right, 13 left,
//                      14 up, 15 down (generated as trackball pulses)
//   DSW=aabbcc         dsw0 dsw1 dsw2 (default 140234 = MAME defaults)
//   POKEY_LOG=file     log POKEY reads/writes as "frame R|W addr data" (MAME trace format)
//   AUDIO_MAME=1       MAME linear mix instead of the board output stage
//   PAL_MAME=0         board DAC levels instead of MAME weights
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <string>
#include "Vmillipede.h"
#include "Vmillipede___024root.h"
#include "verilated.h"

static Vmillipede *top;
static void tick() { top->clk = 0; top->eval(); top->clk = 1; top->eval(); }

static void write_ppm(const char *name, const std::vector<uint8_t> &fb, int w, int h) {
    FILE *f = fopen(name, "wb");
    fprintf(f, "P6\n%d %d\n255\n", w, h);
    fwrite(fb.data(), 1, (size_t)w * h * 3, f);
    fclose(f);
}

static unsigned ctrl = 0;
static void apply_inputs() {
    top->coin_l = ctrl & 1;  top->coin_r = (ctrl >> 1) & 1;
    top->start1 = (ctrl >> 2) & 1;  top->start2 = (ctrl >> 3) & 1;
    top->fire1 = (ctrl >> 4) & 1;   top->fire2 = (ctrl >> 5) & 1;
    top->self_test = (ctrl >> 6) & 1;
    top->joy1 = (ctrl >> 8) & 0xf;
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int frames = argc > 1 ? atoi(argv[1]) : 60;
    int every  = argc > 2 ? atoi(argv[2]) : 10;
    int from   = getenv("DUMP_FROM") ? atoi(getenv("DUMP_FROM")) : 1 << 30;
    unsigned dsw = getenv("DSW") ? strtoul(getenv("DSW"), nullptr, 16) : 0x140234;

    top = new Vmillipede;
    top->dsw0 = (dsw >> 16) & 0xff;
    top->dsw1 = (dsw >> 8) & 0xff;
    top->dsw2 = dsw & 0xff;
    top->upright = 1;
    top->palette_mame = getenv("PAL_MAME") ? atoi(getenv("PAL_MAME")) : 1;
    top->audio_board = getenv("AUDIO_MAME") ? !atoi(getenv("AUDIO_MAME")) : 1;
    apply_inputs();

    std::vector<std::pair<int, unsigned>> script;
    if (const char *s = getenv("INPUTS")) {
        int f, n; unsigned v;
        while (sscanf(s, "%d:%x%n", &f, &v, &n) == 2) {
            script.push_back({f, v});
            s += n;
            if (*s == ',') s++;
        }
    }
    size_t next_input = 0;

    FILE *rf = fopen("roms/rom.bin", "rb");
    if (!rf) { fprintf(stderr, "roms/rom.bin missing\n"); return 1; }
    std::vector<uint8_t> rom(0x5100);
    size_t rn = fread(rom.data(), 1, rom.size(), rf);
    fclose(rf);
    top->reset = 1;
    for (int i = 0; i < 16; i++) tick();
    for (size_t a = 0; a < rn; a++) {
        top->dn_addr = a; top->dn_data = rom[a]; top->dn_wr = 1; tick();
        top->dn_wr = 0; tick();
    }
    for (int i = 0; i < 100; i++) tick();
    top->reset = 0;

    FILE *pl = getenv("POKEY_LOG") ? fopen(getenv("POKEY_LOG"), "w") : nullptr;
    FILE *audio = fopen("audio.raw", "wb");
    int64_t audio_acc = 0;
    int audio_n = 0;

    const int FW = 320, FH = 280;
    std::vector<uint8_t> fb(FW * FH * 3, 0);
    int x = 0, y = 0, maxx = 0, maxy = 0, frame = 0;
    bool last_hblank = false, last_vblank = false;
    uint64_t cycles = 0;
    auto *r = top->rootp;
    int tb_phase = 0, tb_div = 0;

    while (frame < frames) {
        // Trackball emulation: pulses at ~3 kHz while a direction is held
        if (++tb_div == 2000) {
            tb_div = 0;
            tb_phase ^= 1;
            unsigned h = (ctrl >> 12) & 3, v = (ctrl >> 14) & 3;
            top->tb1_hdir = (h == 2); top->tb1_hclk = h ? tb_phase : 0;
            top->tb1_vdir = (v == 1); top->tb1_vclk = v ? tb_phase : 0;
        }
        tick();
        cycles++;

        if (pl && r->millipede__DOT__cpu_ce) {
            unsigned a = r->millipede__DOT__ab & 0x7fff;
            if (a >= 0x400 && a < 0xc00 && (a & 0xf) != 0xa) {
                bool wr = !r->millipede__DOT__rw_n;
                fprintf(pl, "%d %c %04X %02X\n", frame, wr ? 'W' : 'R', a,
                        wr ? r->millipede__DOT__cpu_dout : r->millipede__DOT__cpu_din);
            }
        }

        if (getenv("IO_LOG") && r->millipede__DOT__cpu_ce && frame == atoi(getenv("IO_LOG"))) {
            unsigned a = r->millipede__DOT__ab & 0x7fff;
            if (a >= 0x2000 && a < 0x2040 && r->millipede__DOT__rw_n)
                printf("IO R %04X %02X\n", a, r->millipede__DOT__cpu_din);
        }
        // PC_TRACE=from,to: print the address of every opcode fetch (DECODE state) in those frames
        if (const char *pt = getenv("PC_TRACE")) {
            static int pf = -1, pt2 = -1;
            if (pf < 0) sscanf(pt, "%d,%d", &pf, &pt2);
            if (r->millipede__DOT__cpu_ce && frame >= pf && frame < pt2 && r->millipede__DOT__cpu__DOT__state == 12)
                printf("PC %d %04X A=%02X\n", frame, r->millipede__DOT__cpu__DOT__PC,
                       r->millipede__DOT__cpu__DOT__AXYS[0]);
        }
        audio_acc += (int16_t)top->audio;
        if (++audio_n == 252) {
            int16_t s = (int16_t)(audio_acc / 252);
            fwrite(&s, 2, 1, audio);
            audio_acc = audio_n = 0;
        }

        if (!top->ce_pix) continue;
        if (!top->hblank && !top->vblank) {
            if (x < FW && y < FH) {
                uint8_t *p = &fb[(y * FW + x) * 3];
                p[0] = top->red; p[1] = top->green; p[2] = top->blue;
            }
            if (x == 0 && getenv("VLOG") && frame == atoi(getenv("VLOG")))
                printf("line %d: V=%d hc=%x\n", y, r->millipede__DOT__V, r->millipede__DOT__hc);
            x++;
            if (x > maxx) maxx = x;
        }
        if (top->hblank && !last_hblank) { if (x) { y++; if (y > maxy) maxy = y; } x = 0; }
        if (top->vblank && !last_vblank) {
            frame++;
            while (next_input < script.size() && script[next_input].first <= frame) {
                ctrl = script[next_input++].second;
                apply_inputs();
            }
            // RAMDUMP=f,g,...: write ram_<frame>.bin (0000-03FF) at those frames
            if (const char *rd = getenv("RAMDUMP")) {
                std::string list = std::string(",") + rd + ",";
                if (list.find("," + std::to_string(frame) + ",") != std::string::npos) {
                    char name[32];
                    snprintf(name, sizeof name, "ram_%04d.bin", frame);
                    FILE *f = fopen(name, "wb");
                    for (int i = 0; i < 1024; i++) {
                        uint8_t b = r->millipede__DOT__ram__DOT__mem[i];
                        fwrite(&b, 1, 1, f);
                    }
                    fclose(f);
                }
            }
            if (frame == 2 || frame % 100 == 0)
                printf("frame %4d  active %dx%d  pc %04x\n", frame, maxx, maxy,
                       r->millipede__DOT__ab);
            if (frame % every == 0 || frame >= from) {
                char name[64];
                snprintf(name, sizeof name, "frame_%04d.ppm", frame);
                write_ppm(name, fb, FW, FH);
            }
            y = 0; maxx = maxy = 0;
        }
        last_hblank = top->hblank;
        last_vblank = top->vblank;
    }

    if (pl) fclose(pl);
    fclose(audio);
    printf("%llu clocks, %.2f s emulated\n", (unsigned long long)cycles, cycles / 12.096e6);
    delete top;
    return 0;
}
