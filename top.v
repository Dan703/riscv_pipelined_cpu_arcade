module top(
    input clk,
    input reset,
    input wire [4:0] btn,
    output wire hsync,
    output wire vsync,
    output wire [3:0] red,
    output wire [3:0] green,
    output wire [3:0] blue,
    output wire buzzer
    );

    always @(posedge clk) begin
    if (mem_write_e)
        $display("STORE | rs1_e=%0d rs2_e=%0d rd1_e=%0d rd2_e=%0d src_b_forward_e=%0d forward_b_e=%b",
            rs1_e, rs2_e, rd1_e, rd2_e, src_b_forward_e, forward_b_e);
    end
    
    // ============================================================
    // --- GLOBAL CONTROL & PIPELINE WIRES (Declare these first!) ---
    // ============================================================
    wire [31:0] pc_next_f, pc_f, instr_f, pc_plus4_f;
    wire [31:0] pc_target_e;
    wire pc_src_e, stall_f, stall_d, flush_e;
    wire [31:0] result_w;
    wire [4:0]  rd_w;
    wire        reg_write_w;
    wire [31:0] alu_out_m;
    wire        cache_stall; // Global cache stall wire driven by dcache
    
    wire [9:0] w_vga_ship_x;
    wire [9:0] w_vga_laser_x;
    wire [9:0] w_vga_laser_y;
    wire [9:0] w_vga_alien_x;
    wire [9:0] w_vga_alien_y;
    wire [29:0] w_vga_alien_mask;
    wire [15:0] w_vga_score;
    wire [9:0] w_vga_elaser_x;
    wire [9:0] w_vga_elaser_y;
    wire w_vga_game_over;
    
    // 1. Declare a 2-bit register for counting
    reg [1:0] clk_count = 2'b00;
    wire clk_25mhz;

    // 2. Increment the counter on every positive edge of the 100MHz clock
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            clk_count <= 2'b00;
        end else begin
            clk_count <= clk_count + 1'b1;
        end
    end

    // 3. The MSB (bit 1) toggles at exactly 25 MHz!
    assign clk_25mhz = clk_count[1];

    // ============================================================
    // --- 1. FETCH STAGE (IF) ---
    // ============================================================

    // Freeze Fetch stage if either a hazard or a cache miss occurs
    assign pc_next_f = (pc_src_e) ? pc_target_e : (pc_f + 4);
    assign pc_plus4_f = pc_f + 4;
  
    program_counter PC_MOD (
        .clk(clk), .reset(reset), .en(!stall_f && !cache_stall), .pc_next(pc_next_f), .pc(pc_f)
    );

    instruction_memory IMEM (
        .address(pc_f), .instruction(instr_f)
    );

    // --- IF/ID Pipeline Register ---
    wire [31:0] instr_d, pc_d;

    pipe_reg #(32) reg_instr_id (.clk(clk), .reset(reset), .en(!stall_d && !cache_stall), .clr(pc_src_e), .d(instr_f), .q(instr_d));    
    pipe_reg #(32) reg_pc_id    (.clk(clk), .reset(reset), .en(!stall_d && !cache_stall), .clr(pc_src_e), .d(pc_f),    .q(pc_d));

    // ============================================================
    // --- 2. DECODE STAGE (ID) ---
    // ============================================================

    wire [31:0] rd1_d, rd2_d, imm_ext_d;
    wire [3:0]  alu_ctrl_d;
    wire        reg_write_d, alu_src_d, mem_write_d, branch_d;
    wire [1:0]  result_src_d;
    wire [4:0]  rs1_d = instr_d[19:15];
    wire [4:0]  rs2_d = instr_d[24:20];

    register_file REG (
        .clk(clk), .reg_write(reg_write_w), 
        .rs1(rs1_d), .rs2(rs2_d), .rd(rd_w),
        .write_data(result_w), .read_data1(rd1_d), .read_data2(rd2_d)
    );

    decoder DEC (
        .instruction(instr_d), .reg_write(reg_write_d), .alu_src(alu_src_d),
        .mem_write(mem_write_d), .result_src(result_src_d), .alu_control(alu_ctrl_d), .branch(branch_d)
    );

    imm_gen IMGEN (
        .instruction(instr_d), .imm_ext(imm_ext_d)
    );

    // ============================================================
    // --- 3. EXECUTE STAGE (EX) ---
    // ============================================================
    
    wire [31:0] rd1_e, rd2_e, imm_ext_e, pc_e;
    wire [4:0]  rs1_e, rs2_e, rd_e;
    wire [3:0]  alu_ctrl_e;
    wire        reg_write_e, alu_src_e, mem_write_e, branch_e;
    wire [1:0]  result_src_e;
    // FIX: must also flush on a taken branch (pc_src_e), not just on a
    // hazard-unit load-use stall (flush_e). Without this, the instruction
    // immediately after every taken branch spuriously executes once, since
    // your pipeline resolves branches in EX (2 fetches ahead) and needs
    // TWO flush stages, not one. This was causing infinite loops whenever
    // a taken branch's fall-through instruction was itself a branch.
    wire flush_ex_stage = (flush_e || pc_src_e) && !cache_stall;

    // ID/EX Pipeline Registers: Freeze during a cache stall
    pipe_reg #(1)  reg_rw_e     (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(reg_write_d),  .q(reg_write_e));
    pipe_reg #(1)  reg_mw_e     (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(mem_write_d),  .q(mem_write_e));
    pipe_reg #(1)  reg_asrc_e   (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(alu_src_d),    .q(alu_src_e));
    pipe_reg #(2)  reg_rsrc_e   (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(result_src_d), .q(result_src_e));
    pipe_reg #(4)  reg_alu_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(alu_ctrl_d),   .q(alu_ctrl_e));
    pipe_reg #(1)  reg_branch_e (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(branch_d),   .q(branch_e));
    pipe_reg #(32) reg_rd1_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(rd1_d),        .q(rd1_e));
    pipe_reg #(32) reg_rd2_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(rd2_d),        .q(rd2_e));
    pipe_reg #(32) reg_imm_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(imm_ext_d),    .q(imm_ext_e));
    pipe_reg #(5)  reg_rdaddr_e (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(instr_d[11:7]), .q(rd_e));
    pipe_reg #(32) reg_pc_e     (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(pc_d),         .q(pc_e));
    pipe_reg #(5)  reg_rs1_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(rs1_d),        .q(rs1_e));
    pipe_reg #(5)  reg_rs2_e    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(flush_ex_stage), .d(rs2_d),        .q(rs2_e));
    
    // Forwarding & Branch Logic
    wire [1:0] forward_a_e, forward_b_e;
    wire [31:0] src_a_e, src_b_forward_e;
    wire [31:0] alu_out_e;
    wire zero_e; 
    
    assign pc_src_e = branch_e & zero_e;
    assign pc_target_e = pc_e + imm_ext_e;
    
    // ALU Input Muxes
    assign src_a_e = (forward_a_e == 2'b00) ? rd1_e :
                     (forward_a_e == 2'b01) ? result_w : alu_out_m;

    assign src_b_forward_e = (forward_b_e == 2'b00) ? rd2_e :
                             (forward_b_e == 2'b01) ? result_w : alu_out_m;

    wire [31:0] src_b_final_e = (alu_src_e) ? imm_ext_e : src_b_forward_e;

    alu ALU_MOD (
        .A(src_a_e), 
        .B(src_b_final_e), 
        .alu_control(alu_ctrl_e), 
        .Result(alu_out_e),
        .Zero(zero_e)
    );

    // ============================================================
    // --- HAZARD & FORWARDING UNITS ---
    // ============================================================
    
    forwarding_unit FWU (
        .rs1_e(rs1_e), .rs2_e(rs2_e), .rd_m(rd_m), .rd_w(rd_w),
        .reg_write_m(reg_write_m), .reg_write_w(reg_write_w),
        .forward_a_e(forward_a_e), .forward_b_e(forward_b_e)
    );

    hazard_unit HU (
        .rs1_d(rs1_d), .rs2_d(rs2_d), .rd_e(rd_e),
        .result_src_e0(result_src_e[0]), .cache_stall(cache_stall),
        .stall_f(stall_f), .stall_d(stall_d), .flush_e(flush_e)
    );

    // ============================================================
    // --- 4. MEMORY STAGE (MEM) ---
    // ============================================================

    wire [31:0] write_data_m;
    wire [4:0]  rd_m;
    wire        reg_write_m, mem_write_m;
    wire [1:0]  result_src_m;
    wire [31:0] read_data_m;
    wire [31:0] dmem_raw_data;

    wire [31:0] cache_to_dmem_addr;
    wire [31:0] cache_to_dmem_wdata;
    wire        cache_to_dmem_we;

    //SPACE INVADERS TIME!!!
    // Space Invaders Game State Registers
    reg [9:0] io_ship_x;
    reg [9:0] io_laser_x;
    reg [9:0] io_laser_y;
    reg [9:0] io_alien_x;
    reg [9:0] io_alien_y;
    reg [29:0] io_alien_mask;
    reg [15:0] io_score;
    reg [9:0] io_elaser_x;
    reg [9:0] io_elaser_y;
    reg io_game_over;
    reg [19:0] io_sound_period;
    reg [9:0] io_explosion_x;
    reg [9:0] io_explosion_y;

    wire is_mmio_m = alu_out_m[31];  // top bit set = MMIO region

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            io_ship_x     <= 10'd300;
            io_laser_x    <= 10'd0;
            io_laser_y    <= 10'd0;
            io_alien_x    <= 10'd200;
            io_alien_y    <= 10'd50;
            io_alien_mask <= 30'h3FFFFFFF;
            io_score      <= 16'd0;
            io_elaser_x   <= 10'd0;
            io_elaser_y   <= 10'd0;
            io_game_over  <= 1'b0;
            io_sound_period <= 20'd0;
            io_explosion_x <= 10'd0;
            io_explosion_y <= 10'd0;
        end else if (mem_write_m && is_mmio_m) begin
            case (alu_out_m[7:0])
                8'h00: io_ship_x     <= write_data_m[9:0];
                8'h04: io_laser_x    <= write_data_m[9:0];
                8'h08: io_laser_y    <= write_data_m[9:0];
                8'h0C: io_alien_x    <= write_data_m[9:0];
                8'h10: io_alien_y    <= write_data_m[9:0];
                8'h14: io_alien_mask <= write_data_m[29:0];
                8'h18: io_score      <= write_data_m[15:0];
                8'h1C: io_elaser_x   <= write_data_m[9:0];
                8'h24: io_elaser_y   <= write_data_m[9:0];
                8'h28: io_game_over  <= write_data_m[0];
                8'h2C: io_sound_period <= write_data_m[19:0];
                8'h30: io_explosion_x <= write_data_m[9:0];
                8'h34: io_explosion_y <= write_data_m[9:0];
            endcase
        end
    end

    assign w_vga_ship_x     = io_ship_x;
    assign w_vga_laser_x    = io_laser_x;
    assign w_vga_laser_y    = io_laser_y;
    assign w_vga_alien_x    = io_alien_x;
    assign w_vga_alien_y    = io_alien_y;
    assign w_vga_alien_mask = io_alien_mask;
    assign w_vga_score = io_score;
    assign w_vga_elaser_x = io_elaser_x;
    assign w_vga_elaser_y = io_elaser_y;
 
    // ============================================================
    // Death animation timer (hardware-managed): writing explosion_y
    // (paired with explosion_x, written just before it each hit) starts
    // a ~150ms countdown during which vga_controller renders the
    // explosion sprite at that position. Decoupled into its own always
    // block since the shared MMIO-write block above only fires on the
    // specific cycle something is written -- gating the decrement behind
    // that would pause the timer almost every tick, since some other
    // register (ship_x, alien_x, etc.) is written nearly every tick.
    // ============================================================
    localparam [24:0] EXPLOSION_DURATION = 25'd15_000_000; // ~150ms @ 100MHz
    reg [24:0] explosion_counter;
    wire explosion_trigger = mem_write_m && is_mmio_m && (alu_out_m[7:0] == 8'h34);
    wire w_vga_explosion_active = (explosion_counter != 25'd0);
 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            explosion_counter <= 25'd0;
        end else if (explosion_trigger) begin
            explosion_counter <= EXPLOSION_DURATION;
        end else if (explosion_counter != 25'd0) begin
            explosion_counter <= explosion_counter - 25'd1;
        end
    end
    assign w_vga_game_over = io_game_over;

    // --- Debounced buttons ---
    wire btn0_db, btn3_db, btn4_db;
    debounce DB0 (.clk(clk), .btn_in(btn[0]), .btn_out(btn0_db));
    debounce DB3 (.clk(clk), .btn_in(btn[3]), .btn_out(btn3_db));
    debounce DB4 (.clk(clk), .btn_in(btn[4]), .btn_out(btn4_db));

    wire [31:0] io_btn_data = {27'b0, btn4_db, btn3_db, 1'b0, 1'b0, btn0_db};

    wire [31:0] mmio_read_data = (alu_out_m[7:0] == 8'h20) ? io_btn_data :
                             (alu_out_m[7:0] == 8'h00) ? {22'b0, io_ship_x} :
                             32'b0;

    wire [31:0] cache_output_data;

    assign read_data_m = is_mmio_m ? mmio_read_data : cache_output_data;


    // EX/MEM Pipeline Registers: Freeze during a cache stall to hold the load instruction stable
    pipe_reg #(1)  reg_rw_m    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(reg_write_e),  .q(reg_write_m));
    pipe_reg #(1)  reg_mw_m    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(mem_write_e),  .q(mem_write_m));
    pipe_reg #(2)  reg_rsrc_m  (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(result_src_e), .q(result_src_m));
    pipe_reg #(32) reg_alu_m   (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(alu_out_e),    .q(alu_out_m));
    pipe_reg #(32) reg_wdata_m (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(src_b_forward_e), .q(write_data_m));
    pipe_reg #(5)  reg_rdaddr_m(.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(rd_e),         .q(rd_m));

    dcache DC_CACHE (
        .clk(clk),
        .reset(reset),
        .addr(alu_out_m),
        .write_data(write_data_m),
        .mem_read(result_src_m[0] & !is_mmio_m), 
        .mem_write(mem_write_m & !is_mmio_m), 
        .read_data(cache_output_data),
        .cache_hit(),            
        .stall_pipeline(cache_stall), 
        .mem_addr(cache_to_dmem_addr),
        .mem_wdata(cache_to_dmem_wdata),
        .mem_write_en(cache_to_dmem_we),
        .mem_rdata(dmem_raw_data) 
    );

    data_mem DMEM (
        .clk(clk), 
        .addr(cache_to_dmem_addr), 
        .write_data(cache_to_dmem_wdata), 
        .mem_write(cache_to_dmem_we), 
        .read_data(dmem_raw_data)
    );
    
    // ============================================================
    // --- 5. WRITE BACK STAGE (WB) ---
    // ============================================================

    wire [31:0] alu_out_w, read_data_w;
    wire [1:0]  result_src_w;

    // MEM/WB Pipeline Registers: Restored to clean 1'b1 enables so data passes straight through without timing slips
    pipe_reg #(1)  reg_rw_w    (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(reg_write_m),  .q(reg_write_w));
    pipe_reg #(2)  reg_rsrc_w  (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(result_src_m), .q(result_src_w));
    pipe_reg #(32) reg_alu_w   (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(alu_out_m),    .q(alu_out_w));
    pipe_reg #(32) reg_rdata_w (.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(read_data_m),  .q(read_data_w));
    pipe_reg #(5)  reg_rdaddr_w(.clk(clk), .reset(reset), .en(!cache_stall), .clr(1'b0), .d(rd_m),         .q(rd_w));
    
    assign result_w = (result_src_w == 2'b01) ? read_data_w : alu_out_w;
    
    // ============================================================
    // --- 6. VGA RENDERING SUB-SYSTEM ---
    // ============================================================

    // Note: The VGA module requires a 25MHz clock signal. 
    // If you don't have a clock wizard IP generated yet, you can use 
    // your standard system 'clk' for testing, but a 25MHz clock is 
    // required for a real monitor to recognize the signal!
    
    vga_controller VGA_DISPLAY (
        .clk_25mhz(clk_25mhz),             // Feed your pixel clock here
        .reset(reset),
        
        // Connect directly to your Space Invaders hardware registers
        .ship_x(io_ship_x),
        .laser_x(io_laser_x),
        .laser_y(io_laser_y),
        .alien_x(io_alien_x),
        .alien_y(io_alien_y),
        .io_alien_mask(io_alien_mask),
        .score(w_vga_score),
        .elaser_x(w_vga_elaser_x),
        .elaser_y(w_vga_elaser_y),
        .explosion_x(io_explosion_x),
        .explosion_y(io_explosion_y),
        .explosion_active(w_vga_explosion_active),
        .game_over(w_vga_game_over),
        
        // Pass these straight out to the physical Basys 3 pins
        .hsync(hsync),
        .vsync(vsync),
        .red(red),
        .green(green),
        .blue(blue)
    );

    // ============================================================
    // 7. SOUND (passive buzzer on JA1)
    // Runs on the 100MHz system clock. Toggles the output every
    // io_sound_period cycles, giving a square wave whose frequency is
    // 100_000_000 / (2 * io_sound_period). io_sound_period == 0 means
    // silent (the RISC-V program is the only thing that ever loads a
    // nonzero period, and it's responsible for silencing it again).
    // ============================================================
    reg [19:0] sound_counter;
    reg sound_wave;
 
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            sound_counter <= 20'd0;
            sound_wave <= 1'b0;
        end else if (io_sound_period == 20'd0) begin
            sound_counter <= 20'd0;
            sound_wave <= 1'b0;
        end else if (sound_counter == 20'd0) begin
            sound_counter <= io_sound_period - 20'd1;
            sound_wave <= ~sound_wave;
        end else begin
            sound_counter <= sound_counter - 20'd1;
        end
    end
 
    assign buzzer = sound_wave;
 
endmodule