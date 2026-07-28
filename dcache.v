module dcache (
    input wire clk,
    input wire reset,
    input wire [31:0] addr,       // From CPU pipeline
    input wire [31:0] write_data,  // From CPU pipeline
    input wire mem_read,          // High if instruction is lw
    input wire mem_write,     // High if instruction is sw
    input  wire [31:0] mem_rdata,

    output reg  [31:0] mem_addr,       // Address sent to Main Memory
    output reg  [31:0] mem_wdata,      // Data sent to Main Memory
    output reg         mem_write_en,
    output wire [31:0] read_data, // Data going back to CPU
    output wire cache_hit,         // High if we found the data!
    output wire stall_pipeline     // Drives top.v's cache_stall wire
);

    localparam STATE_IDLE   = 2'b00; // Waiting for CPU requests
    localparam STATE_FETCH  = 2'b01; // Cache miss! Fetching from slow Main Memory
    localparam STATE_UPDATE = 2'b10; // Writing data into cache arrays
    localparam STATE_DONE = 2'b11;
    
    
    reg [1:0] current_state, next_state;

    reg        valid_array [0:3];  
    reg [27:0] tag_array   [0:3];  
    reg [31:0] data_array  [0:3];


    wire [1:0]  index = addr[3:2];
    wire [27:0] tag   = addr[31:4];

    
    assign cache_hit = valid_array[index] && (tag_array[index] == tag);
    
    reg [31:0] read_data_reg;

    always @(posedge clk) begin
        if (current_state == STATE_UPDATE)
            read_data_reg <= mem_rdata;
    end

    assign read_data = (cache_hit)                   ? data_array[index] :
                       (current_state == STATE_DONE) ? read_data_reg :
                        32'b0;
    
    // Stalls top.v ONLY while the state machine is handling the miss cycles
    wire miss_detected = mem_read && !cache_hit;

    assign stall_pipeline = miss_detected || (current_state == STATE_FETCH) || (current_state == STATE_UPDATE) || (current_state == STATE_DONE);
  

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            current_state <= STATE_IDLE;

            for (i = 0; i < 4; i = i + 1) begin
                valid_array[i] <= 1'b0;
                tag_array[i]   <= 28'b0;
                data_array[i]  <= 32'b0;
            end
        end else begin

            current_state <= next_state;

            if(current_state == STATE_UPDATE) begin
                valid_array[index] <= 1'b1;
                tag_array[index] <= tag;
                data_array[index] <= mem_rdata;
            end
        end
    end
    
    always @(*) begin
        next_state = current_state;
        case (current_state)
            STATE_IDLE: begin
                if ((mem_read || mem_write) && !cache_hit) begin
                    next_state = STATE_FETCH;
                end
            end
            STATE_FETCH: begin
                next_state = STATE_UPDATE;
            end
            STATE_UPDATE: begin
                next_state = STATE_DONE;
            end
            STATE_DONE: begin
                next_state = STATE_IDLE;      
            end
            default: next_state = STATE_IDLE;
        endcase    
    end

    always @(*) begin
    // By default, pass the CPU's memory commands straight through to Main Memory
        mem_addr     = addr;
        mem_wdata    = write_data;
        mem_write_en = mem_write; 

    end
    
 
    always @(posedge clk) begin
        if (mem_read || mem_write)
        $display("CACHE OP | write=%b | read=%b | addr=%0d | hit=%b | wdata=%0d | rdata=%0d",
            mem_write, mem_read, addr, cache_hit, write_data, read_data);
    end
    
endmodule