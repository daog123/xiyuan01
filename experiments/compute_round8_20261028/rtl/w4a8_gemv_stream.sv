// Single-row W4A8 path. 8-byte ingress, 64 physical product lanes, group32.
// Stream: A bytes, packed uint16 SX groups, then for each N tile and K group:
// packed INT4 weights column-by-column, followed by packed uint16 SW columns.
// Each section has a contiguous low-bit keep mask on its final beat.
module w4a8_gemv_stream #(
    parameter integer ROWS=8,COLS=8,GROUP_SIZE=32,MAX_N=64,MAX_K=4096,
    parameter integer POST_LANES=2
)(
    input logic clk,rst,start,load_pause,array_pause,post_pause,
    output logic start_ready,busy,done,error,
    input logic [15:0] cfg_n,cfg_k,
    input logic in_valid,output logic in_ready,
    input logic [63:0] in_data,input logic [7:0] in_keep,
    output logic out_valid,input logic out_ready,
    output logic [15:0] out_n,output logic out_last,
    output logic signed [31:0] out_data,
    output logic [31:0] total_cycles,input_beats,weight_bytes,activation_bytes,
        sx_bytes,sw_bytes,valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles
);
    localparam integer GROUPS=(MAX_K+GROUP_SIZE-1)/GROUP_SIZE;
    localparam integer WSPAN=(GROUP_SIZE+1)/2;
    localparam integer ADEPTH=(MAX_K+ROWS-1)/ROWS;
    typedef enum logic [2:0] {IDLE,WAIT_BANK,CLEAR,PRIME,RUN,REDUCE,POST,OUTPUTS} cstate_t;
    typedef enum logic [2:0] {LOAD_A,LOAD_SX,LOAD_W,LOAD_SW,LOAD_DONE} lstate_t;
    cstate_t state;
    lstate_t load_state;
    logic [15:0] n,k,ng,lnt,lg,load_pos,active_nt,active_g,active_nl,active_kl,run_k,output_col;
    logic writer,reader;
    logic [1:0] ready_bank;
    logic [15:0] bank_nt[0:1],bank_g[0:1];
    wire [15:0] sx_value[0:3];
    logic [7:0] weights[0:1][0:COLS-1][0:WSPAN-1];
    logic [15:0] scales[0:1][0:COLS-1];
    wire signed [7:0] a_q[0:ROWS-1];
    logic signed [31:0] pe[0:ROWS-1][0:COLS-1];
    (* use_dsp="no" *) logic signed [31:0] psum[0:COLS-1];
    (* use_dsp="no" *) logic signed [63:0] y[0:COLS-1];
    wire [15:0] load_nl=n-lnt<COLS?n-lnt:16'(COLS);
    wire [15:0] load_kl=k-lg*GROUP_SIZE<GROUP_SIZE?k-lg*GROUP_SIZE:16'(GROUP_SIZE);
    wire [15:0] load_wspan=(load_kl+1)/2;
    (* use_dsp="no" *) logic [15:0] section_bytes;
    logic [3:0] beat_bytes;
    logic [7:0] expected_keep;
    always_comb begin
        case(load_state)
            LOAD_A: section_bytes=k;
            LOAD_SX: section_bytes=ng*2;
            LOAD_W: section_bytes=load_nl*load_wspan;
            LOAD_SW: section_bytes=load_nl*2;
            default: section_bytes=0;
        endcase
        beat_bytes=section_bytes-load_pos<8?4'(section_bytes-load_pos):4'd8;
        expected_keep=8'((9'd1<<beat_bytes)-1);
    end
    assign busy=state!=IDLE;
    assign start_ready=!rst && !busy;
    assign in_ready=!rst && busy && !load_pause && load_state!=LOAD_DONE &&
        ((load_state==LOAD_A || load_state==LOAD_SX) || !ready_bank[writer]);
    wire accept=in_valid && in_ready;
    assign out_valid=!rst && state==OUTPUTS;
    assign out_n=active_nt+output_col;
    assign out_last=out_n+1==n;
    function automatic signed [31:0] round_output(input logic signed [63:0] value);
        logic [63:0] magnitude,rounded;
        begin
            magnitude=value[63]?$unsigned(-value):$unsigned(value);
            rounded=(magnitude+64'd128)>>8;
            if(!value[63]) round_output=rounded>64'd2147483647 ? 32'sh7fffffff : $signed(rounded[31:0]);
            else round_output=rounded>64'd2147483648 ? 32'sh80000000 : -$signed(rounded[31:0]);
        end
    endfunction
    assign out_data=round_output(y[output_col]);
    for(genvar b=0;b<4;b++) begin: sx_bank
        localparam integer DEPTH=(GROUPS+3)/4;
        (* ram_style="distributed" *) logic [15:0] data[0:DEPTH-1];
        always_ff @(posedge clk) if(accept && in_keep==expected_keep &&
            load_state==LOAD_SX && in_keep[b*2]) data[load_pos/8]<=in_data[b*16+:16];
        assign sx_value[b]=data[active_g/4];
    end
    // K-interleaved activation banks provide eight independent bytes per step.
    for(genvar r=0;r<ROWS;r++) begin: activation_bank
        (* ram_style="block" *) logic signed [7:0] data[0:ADEPTH-1];
        logic signed [7:0] q;
        wire read_a=state==PRIME || (state==RUN && !array_pause && run_k+ROWS<active_kl);
        wire [15:0] read_k=(state==PRIME)?run_k:run_k+16'(ROWS);
        always_ff @(posedge clk) begin
            if(accept && load_state==LOAD_A && in_keep[r]) data[load_pos/ROWS]<=in_data[r*8+:8];
            if(read_a) q<=data[(active_g*GROUP_SIZE+read_k)/ROWS];
        end
        assign a_q[r]=q;
    end
    // Explicit 8x8 physical multipliers. Each PE owns a K slice and output column.
    for(genvar r=0;r<ROWS;r++) begin: pe_row
        for(genvar c=0;c<COLS;c++) begin: pe_col
            wire signed [3:0] nibble=weights[reader][c][(run_k+r)/2][((run_k+r)%2)*4+:4];
            wire signed [7:0] w={{4{nibble[3]}},nibble};
            (* use_dsp="yes" *) wire signed [15:0] product=a_q[r]*w;
            always_ff @(posedge clk) begin
                if(rst || state==CLEAR) pe[r][c]<=0;
                else if(state==RUN && !array_pause && run_k+r<active_kl && c<active_nl)
                    pe[r][c]<=pe[r][c]+{{16{product[15]}},product};
            end
        end
    end
    wire signed [39:0] reduced[0:COLS-1];
    for(genvar c=0;c<COLS;c++) begin: reduction_column
        (* use_dsp="no" *) wire signed [39:0] tree[1:2*ROWS-1];
        for(genvar r=0;r<ROWS;r++) assign tree[ROWS+r]={{8{pe[r][c][31]}},pe[r][c]};
        for(genvar q=1;q<ROWS;q++) assign tree[q]=tree[2*q]+tree[2*q+1];
        assign reduced[c]=tree[1];
    end
    // Fixed destination elements avoid variable-divisor address logic on the
    // ingress path. The byte offset selects one of the eight incoming bytes.
    for(genvar c=0;c<COLS;c++) begin: weight_column
        for(genvar b=0;b<2;b++) begin: scale_buffer
            always_ff @(posedge clk) if(accept && in_keep==expected_keep &&
                load_state==LOAD_SW && writer==b && c*2>=load_pos && c*2<load_pos+beat_bytes)
                scales[b][c]<=in_data[(c%4)*16+:16];
        end
        for(genvar q=0;q<WSPAN;q++) begin: weight_byte
            wire [15:0] offset=16'(c)*load_wspan+16'(q);
            for(genvar b=0;b<2;b++) begin: buffer
                always_ff @(posedge clk) if(accept && in_keep==expected_keep &&
                    load_state==LOAD_W && writer==b && q<load_wspan &&
                    offset>=load_pos && offset<load_pos+beat_bytes)
                    weights[b][c][q]<=in_data[offset[2:0]*8+:8];
            end
        end
    end
    logic [15:0] issue_col;
    logic issue_done,v0,v1;
    logic [POST_LANES-1:0] mask0,mask1;
    logic [15:0] col0[0:POST_LANES-1],col1[0:POST_LANES-1];
    logic [31:0] factors[0:POST_LANES-1];
    logic signed [31:0] partials[0:POST_LANES-1];
    logic signed [63:0] scaled[0:POST_LANES-1];
    wire signed [64:0] products[0:POST_LANES-1];
    for(genvar lane=0;lane<POST_LANES;lane++) begin: post_lane
        (* use_dsp="yes" *) wire signed [64:0] product=$signed(partials[lane])*$signed({1'b0,factors[lane]});
        assign products[lane]=product;
    end
    wire post_step=state==POST && !post_pause;
    wire finish_post=post_step && issue_done && !v0 && v1;
    (* use_dsp="no" *) wire [31:0] useful_step=(active_kl-run_k<ROWS?active_kl-run_k:ROWS)*active_nl;
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;load_state<=LOAD_DONE;done<=0;error<=0;n<=0;k<=0;ng<=0;
            lnt<=0;lg<=0;load_pos<=0;writer<=0;reader<=0;ready_bank<=0;
            active_nt<=0;active_g<=0;active_nl<=0;active_kl<=0;run_k<=0;output_col<=0;
            issue_col<=0;issue_done<=0;v0<=0;v1<=0;mask0<=0;mask1<=0;
            total_cycles<=0;input_beats<=0;weight_bytes<=0;activation_bytes<=0;sx_bytes<=0;sw_bytes<=0;
            valid_macs<=0;compute_cycles<=0;input_wait_cycles<=0;output_wait_cycles<=0;
            for(integer c=0;c<COLS;c++) begin y[c]<=0;psum[c]<=0;end
            for(integer lane=0;lane<POST_LANES;lane++) begin
                col0[lane]<=0;col1[lane]<=0;factors[lane]<=0;partials[lane]<=0;scaled[lane]<=0;
            end
        end else begin
            done<=0;
            if(start && start_ready) begin
                error<=0;
                if(cfg_n==0 || cfg_n>MAX_N || cfg_k==0 || cfg_k>MAX_K) begin error<=1;done<=1;end
                else begin
                    n<=cfg_n;k<=cfg_k;ng<=(cfg_k+GROUP_SIZE-1)/GROUP_SIZE;
                    state<=WAIT_BANK;load_state<=LOAD_A;lnt<=0;lg<=0;load_pos<=0;
                    writer<=0;reader<=0;ready_bank<=0;v0<=0;v1<=0;issue_done<=0;
                    total_cycles<=0;input_beats<=0;weight_bytes<=0;activation_bytes<=0;sx_bytes<=0;sw_bytes<=0;
                    valid_macs<=0;compute_cycles<=0;input_wait_cycles<=0;output_wait_cycles<=0;
                end
            end
            if(busy) begin
                total_cycles<=total_cycles+1;
                if(in_ready && !in_valid) input_wait_cycles<=input_wait_cycles+1;
                if(out_valid && !out_ready) output_wait_cycles<=output_wait_cycles+1;
                if(accept) begin
                    if(in_keep!=expected_keep) begin state<=IDLE;load_state<=LOAD_DONE;done<=1;error<=1;end
                    else begin
                        input_beats<=input_beats+1;
                        case(load_state)
                            LOAD_A: activation_bytes<=activation_bytes+beat_bytes;
                            LOAD_SX: begin
                                sx_bytes<=sx_bytes+beat_bytes;
                            end
                            LOAD_W: begin
                                weight_bytes<=weight_bytes+beat_bytes;
                                if(load_pos==0) begin bank_nt[writer]<=lnt;bank_g[writer]<=lg;end
                            end
                            LOAD_SW: begin
                                sw_bytes<=sw_bytes+beat_bytes;
                            end
                            default: ;
                        endcase
                        if(load_pos+beat_bytes<section_bytes) load_pos<=load_pos+beat_bytes;
                        else begin
                            load_pos<=0;
                            case(load_state)
                                LOAD_A: load_state<=LOAD_SX;
                                LOAD_SX: load_state<=LOAD_W;
                                LOAD_W: load_state<=LOAD_SW;
                                LOAD_SW: begin
                                    ready_bank[writer]<=1;writer<=~writer;
                                    if(lg+1<ng) begin lg<=lg+1;load_state<=LOAD_W;end
                                    else if(lnt+COLS<n) begin lg<=0;lnt<=lnt+COLS;load_state<=LOAD_W;end
                                    else load_state<=LOAD_DONE;
                                end
                                default: ;
                            endcase
                        end
                    end
                end
                case(state)
                    WAIT_BANK: if(ready_bank[reader]) begin
                        active_nt<=bank_nt[reader];active_g<=bank_g[reader];
                        active_nl<=n-bank_nt[reader]<COLS?n-bank_nt[reader]:16'(COLS);
                        active_kl<=k-bank_g[reader]*GROUP_SIZE<GROUP_SIZE?k-bank_g[reader]*GROUP_SIZE:16'(GROUP_SIZE);
                        state<=CLEAR;
                    end
                    CLEAR: begin
                        run_k<=0;
                        if(active_g==0) for(integer c=0;c<COLS;c++) y[c]<=0;
                        state<=PRIME;
                    end
                    PRIME: state<=RUN;
                    RUN: if(!array_pause) begin
                        compute_cycles<=compute_cycles+1;
                        valid_macs<=valid_macs+useful_step;
                        if(run_k+ROWS<active_kl) run_k<=run_k+16'(ROWS);
                        else state<=REDUCE;
                    end
                    REDUCE: begin
                        for(integer c=0;c<COLS;c++) psum[c]<=reduced[c][31:0];
                        issue_col<=0;issue_done<=0;v0<=0;v1<=0;state<=POST;
                    end
                    POST: if(!post_pause) begin
                        v0<=!issue_done;v1<=v0;
                        if(!issue_done) begin
                            for(integer lane=0;lane<POST_LANES;lane++) begin
                                mask0[lane]<=issue_col+lane<active_nl;
                                col0[lane]<=issue_col+16'(lane);
                                if(issue_col+lane<active_nl) begin
                                    factors[lane]<=32'(sx_value[active_g%4])*32'(scales[reader][issue_col+lane]);
                                    partials[lane]<=psum[issue_col+lane];
                                end
                            end
                            if(issue_col+POST_LANES>=active_nl) issue_done<=1;
                            else issue_col<=issue_col+16'(POST_LANES);
                        end
                        if(v0) for(integer lane=0;lane<POST_LANES;lane++) begin
                            scaled[lane]<=products[lane][63:0];col1[lane]<=col0[lane];mask1[lane]<=mask0[lane];
                        end
                        if(v1) for(integer lane=0;lane<POST_LANES;lane++) if(mask1[lane])
                            y[col1[lane]]<=y[col1[lane]]+scaled[lane];
                        if(finish_post) begin
                            ready_bank[reader]<=0;reader<=~reader;
                            if(active_g+1==ng) begin output_col<=0;state<=OUTPUTS;end
                            else state<=WAIT_BANK;
                        end
                    end
                    OUTPUTS: if(out_ready) begin
                        if(output_col+1==active_nl) begin
                            if(active_nt+active_nl==n) begin state<=IDLE;done<=1;end
                            else state<=WAIT_BANK;
                        end else output_col<=output_col+1;
                    end
                    default: ;
                endcase
                // A malformed beat cancels the task regardless of consumer state.
                if(accept && in_keep!=expected_keep) begin
                    state<=IDLE;load_state<=LOAD_DONE;done<=1;error<=1;
                end
            end
        end
    end
    initial begin
        if(ROWS!=8 || COLS!=8 || GROUP_SIZE%ROWS!=0 || POST_LANES<1 || POST_LANES>COLS)
            $fatal(1,"unsupported stream-core parameters");
    end
endmodule
