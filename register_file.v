`timescale 1ns / 1ps

module register_file(
    input clk,
    input reg_write,
    input [4:0] rs1,
    input [4:0] rs2,
    input [4:0] rd,
    input [31:0] write_data,
    output [31:0] read_data1,
    output [31:0] read_data2
    );

    reg [31:0] registers [0:31];
    
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] = 32'h0;
        end
    end

    assign read_data1 = (rs1 == 5'b0)                    ? 32'b0 :
                    (reg_write && rd == rs1 && rd != 0) ? write_data :
                    registers[rs1];

    assign read_data2 = (rs2 == 5'b0)                    ? 32'b0 :
                    (reg_write && rd == rs2 && rd != 0) ? write_data :
                    registers[rs2];


    always @(negedge clk) begin
        if (reg_write && rd != 5'b0) begin
            registers[rd] <= write_data;
        end
    end
    
    
endmodule