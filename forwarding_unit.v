`timescale 1ns / 1ps


module forwarding_unit(
    input  wire [4:0] rs1_e, rs2_e,      // Sources in Execute
    input  wire [4:0] rd_m, rd_w,        // Destinations in MEM and WB
    input  wire       reg_write_m, reg_write_w,
    output reg  [1:0] forward_a_e, forward_b_e
);
    
    always @(*) begin
        
        forward_a_e = 2'b00;
        forward_b_e = 2'b00;

        if(reg_write_m && (rd_m != 0)) begin
            if (rd_m == rs1_e) forward_a_e = 2'b10;
            if (rd_m == rs2_e) forward_b_e = 2'b10;
        end

        if (reg_write_w && (rd_w != 0)) begin
            if (rd_w == rs1_e && forward_a_e == 2'b00) forward_a_e = 2'b01;
            if (rd_w == rs2_e && forward_b_e == 2'b00) forward_b_e = 2'b01;
        end
    end
endmodule