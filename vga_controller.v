module vga_controller (
    input wire clk_25mhz,       // 25MHz VGA clock from your board's clock wizard
    input wire reset,
    
    // Game state inputs directly from your CPU's MMIO registers
    input wire [9:0] ship_x,
    input wire [9:0] laser_x,
    input wire [9:0] laser_y,
    input wire [9:0] alien_x,
    input wire [9:0] alien_y,
    input wire [29:0] io_alien_mask, // 1 = Alive, 0 = Dead. bits [9:0]=row0, [19:10]=row1, [29:20]=row2
    input wire [9:0] explosion_x,
    input wire [9:0] explosion_y,
    input wire explosion_active,
    input wire [15:0] score,
    input wire [9:0] elaser_x,
    input wire [9:0] elaser_y,
    input wire game_over,
    
    // Physical VGA port pins on the Basys 3
    output reg hsync,
    output reg vsync,
    output reg [3:0] red,
    output reg [3:0] green,
    output reg [3:0] blue
);
 
    // Standard Timing Constants for 640x480 @ 60Hz
    localparam H_VISIBLE = 640;
    localparam H_TOTAL   = 800;
    localparam V_VISIBLE = 480;
    localparam V_TOTAL   = 525;
 
    // Formation layout
    localparam ROW_SPACING = 30;  // vertical gap between the 3 rows
    localparam COL_SPACING = 30;  // horizontal gap between the 10 columns (was 35 for 8 columns)
    localparam ALIEN_SIZE  = 20;  // on-screen width/height of each alien
 
    reg [9:0] h_count;
    reg [9:0] v_count;
    
 
    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            h_count <= 0;
            v_count <= 0;
        end else begin
            if(h_count == H_TOTAL - 1) begin
                h_count <= 0;
                if(v_count == V_TOTAL - 1)
                    v_count <= 0;
                else
                    v_count <= v_count + 1;
            end else begin
                h_count <= h_count + 1;
            end
        end
    end
 
    always @(*) begin
        hsync = ~((h_count >= 656) && (h_count < 752)); // 640 + 16 front porch
        vsync = ~((v_count >= 490) && (v_count < 492)); // 480 + 10 front porch
    end
 
    wire video_on = (h_count < H_VISIBLE) && (v_count < V_VISIBLE);
 
    // ============================================================
    // ALIEN WALK-CYCLE TIMER
    // Flips alien_frame once every ANIM_PERIOD full video frames
    // (~60Hz frame rate), independent of the RISC-V program. Shared
    // by all three alien types so the whole formation marches in sync.
    // ============================================================
    localparam [5:0] ANIM_PERIOD = 6'd29; // ~30 frames = ~0.5s per pose at 60Hz
 
    reg [5:0] frame_counter;
    reg alien_frame;
    wire end_of_frame = (h_count == H_TOTAL - 1) && (v_count == V_TOTAL - 1);
 
    always @(posedge clk_25mhz or posedge reset) begin
        if (reset) begin
            frame_counter <= 6'd0;
            alien_frame   <= 1'b0;
        end else if (end_of_frame) begin
            if (frame_counter == ANIM_PERIOD) begin
                frame_counter <= 6'd0;
                alien_frame   <= ~alien_frame;
            end else begin
                frame_counter <= frame_counter + 1'b1;
            end
        end
    end
 
    // ============================================================
    // SPRITE ROMS
    // Original silhouettes (not the iconic Taito sprites), authored
    // at low resolution and scaled 2x to fill the existing 20x20
    // alien hitbox exactly -- no gameplay/collision math changes.
    // All three types share the same two-frame leg animation; only
    // the body/head (rows 0-5) differs between types.
    // ============================================================
 
    // Ship: 15x8 source, scaled 2x -> 30x16 on screen (matches existing hitbox)
    reg [14:0] ship_sprite [0:7];
    initial begin
        ship_sprite[0] = 15'b000000111000000;
        ship_sprite[1] = 15'b000001111100000;
        ship_sprite[2] = 15'b000001111100000;
        ship_sprite[3] = 15'b000011111110000;
        ship_sprite[4] = 15'b011111111111110;
        ship_sprite[5] = 15'b011111111111110;
        ship_sprite[6] = 15'b111111111111111;
        ship_sprite[7] = 15'b101010101010101; // flickering thruster row
    end
 
    // Shared legs, two frames (splayed / tucked)
    reg [9:0] legs_a [0:3];
    reg [9:0] legs_b [0:3];
    initial begin
        legs_a[0] = 10'b0011001100;
        legs_a[1] = 10'b0110000110;
        legs_a[2] = 10'b1100000011;
        legs_a[3] = 10'b0100000010;
 
        legs_b[0] = 10'b0001111000;
        legs_b[1] = 10'b0011001100;
        legs_b[2] = 10'b0110000110;
        legs_b[3] = 10'b1100000011;
    end
 
    // Row 0 (bottom row, closest to ship): "round-eyed" type
    reg [9:0] type0_body [0:5];
    initial begin
        type0_body[0] = 10'b0011111100;
        type0_body[1] = 10'b0111111110;
        type0_body[2] = 10'b1101111011; // eyes
        type0_body[3] = 10'b1111111111;
        type0_body[4] = 10'b1111111111;
        type0_body[5] = 10'b0111111110;
    end
 
    // Row 1 (middle row): "wide-winged" type
    reg [9:0] type1_body [0:5];
    initial begin
        type1_body[0] = 10'b1000000001;
        type1_body[1] = 10'b1110000111;
        type1_body[2] = 10'b1111111111;
        type1_body[3] = 10'b0111111110;
        type1_body[4] = 10'b0101111010;
        type1_body[5] = 10'b0011111100;
    end
 
    // Row 2 (top row): "tall/insect" type
    reg [9:0] type2_body [0:5];
    initial begin
        type2_body[0] = 10'b0001111000;
        type2_body[1] = 10'b0011111100;
        type2_body[2] = 10'b0111111110;
        type2_body[3] = 10'b1111001111;
        type2_body[4] = 10'b1111111111;
        type2_body[5] = 10'b0111111110;
    end
 
    // Death animation: simple X-shaped burst, 10x10 source scaled 2x -> 20x20
    // (matches the alien hitbox exactly, so it appears right where the
    // alien was). Original design, not tied to any particular game's art.
    reg [9:0] explosion_sprite [0:9];
    initial begin
        explosion_sprite[0] = 10'b1000000001;
        explosion_sprite[1] = 10'b0100000010;
        explosion_sprite[2] = 10'b0010000100;
        explosion_sprite[3] = 10'b0001001000;
        explosion_sprite[4] = 10'b0000110000;
        explosion_sprite[5] = 10'b0000110000;
        explosion_sprite[6] = 10'b0001001000;
        explosion_sprite[7] = 10'b0010000100;
        explosion_sprite[8] = 10'b0100000010;
        explosion_sprite[9] = 10'b1000000001;
    end
 
    // Scoreboard digit font: standard 5x7 blocky numerals, one entry per
    // (digit*7 + row), scaled 3x -> 15x21 on screen per digit.
    reg [4:0] digit_font [0:69];
    initial begin
        // 0
        digit_font[0]=5'b01110; digit_font[1]=5'b10001; digit_font[2]=5'b10011; digit_font[3]=5'b10101;
        digit_font[4]=5'b11001; digit_font[5]=5'b10001; digit_font[6]=5'b01110;
        // 1
        digit_font[7]=5'b00100; digit_font[8]=5'b01100; digit_font[9]=5'b00100; digit_font[10]=5'b00100;
        digit_font[11]=5'b00100; digit_font[12]=5'b00100; digit_font[13]=5'b01110;
        // 2
        digit_font[14]=5'b01110; digit_font[15]=5'b10001; digit_font[16]=5'b00001; digit_font[17]=5'b00010;
        digit_font[18]=5'b00100; digit_font[19]=5'b01000; digit_font[20]=5'b11111;
        // 3
        digit_font[21]=5'b11111; digit_font[22]=5'b00010; digit_font[23]=5'b00100; digit_font[24]=5'b00010;
        digit_font[25]=5'b00001; digit_font[26]=5'b10001; digit_font[27]=5'b01110;
        // 4
        digit_font[28]=5'b00010; digit_font[29]=5'b00110; digit_font[30]=5'b01010; digit_font[31]=5'b10010;
        digit_font[32]=5'b11111; digit_font[33]=5'b00010; digit_font[34]=5'b00010;
        // 5
        digit_font[35]=5'b11111; digit_font[36]=5'b10000; digit_font[37]=5'b11110; digit_font[38]=5'b00001;
        digit_font[39]=5'b00001; digit_font[40]=5'b10001; digit_font[41]=5'b01110;
        // 6
        digit_font[42]=5'b00110; digit_font[43]=5'b01000; digit_font[44]=5'b10000; digit_font[45]=5'b11110;
        digit_font[46]=5'b10001; digit_font[47]=5'b10001; digit_font[48]=5'b01110;
        // 7
        digit_font[49]=5'b11111; digit_font[50]=5'b00001; digit_font[51]=5'b00010; digit_font[52]=5'b00100;
        digit_font[53]=5'b01000; digit_font[54]=5'b01000; digit_font[55]=5'b01000;
        // 8
        digit_font[56]=5'b01110; digit_font[57]=5'b10001; digit_font[58]=5'b10001; digit_font[59]=5'b01110;
        digit_font[60]=5'b10001; digit_font[61]=5'b10001; digit_font[62]=5'b01110;
        // 9
        digit_font[63]=5'b01110; digit_font[64]=5'b10001; digit_font[65]=5'b10001; digit_font[66]=5'b01111;
        digit_font[67]=5'b00001; digit_font[68]=5'b00010; digit_font[69]=5'b01100;
    end
 
    // "GAME OVER" letterforms, standard blocky 5x7 style (same generic
    // functional convention as the digit font -- not a creative work).
    // Indexed by letter*7+row: 0=G, 1=A, 2=M, 3=E, 4=O, 5=V, 6=R
    reg [4:0] letter_font [0:48];
    initial begin
        // G (index 0)
        letter_font[0]=5'b01111; letter_font[1]=5'b10000; letter_font[2]=5'b10000; letter_font[3]=5'b10011;
        letter_font[4]=5'b10001; letter_font[5]=5'b10001; letter_font[6]=5'b01111;
        // A (index 1)
        letter_font[7]=5'b01110; letter_font[8]=5'b10001; letter_font[9]=5'b10001; letter_font[10]=5'b11111;
        letter_font[11]=5'b10001; letter_font[12]=5'b10001; letter_font[13]=5'b10001;
        // M (index 2)
        letter_font[14]=5'b10001; letter_font[15]=5'b11011; letter_font[16]=5'b10101; letter_font[17]=5'b10101;
        letter_font[18]=5'b10001; letter_font[19]=5'b10001; letter_font[20]=5'b10001;
        // E (index 3)
        letter_font[21]=5'b11111; letter_font[22]=5'b10000; letter_font[23]=5'b10000; letter_font[24]=5'b11110;
        letter_font[25]=5'b10000; letter_font[26]=5'b10000; letter_font[27]=5'b11111;
        // O (index 4)
        letter_font[28]=5'b01110; letter_font[29]=5'b10001; letter_font[30]=5'b10001; letter_font[31]=5'b10001;
        letter_font[32]=5'b10001; letter_font[33]=5'b10001; letter_font[34]=5'b01110;
        // V (index 5)
        letter_font[35]=5'b10001; letter_font[36]=5'b10001; letter_font[37]=5'b10001; letter_font[38]=5'b10001;
        letter_font[39]=5'b10001; letter_font[40]=5'b01010; letter_font[41]=5'b00100;
        // R (index 6)
        letter_font[42]=5'b11110; letter_font[43]=5'b10001; letter_font[44]=5'b10001; letter_font[45]=5'b11110;
        letter_font[46]=5'b10100; letter_font[47]=5'b10010; letter_font[48]=5'b10001;
    end
 
    // ============================================================
    // GAME OVER OVERLAY
    // "GAME OVER" = 9 character slots (G,A,M,E,space,O,V,E,R).
    // Letter indices into letter_font; 7 = blank (space).
    // ============================================================
    localparam GO_SCALE = 6;
    localparam GO_CHAR_W = 5 * GO_SCALE; // 30
    localparam GO_CHAR_H = 7 * GO_SCALE; // 42
    localparam GO_GAP    = 6;
    localparam GO_Y0     = 219;
    localparam GO_X0     = 320 - ((9*GO_CHAR_W + 8*GO_GAP) / 2); // centers the 9-slot message
 
    reg [2:0] go_letter_idx [0:8];
    initial begin
        go_letter_idx[0] = 0; // G
        go_letter_idx[1] = 1; // A
        go_letter_idx[2] = 2; // M
        go_letter_idx[3] = 3; // E
        go_letter_idx[4] = 7; // (space)
        go_letter_idx[5] = 4; // O
        go_letter_idx[6] = 5; // V
        go_letter_idx[7] = 3; // E
        go_letter_idx[8] = 6; // R
    end
 
    reg game_over_pixel_on;
    integer g;
    reg [2:0] go_letter;
    reg [9:0] go_local_x;
    reg [9:0] go_local_y;
    reg [2:0] go_font_row;
    reg [2:0] go_font_col;
 
    always @(*) begin
        game_over_pixel_on = 1'b0;
        for (g = 0; g < 9; g = g + 1) begin
            if ((h_count >= GO_X0 + g*(GO_CHAR_W+GO_GAP)) &&
                (h_count <  GO_X0 + g*(GO_CHAR_W+GO_GAP) + GO_CHAR_W) &&
                (v_count >= GO_Y0) && (v_count < GO_Y0 + GO_CHAR_H)) begin
 
                go_letter = go_letter_idx[g];
                if (go_letter != 3'd7) begin // not a blank/space slot
                    go_local_x = h_count - (GO_X0 + g*(GO_CHAR_W+GO_GAP));
                    go_local_y = v_count - GO_Y0;
                    go_font_row = go_local_y / GO_SCALE;
                    go_font_col = go_local_x / GO_SCALE;
                    if (letter_font[go_letter*7 + go_font_row][4-go_font_col])
                        game_over_pixel_on = 1'b1;
                end
            end
        end
    end
 
    // ============================================================
    // SCOREBOARD
    // Extracts 4 decimal digits from the 16-bit binary score (constant
    // divisors -- Vivado synthesizes this as small dedicated logic, not
    // a general-purpose divider, and it settles well within one 25MHz
    // pixel period). Rendered near the top of the screen, well above
    // where the alien formation starts.
    // ============================================================
    wire [3:0] score_thousands = (score / 1000) % 10;
    wire [3:0] score_hundreds  = (score / 100)  % 10;
    wire [3:0] score_tens      = (score / 10)   % 10;
    wire [3:0] score_ones      = score % 10;
 
    localparam SCORE_SCALE = 3;
    localparam SCORE_DIGIT_W = 5 * SCORE_SCALE;  // 15
    localparam SCORE_DIGIT_H = 7 * SCORE_SCALE;  // 21
    localparam SCORE_GAP     = 3;
    localparam SCORE_Y       = 10;
    localparam SCORE_X0      = 320 - (2*(SCORE_DIGIT_W+SCORE_GAP)); // centers the 4-digit block
 
    reg score_pixel_on;
    reg [3:0] cur_digit_value;
    reg [6:0] font_row_bits5; // only bottom 5 bits used
    integer d;
    reg [9:0] digit_local_x;
    reg [9:0] digit_local_y;
    reg [2:0] font_row;
    reg [2:0] font_col;
 
    always @(*) begin
        score_pixel_on = 1'b0;
        for (d = 0; d < 4; d = d + 1) begin
            if ((h_count >= SCORE_X0 + d*(SCORE_DIGIT_W+SCORE_GAP)) &&
                (h_count <  SCORE_X0 + d*(SCORE_DIGIT_W+SCORE_GAP) + SCORE_DIGIT_W) &&
                (v_count >= SCORE_Y) && (v_count < SCORE_Y + SCORE_DIGIT_H)) begin
 
                case (d)
                    0: cur_digit_value = score_thousands;
                    1: cur_digit_value = score_hundreds;
                    2: cur_digit_value = score_tens;
                    default: cur_digit_value = score_ones;
                endcase
 
                digit_local_x = h_count - (SCORE_X0 + d*(SCORE_DIGIT_W+SCORE_GAP));
                digit_local_y = v_count - SCORE_Y;
                font_row = digit_local_y / SCORE_SCALE; // 0..6
                font_col = digit_local_x / SCORE_SCALE; // 0..4
 
                if (digit_font[cur_digit_value*7 + font_row][4-font_col])
                    score_pixel_on = 1'b1;
            end
        end
    end
 
    // ============================================================
    // DEATH ANIMATION (explosion)
    // Position is written once by the RISC-V program at the moment of a
    // hit; the ~150ms display duration is entirely hardware-timed
    // (explosion_active, driven by top.v), so this renders independently
    // of the alien/mask state -- it plays out even after the alien's
    // normal sprite has already stopped drawing.
    // ============================================================
    wire explosion_in_bbox = explosion_active &&
                             (h_count >= explosion_x) && (h_count < explosion_x + 20) &&
                             (v_count >= explosion_y) && (v_count < explosion_y + 20);
    wire [9:0] explosion_local_x = h_count - explosion_x;
    wire [9:0] explosion_local_y = v_count - explosion_y;
    wire [3:0] explosion_row = explosion_local_y[4:1]; // /2 -> 0..9
    wire [3:0] explosion_col = explosion_local_x[4:1]; // /2 -> 0..9
    wire explosion_bit = explosion_sprite[explosion_row][9 - explosion_col];
    wire explosion_on = explosion_in_bbox && explosion_bit;
 
    // ============================================================
    // SHIP
    // ============================================================
    wire ship_in_bbox = (h_count >= ship_x) && (h_count < ship_x + 30) &&
                        (v_count >= 440)   && (v_count < 456);
    wire [9:0] ship_local_x = h_count - ship_x;
    wire [9:0] ship_local_y = v_count - 440;
    wire [2:0] ship_row = ship_local_y[3:1]; // /2 -> 0..7
    wire [3:0] ship_col = ship_local_x[4:1]; // /2 -> 0..14
    wire ship_bit = ship_sprite[ship_row][14 - ship_col];
    wire ship_on = ship_in_bbox && ship_bit;
 
    // ============================================================
    // LASER
    // Kept as a simple beam rather than a bitmap -- at 2px wide there
    // isn't enough room for a meaningful sprite; a two-tone glow reads
    // better than a forced pixel pattern at this size.
    // ============================================================
    wire laser_on = (laser_y > 0) && (h_count >= laser_x && h_count <= laser_x + 2) && (v_count >= laser_y && v_count <= laser_y + 10);
    wire laser_core = laser_on && (h_count == laser_x + 1); // brighter center column
 
    // Enemy laser: same shape/size as the player's, fired downward by the
    // "wide-winged" middle-row alien type. Rendered in magenta/red to
    // distinguish it at a glance from the player's yellow-orange bolt.
    wire elaser_on = (elaser_y > 0) && (h_count >= elaser_x && h_count <= elaser_x + 2) && (v_count >= elaser_y && v_count <= elaser_y + 10);
    wire elaser_core = elaser_on && (h_count == elaser_x + 1);
 
    // ============================================================
    // ALIENS (3 rows x 8 columns, sprite-based, animated, per-row type)
    // ============================================================
    integer r, c;
    reg [9:0] a_left;
    reg [9:0] a_top;
    reg [4:0] mask_bit_index;
    reg [9:0] alien_local_x;
    reg [9:0] alien_local_y;
    reg [3:0] alien_row;
    reg [3:0] alien_col;
    reg [9:0] body_bits;
    reg [9:0] leg_bits;
    reg [9:0] alien_row_bits;
    reg alien_pixel_on;
 
    always @(*) begin
        alien_pixel_on = 1'b0;
 
        for (r = 0; r < 3; r = r + 1) begin
            a_top = alien_y + (r * ROW_SPACING);
 
            for (c = 0; c < 10; c = c + 1) begin
                a_left = alien_x + (c * COL_SPACING);
                mask_bit_index = (r * 10) + c;
 
                if (io_alien_mask[mask_bit_index] &&
                    (h_count >= a_left) && (h_count < a_left + ALIEN_SIZE) &&
                    (v_count >= a_top)  && (v_count < a_top + ALIEN_SIZE)) begin
 
                    alien_local_x = h_count - a_left;
                    alien_local_y = v_count - a_top;
                    alien_row = alien_local_y[4:1]; // /2 -> 0..9
                    alien_col = alien_local_x[4:1]; // /2 -> 0..9
 
                    if (alien_row < 6) begin
                        case (r)
                            0: body_bits = type0_body[alien_row];
                            1: body_bits = type1_body[alien_row];
                            default: body_bits = type2_body[alien_row];
                        endcase
                        alien_row_bits = body_bits;
                    end else begin
                        leg_bits = alien_frame ? legs_b[alien_row-6] : legs_a[alien_row-6];
                        alien_row_bits = leg_bits;
                    end
 
                    if (alien_row_bits[9 - alien_col])
                        alien_pixel_on = 1'b1;
                end
            end
        end
    end
 
    // ============================================================
    // OUTPUT COLOR MUX
    // ============================================================
    always @(*) begin
        if (!video_on) begin
            red   = 4'b0000; green = 4'b0000; blue = 4'b0000; // Invisible blanking region
        end else if (game_over) begin
            if (game_over_pixel_on) begin
                red = 4'b1111; green = 4'b0000; blue = 4'b0000; // Bright red GAME OVER text
            end else if (score_pixel_on) begin
                red = 4'b1111; green = 4'b1111; blue = 4'b0000; // Final score stays visible
            end else begin
                red = 4'b0000; green = 4'b0000; blue = 4'b0000; // Plain black background
            end
        end else if (score_pixel_on) begin
            red   = 4'b1111; green = 4'b1111; blue = 4'b0000; // Yellow scoreboard
        end else if (ship_on) begin
            red   = 4'b0000; green = 4'b1111; blue = 4'b0000; // Green Ship
        end else if (laser_on) begin
            if (laser_core) begin
                red = 4'b1111; green = 4'b1111; blue = 4'b0110; // bright yellow-white core
            end else begin
                red = 4'b1111; green = 4'b0100; blue = 4'b0000; // dimmer orange edge
            end
        end else if (elaser_on) begin
            if (elaser_core) begin
                red = 4'b1111; green = 4'b0011; blue = 4'b1111; // bright magenta core
            end else begin
                red = 4'b1000; green = 4'b0000; blue = 4'b0100; // dimmer red-violet edge
            end
        end else if (explosion_on) begin
            red   = 4'b1111; green = 4'b1000; blue = 4'b0000; // Orange burst
        end else if (alien_pixel_on) begin
            red   = 4'b1111; green = 4'b1111; blue = 4'b1111; // White Invaders
        end else begin
            red   = 4'b0000; green = 4'b0000; blue = 4'b0011; // Dark blue background
        end
    end
 
endmodule
 