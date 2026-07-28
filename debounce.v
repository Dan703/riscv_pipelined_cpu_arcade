module debounce (
    input wire clk,
    input wire btn_in,
    output reg btn_out
);
    reg [19:0] counter = 0;
    reg btn_sync_0 = 0, btn_sync_1 = 0;
    initial btn_out = 0;

    always @(posedge clk) begin
        btn_sync_0 <= btn_in;
        btn_sync_1 <= btn_sync_0;
    end

    always @(posedge clk) begin
        if (btn_sync_1 == btn_out) begin
            counter <= 0;
        end else begin
            counter <= counter + 1;
            if (counter >= 20'd1_000_000) begin
                btn_out <= btn_sync_1;
                counter <= 0;
            end
        end
    end
endmodule