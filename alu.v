`timescale 1ns / 1ps

module alu(
        input [31:0] A,
        input [31:0] B,
        input [3:0] alu_control,
        output reg [31:0] Result,
        output Zero
    );

    always @(*) begin
        case(alu_control)
            4'b0000: Result = A + B;                      // ADD
            4'b0001: Result = A - B;                      // SUB
            4'b0010: Result = A << B[4:0];                // SLL (Shift Left)
            4'b0011: Result = ($signed(A) < $signed(B));  // SLT (Set Less Than)
            4'b0101: Result = A ^ B;                      // XOR
            4'b0110: Result = A >> B[4:0];                // SRL (Shift Right)
            4'b0111: Result = $signed(A) >>> B[4:0];      // SRA (Shift Right Arith)
            4'b1000: Result = A | B;                      // OR
            4'b1001: Result = A & B;                      // AND
            default: Result = 32'b0;
        endcase
    end

    assign Zero = (Result == 0);

endmodule
 