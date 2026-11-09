// One reserved byte response slot, one AXI transaction, fixed ID=0.
// Single-beat INCR, ARSIZE=0. Never aligns down or reads padding.
// Forward the first address and a complete response without extra register-only
// cycles. Capture either channel when stalled; malformed bursts still drain.
module w4a8_axi_read #(parameter integer ADDR_WIDTH=32)(
    input logic clk,rst,
    input logic cmd_valid, output logic cmd_ready, input logic [ADDR_WIDTH-1:0] cmd_addr,
    output logic rsp_valid, input logic rsp_ready,
    output logic [7:0] rsp_data, output logic rsp_error, output logic idle,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output wire [2:0] arsize,
    output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast
);
    typedef enum logic [2:0] {EMPTY,ADDRESS,DATA,DRAIN,RESPONSE} state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] saved_addr;
    logic [7:0] saved_data;
    logic saved_error;
    wire forward_response=state==DATA && rvalid && rlast;
    assign arid=0;assign arlen=0;assign arsize=0;assign arburst=1;
    assign idle=state==EMPTY;
    assign cmd_ready=idle && !rst;
    assign arvalid=(state==ADDRESS || (idle && cmd_valid)) && !rst;
    assign araddr=idle?cmd_addr:saved_addr;
    assign rready=(state==DATA || state==DRAIN) && !rst;
    assign rsp_valid=(state==RESPONSE || forward_response) && !rst;
    assign rsp_data=state==RESPONSE?saved_data:rdata[saved_addr[2:0]*8 +:8];
    assign rsp_error=state==RESPONSE?saved_error:(rresp!=0 || rid!=0);
    always_ff @(posedge clk) begin
        if(rst) begin state<=EMPTY;saved_addr<=0;saved_data<=0;saved_error<=0;end
        else case(state)
            EMPTY:if(cmd_valid) begin
                saved_addr<=cmd_addr;saved_error<=0;
                state<=arready?DATA:ADDRESS;
            end
            ADDRESS:if(arready) state<=DATA;
            DATA:if(rvalid) begin
                saved_data<=rdata[saved_addr[2:0]*8 +:8];
                saved_error<=rresp!=0 || rid!=0 || !rlast;
                if(!rlast) state<=DRAIN;
                else state<=rsp_ready?EMPTY:RESPONSE;
            end
            // No response is exposed until the malformed burst reaches RLAST.
            DRAIN:if(rvalid && rlast) state<=RESPONSE;
            RESPONSE:if(rsp_ready) state<=EMPTY;
            default:state<=EMPTY;
        endcase
    end
endmodule

// One bounded, naturally aligned AXI beat. cmd_bytes is an upper bound (1..8);
// rsp_bytes reports the largest aligned power-of-two transfer within that bound.
// No alignment down, allocation padding, 4KiB crossing or speculative over-read.
module w4a8_axi_read_chunk #(parameter integer ADDR_WIDTH=64)(
    input logic clk,rst,
    input logic cmd_valid,output logic cmd_ready,input logic [ADDR_WIDTH-1:0] cmd_addr,
    input logic [3:0] cmd_bytes,
    output logic rsp_valid,input logic rsp_ready,output logic [63:0] rsp_data,
    output logic [3:0] rsp_bytes,output logic rsp_error,idle,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output wire [7:0] arlen,output logic [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast
);
    typedef enum logic [2:0] {EMPTY,ADDRESS,DATA,DRAIN,RESPONSE} state_t;
    state_t state;
    logic [ADDR_WIDTH-1:0] saved_addr;
    logic [63:0] saved_data;
    logic [2:0] saved_size,chosen_size;
    logic saved_error;
    always_comb begin
        chosen_size=0;
        if(cmd_bytes>=8 && cmd_addr[2:0]==0) chosen_size=3;
        else if(cmd_bytes>=4 && cmd_addr[1:0]==0) chosen_size=2;
        else if(cmd_bytes>=2 && cmd_addr[0]==0) chosen_size=1;
    end
    wire forward_response=state==DATA && rvalid && rlast;
    assign arid=0;assign arlen=0;assign arburst=1;
    assign idle=state==EMPTY;
    assign cmd_ready=idle && !rst;
    assign arvalid=(state==ADDRESS || (idle && cmd_valid)) && !rst;
    assign araddr=idle?cmd_addr:saved_addr;
    assign arsize=idle?chosen_size:saved_size;
    assign rready=(state==DATA || state==DRAIN) && !rst;
    assign rsp_valid=(state==RESPONSE || forward_response) && !rst;
    assign rsp_data=state==RESPONSE?saved_data:(rdata >> (saved_addr[2:0]*8));
    assign rsp_bytes=4'd1<<saved_size;
    assign rsp_error=state==RESPONSE?saved_error:(rresp!=0 || rid!=0);
    always_ff @(posedge clk) begin
        if(rst) begin state<=EMPTY;saved_addr<=0;saved_data<=0;saved_error<=0;saved_size<=0;end
        else case(state)
            EMPTY:if(cmd_valid) begin
                saved_addr<=cmd_addr;saved_size<=chosen_size;saved_error<=0;
                state<=arready?DATA:ADDRESS;
            end
            ADDRESS:if(arready) state<=DATA;
            DATA:if(rvalid) begin
                saved_data<=rdata >> (saved_addr[2:0]*8);
                saved_error<=rresp!=0 || rid!=0 || !rlast;
                if(!rlast) state<=DRAIN;else state<=rsp_ready?EMPTY:RESPONSE;
            end
            DRAIN:if(rvalid && rlast) state<=RESPONSE;
            RESPONSE:if(rsp_ready) state<=EMPTY;
            default:state<=EMPTY;
        endcase
    end
    // synthesis translate_off
    always @(posedge clk) if(!rst && cmd_valid && cmd_ready)
        if(cmd_bytes==0 || cmd_bytes>8) $fatal(1,"CHUNK_INVALID_LENGTH");
    // synthesis translate_on
endmodule

// Bounded activation-row prefetch. One outstanding AR; reserve MAX_BEATS slots
// before issuing it. Store the entire burst before exposing any of its data, so
// a fault on any beat cannot turn a partial burst into a successful response.
// cmd_span is the caller's proven contiguous useful-byte range, not allocation
// padding. Only full-width aligned reads burst; narrow heads/tails stay single.
module w4a8_axi_read_burst #(
    parameter integer ADDR_WIDTH=64, MAX_BEATS=4
)(
    input logic clk,rst,
    input logic cmd_valid,output logic cmd_ready,input logic [ADDR_WIDTH-1:0] cmd_addr,
    input logic [3:0] cmd_bytes,input logic [15:0] cmd_span,
    output logic rsp_valid,input logic rsp_ready,output logic [63:0] rsp_data,
    output logic [3:0] rsp_bytes,output logic rsp_error,idle,
    output logic arvalid,input logic arready,output logic [ADDR_WIDTH-1:0] araddr,
    output wire [3:0] arid,output logic [7:0] arlen,output logic [2:0] arsize,output wire [1:0] arburst,
    input logic rvalid,output logic rready,input logic [63:0] rdata,
    input logic [3:0] rid,input logic [1:0] rresp,input logic rlast
);
    localparam integer PTR_W=MAX_BEATS>1?$clog2(MAX_BEATS):1;
    typedef enum logic [2:0] {EMPTY,ADDRESS,DATA,DRAIN,RESPONSE} state_t;
    state_t state;
    logic [63:0] fifo[0:MAX_BEATS-1],saved_data;
    logic [ADDR_WIDTH-1:0] saved_addr,cache_addr;
    logic [2:0] saved_size,chosen_size,cache_size;
    logic [7:0] saved_len,chosen_len;
    logic [8:0] received,cache_count;
    logic [PTR_W-1:0] cache_ptr;
    logic saved_error,burst_error;
    integer beats,boundary_beats;
    wire cache_hit=cache_count!=0 && cmd_addr==cache_addr &&
        cmd_bytes>=(4'd1<<cache_size) && cmd_span>=(16'd1<<cache_size);
    always_comb begin
        chosen_size=0;
        if(cmd_bytes>=8 && cmd_addr[2:0]==0) chosen_size=3;
        else if(cmd_bytes>=4 && cmd_addr[1:0]==0) chosen_size=2;
        else if(cmd_bytes>=2 && cmd_addr[0]==0) chosen_size=1;
        beats=1;
        boundary_beats=(4096-integer'(cmd_addr[11:0]))/8;
        if(chosen_size==3) begin
            beats=integer'(cmd_span)/8;
            if(beats>MAX_BEATS) beats=MAX_BEATS;
            if(beats>boundary_beats) beats=boundary_beats;
            if(beats<1) beats=1;
        end
        chosen_len=8'(beats-1);
    end
    wire forward_response=state==DATA && saved_len==0 && rvalid && rlast;
    assign arid=0;assign arburst=1;
    assign idle=state==EMPTY;
    assign cmd_ready=idle && !rst;
    assign arvalid=(state==ADDRESS || (idle && cmd_valid && !cache_hit)) && !rst;
    assign araddr=idle?cmd_addr:saved_addr;
    assign arsize=idle?chosen_size:saved_size;
    assign arlen=idle?chosen_len:saved_len;
    assign rready=(state==DATA || state==DRAIN) && !rst;
    assign rsp_valid=(state==RESPONSE || forward_response) && !rst;
    assign rsp_data=state==RESPONSE?saved_data:(rdata>>(saved_addr[2:0]*8));
    assign rsp_bytes=4'd1<<saved_size;
    assign rsp_error=state==RESPONSE?saved_error:(rresp!=0 || rid!=0);
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=EMPTY;saved_addr<=0;saved_data<=0;saved_size<=0;saved_len<=0;
            saved_error<=0;burst_error<=0;received<=0;cache_count<=0;
            cache_addr<=0;cache_ptr<=0;cache_size<=0;
        end else case(state)
            EMPTY:if(cmd_valid) begin
                saved_addr<=cmd_addr;saved_error<=0;burst_error<=0;received<=0;
                if(cache_hit) begin
                    saved_size<=cache_size;saved_data<=fifo[cache_ptr];
                    cache_ptr<=cache_ptr+1'b1;cache_count<=cache_count-1'b1;
                    cache_addr<=cache_addr+(ADDR_WIDTH'(1)<<cache_size);state<=RESPONSE;
                end else begin
                    cache_count<=0;saved_size<=chosen_size;saved_len<=chosen_len;
                    state<=arready?DATA:ADDRESS;
                end
            end
            ADDRESS:if(arready) state<=DATA;
            DATA:if(rvalid) begin
                fifo[PTR_W'(received)]<=rdata>>(saved_addr[2:0]*8);
                burst_error<=burst_error || rresp!=0 || rid!=0;
                received<=received+1'b1;
                if(received==0) saved_data<=rdata>>(saved_addr[2:0]*8);
                if(rlast) begin
                    saved_error<=burst_error || rresp!=0 || rid!=0 || received!={1'b0,saved_len};
                    if(!burst_error && rresp==0 && rid==0 && received=={1'b0,saved_len}) begin
                        cache_count<={1'b0,saved_len};cache_size<=saved_size;
                        cache_addr<=saved_addr+(ADDR_WIDTH'(1)<<saved_size);cache_ptr<=PTR_W'(1);
                    end else cache_count<=0;
                    state<=saved_len==0 && rsp_ready?EMPTY:RESPONSE;
                end else if(received=={1'b0,saved_len}) begin
                    saved_error<=1;cache_count<=0;state<=DRAIN;
                end
            end
            DRAIN:if(rvalid && rlast) state<=RESPONSE;
            RESPONSE:if(rsp_ready) state<=EMPTY;
            default:state<=EMPTY;
        endcase
    end
    // synthesis translate_off
    initial if(!(MAX_BEATS==1 || MAX_BEATS==2 || MAX_BEATS==4 || MAX_BEATS==8))
        $fatal(1,"BURST_INVALID_CAPACITY");
    always @(posedge clk) if(!rst && cmd_valid && cmd_ready)
        if(cmd_bytes==0 || cmd_bytes>8 || cmd_span<cmd_bytes)
            $fatal(1,"BURST_INVALID_RANGE");
    // synthesis translate_on
endmodule
