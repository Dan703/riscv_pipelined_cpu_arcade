module pipe_reg #(parameter WIDTH = 32) (
    input  wire             clk,
    input  wire             reset,
    input  wire             en,    // 1 = Pass data, 0 = Freeze (Stall)
    input  wire             clr,   // 1 = Wipe data to 0 (Flush/NOP)
    input  wire [WIDTH-1:0] d,
    output reg  [WIDTH-1:0] q
);

    always @(posedge clk or posedge reset) begin

    if(reset)
        q <= 0;
    else if(clr)
        q <= 0;
    else if (en)
        q <= d;
        
    end

endmodule