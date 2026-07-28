module data_mem(
    input clk,
    input [31:0] addr,
    input [31:0] write_data,
    input mem_write,
    output [31:0] read_data
    );

    reg [31:0] ram [0:255];
    
    integer i;
    initial begin
    
        for (i = 0; i < 256; i = i + 1) begin
            ram[i] = 32'b0;
        end
        
        ram[0] = 32'h80000020; // Data Address 0 holds the Buttons pointer
        ram[1] = 32'h80000000; // Data Address 4 (Index 1) holds the Ship_X pointer
    end
    
    always @(posedge clk) begin
        if (mem_write)
            ram[addr >> 2] <= write_data;
    end

    assign read_data = ram[addr >> 2];
    
endmodule