`timescale 1ns / 1ps

module decoder(
    input [31:0] instruction,
    output reg reg_write,
    output reg alu_src,
    output reg mem_write,
    output reg branch,
    output reg [1:0] result_src,
    output reg [3:0] alu_control
    );

    wire [6:0] opcode = instruction[6:0];
    wire [2:0] funct3 = instruction[14:12];
    wire [6:0] funct7 = instruction[31:25];

    always @(*) begin

        reg_write = 0; 
        alu_src = 0; 
        mem_write = 0; 
        result_src = 0; 
        alu_control = 0;
        branch = 0;

        case(opcode)
            7'b0110011: begin

                reg_write = 1;
                alu_src = 0;
                result_src = 2'b00;
                
                case(funct3)
                    3'b000: alu_control = (funct7[5]) ? 4'b0001 : 4'b0000; // SUB : ADD
                    3'b001: alu_control = 4'b0010; // SLL
                    3'b010: alu_control = 4'b0011; // SLT
                    3'b100: alu_control = 4'b0101; // XOR
                    3'b101: alu_control = (funct7[5]) ? 4'b0111 : 4'b0110; // SRA : SRL
                    3'b110: alu_control = 4'b1000; // OR
                    3'b111: alu_control = 4'b1001; // AND
                endcase
            end

            7'b0010011: begin
                reg_write = 1;
                alu_src = 1;      // Use the Immediate!
                result_src = 2'b00;
                case(funct3)
                    3'b000: alu_control = 4'b0000; // ADDI
                    3'b110: alu_control = 4'b1000; // ORI
                    3'b111: alu_control = 4'b1001; // ANDI
                    3'b001: alu_control = 4'b0010; // slli (pass shift left command to ALU)
                    3'b101: alu_control = 4'b0110; // srli (pass shift right command to ALU)
                    default: alu_control = 4'b0000;
                endcase
            end

            7'b0000011: begin
                reg_write = 1;
                alu_src = 1;
                result_src = 2'b01;
                alu_control = 4'b0000;
            end
            
            7'b0100011: begin
                mem_write = 1;
                alu_src = 1;
                reg_write = 0;
                alu_control = 4'b0000;
            end

            7'b1100011: begin
                branch = 1;
                alu_control = 4'b0001;
                alu_src = 0;
                reg_write = 0;
            end

        endcase

    end

endmodule