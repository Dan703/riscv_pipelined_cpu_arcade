`timescale 1ns / 1ps

module hazard_unit(
    input  wire [4:0] rs1_d, rs2_d,      // Registers being read in Decode
    input  wire [4:0] rd_e,              // Register being written in Execute
    input  wire       result_src_e0,     // result_src_e[0] is 1 if it's a 'lw'
    input  wire       cache_stall,
    output reg        stall_f, stall_d, flush_e
);
                                                
    wire lw_stall;

    assign lw_stall = result_src_e0 && ((rd_e == rs1_d) || (rd_e == rs2_d));

    always @(*) begin

        stall_f = 0;
        stall_d = 0;
        flush_e = 0;

        if (cache_stall) begin
            stall_f = 1;
            stall_d = 1;
        end

        else if(lw_stall) begin
            stall_f = 1;
            stall_d = 1;
            flush_e = 1;
        end
        
    end
endmodule