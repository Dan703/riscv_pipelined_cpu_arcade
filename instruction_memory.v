module instruction_memory(
        input [31:0] address,
        output [31:0] instruction
    );

    reg [31:0] rom [0:511];

    assign instruction = rom[address[10:2]];
    
    integer i;

   initial begin
        // 1. MUST initialize all to 0 to prevent red lines
        // If the PC goes to an address you didn't define, 
        // it reads 0 instead of Red X.
        for (i = 0; i < 512; i = i + 1) begin
            rom[i] = 32'h00000000;
        end

       // Load from the file
        $readmemh("program.mem", rom);
        
    end
    
endmodule