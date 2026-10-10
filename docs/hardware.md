# Millipede hardware notes

Sources: Atari schematic package SP-217 (Millipede game PCB 038874, sheets 1A-7A),
the Millipede operation, maintenance and service manual (PCB layout and parts
lists), and MAME
`atari/centiped.cpp` / `centiped_v.cpp` for comparison.  Chip references
("7H", "9B") are board locations.

The board is a close relative of the Centipede board, not a "system" board.

## Clocks and timing (sheets 3B, 4A)

* Y1 12.096 MHz.  6D/6E/6F LS163 count 6MHZ, 1H .. 256H; the chain runs
  128H..511H, so a line is 384 pixels (6.048 MHz pixel clock, 15.75 kHz).
* 2HD (8H LS74) and 4HD (7H LS109) are 2H and 4H re-timed on 6MHZ rising.
* PLOAD = NAND(1H, 2H, 4H) (5F).  256HD and 256H2D (10D) are clocked once per
  8-pixel slot (9E: 12MHZ low while 6D ripple-carry is high).
* Vertical: 7C/7D LS163 clocked by /256H, sync PROM 136001-213 at 7E latched in 8E.
  PROM address = {VBLANK, 128V, 64V, 32V, 8V, 4V, 2V, 1V} (16V is not used).
  Outputs: bit 0 VSYNC, bit 2 VRESET, bit 3 VBLANK.  Result: 263 lines/frame
  (59.88 Hz), visible V = 0..239, VBLANK from V=240 through a second pass of
  V=0..6, VSYNC on V=243..245.

### CPU clock (7H LS109)

J = /SCRAM OR 4HD, /K = /2HD, clocked by /1H.  With no playfield access, phi0
follows 2H exactly (1.512 MHz).  When the CPU addresses playfield RAM
($1000-$1FFF, SCRAM) J is held low until 4HD, stretching the low phase so the
access lands in the CPU's half of the playfield RAM time slot (MAME notes the
0.756 MHz figure but does not model it).

### IRQ (3H LS74)

D = 32V, clock = 16V, /Q drives /IRQ, cleared by IRQRES ($2600).  Four IRQs per
frame, at V = 48, 112, 176, 240.

### Watchdog / reset (9F LS90)

The LS90 counts VBLANK and is cleared by WATCHDOG ($2680); QD resets the CPU.
Power-on RESET presets it to 9, so the CPU starts at the first VBLANK.

## Address map (sheet 3A, matches MAME)

A15 is not decoded.

| Address | Function |
|---|---|
| 0000-03FF | RAM |
| 0400-040F | POKEY 4D (I/OS0); $0408 ALLPOT = option switch 5D |
| 0800-080F | POKEY 4B (I/OS1); $0808 ALLPOT = option switch 5B |
| 1000-13BF | playfield RAM |
| 13C0-13FF | motion objects: picture, vertical, horizontal, colour (16 each) |
| 2000 R | D7 HDIR, D6 VBLANK, D5 START1, D4 FIRE1, D3-0 horizontal trackball counter |
| 2001 R | D7 VDIR, D6 0, D5 START2, D4 FIRE2, D3-0 vertical trackball counter |
| 2010 R | D7 COIN R, D6 COIN L, D5 COIN AUX, D4 SLAM, D3-0 joystick |
| 2011 R | D7 SELF TEST, D6 0, D5 CABINET, D4 (pulled up), D3-0 joystick |
| 2030 R | EAROM read |
| 2480-248F W | playfield colour RAM |
| 2490-249F W | motion object colour RAM |
| 2500-2507 W | 12E LS259 (D7): 1 coin cntr L, 2 coin cntr R, 3/4 start LEDs, 5 TBEN, 6 VIDROT, 7 CNTRLSEL |
| 2600 W | IRQ reset |
| 2680 W | watchdog |
| 2700 W | EAROM control |
| 2780-27BF W | EAROM address/data |
| 3000-3FFF | ROM 0 socket, not used |
| 4000-7FFF | program ROM |

## Playfield (sheet 5A)

Four 256x8 RAM lanes (2101).  Video address = {128V..16V, 64H..8H}, lane =
{8V, 128H}; during horizontal blank (256H low) the address is {1111, 64H..8H}
and lane 0, giving the 16 motion objects one 8-pixel slot each.
PIC0-7 latched in 4R on 4H.  PIC7D/PIC6D (palette select) in 9J on /4H, the
same edge on which 9B latches the first pixel of the new character.

## Motion objects (sheet 5B)

* 6H/6J add V and the object's vertical byte; /VMATCH = NAND of the top four
  sum bits.  6L latches the low four bits and /VMATCH on 4H.
* 6M/7N select row and flips: during objects the row is the sum, PIC7 is
  vertical flip, PIC6 horizontal flip and PIC0 the ROM bank (MGA10); during the
  playfield the row is {PIC0, 4V..1V}, there are no flips and PIC6 is MGA10.
  VIDROT is XORed into both flips; there is no flip of the address counters
  (the game mirrors the picture itself in cocktail mode).
* Picture ROM address = {MGA10, 256H, PIC5..PIC1, MGA3..0}.  5R (-107) feeds
  AREA0 through 7R, 5P (-106) AREA1 through 5L (LS166, loaded on PLOAD).
* Horizontal position: 5E latches the horizontal byte on 4H; 8D/8C LS163 are
  loaded on PLOAD while 256H is low and cleared on the first PLOAD of the line.
* Line buffer 8B (93422, 256x4) holds {MOCB1, MOCB0, GRY1, GRY0}, written
  every pixel while 6MHZ is low (read-modify-write with 9B, latched on /6MHZ).
* Colour selectors 8J/7B (S153): object colour byte from 7K (4H) / 7J (/4H).
  Pen n selects colour bits [2n-1:2n-2]; bits 7-6 are the bank.  A pen 0 pixel
  keeps the old line-buffer contents.  A pen whose selection is 0 writes 0, so
  it can erase an earlier object's pixel (MAME treats it as transparent).
  The selectors are disabled by 256HD, which clears the buffer as it is read.

## Colour (sheet 6A)

* Colour address (9C/10C/12B): object pixel when (GRY != 0) AND 256H AND
  256H2D, giving {1, MOCB, GRY}; otherwise {0, PIC7D, PIC6D, AREA}.  The
  256H AND 256H2D gate hides objects in the last 8 pixels of the line (MAME's
  sprite clip).
* 10A/10B/11B/11C 82S25, 32 x 8, inverted outputs; 12A latches the colour on
  /6MHZ and is cleared during blanking.
* DAC: red 470/1k/1.8k (D7-5) with 1.8k to ground; green 470/1k (D4-3) with
  1.8k to +5V and 1.8k to ground; blue 470/1k/1.8k (D2-0) with 1.8k to +5V and
  1.8k to ground; all with 6.8k to +15V into 2N3904 emitter followers.  Green
  and blue have a black-level offset (removed in the core, as monitor setup
  would).  MAME's weights give green a maximum of 222; the board reaches full
  scale.

## Inputs (sheet 6B)

* Trak-Ball: 10P selects player 1 or 2 by CNTRLSEL (MAME uses VIDROT).  10R
  latches each direction on its clock; 9P/8N LS191 count.  While TBEN is low
  the counters are held loaded with option switch bank 8P:
  9P (horizontal) = switches 1-4, 8N (vertical) = switches 5-7, D tied low.
  Switch 8 is the CCNTRR coin counter strap and is not readable.
  The game copies the two nibbles into RAM $F8 at start-up.  Switches 5 and 6
  ($F8 bits 4-5) are "unknown" in MAME, which reads them as 1 (open); the
  game combines them with the coin switch settings when it builds its coin
  table (around $77F0), and with them at 0 the game misbehaves (it fired by
  itself in testing).  The MRA keeps them at 1, so the default for the bank is
  $34 (bonus 0/1x, English, credit minimum 1).
* Joystick (9M): selected by CNTRLSEL for both $2010 and $2011.  The sheet notes
  the circuit is not used in Millipede, but the game reads it.

## Sound (sheet 7A)

* Two POKEYs.  Their clock is PHI2B OR 2H (4F); since phi0 follows 2H and only
  stretches its low phase, this is a steady 2H = 1.512 MHz.
* The option switches 5D/5B are on the POKEY pot inputs (10k pull-ups, no
  capacitors).  The game writes SKCTL = $07 (fast pot scan), POTGO, and reads
  ALLPOT once at start-up.
* Both AUD outputs are tied together, with C63 0.22uF to ground and R153 220R
  to the inverting input of a TL084 (11F) held at +5V (R154/C36), feedback
  R155 1k.  This is a current-to-voltage stage: the POKEY sinks pull current
  through R153.  With C63 the node forms a low-pass of about 3.3 kHz (higher
  at high volume).  C37 0.22uF / R156 39k couple to two inverting stages (AUD1,
  AUD2, balanced).  MAME uses its linear mix with no filtering.
