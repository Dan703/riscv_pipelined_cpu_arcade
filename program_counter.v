`timescale 1ns / 1ps

module program_counter(
        input clk,
        input reset, 
        input en,
        input wire [31:0] pc_next,
        output reg [31:0] pc
    );

    always @(posedge clk) begin

        if (reset) begin
            pc <= 32'b0;
        end else if (en) begin
            pc <= pc_next;
        end

    end

endmodule