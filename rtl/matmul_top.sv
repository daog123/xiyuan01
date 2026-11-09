// Scalar matrix loading and output-stationary tiled compute. Synchronous reset.
module matmul_top #(
    parameter integer ROWS=4, COLS=4, TILE_K=8,
    parameter integer MAX_M=16, MAX_N=16, MAX_K=32,
    parameter bit OPTIMIZED=1, DOUBLE_BUFFER=1,
    parameter integer B_LOAD_GAP=0
)(
    input logic clk, rst, pause,
    input logic wr_valid,
    output logic wr_ready,
    input logic wr_matrix,
    input logic [15:0] wr_row, wr_col,
    input logic signed [7:0] wr_data,
    input logic [15:0] cfg_m, cfg_n, cfg_k,
    input logic start,
    output logic start_ready,
    output logic busy, done, error, result_available,
    input logic rd_req,
    output logic rd_ready,
    input logic [15:0] rd_row, rd_col,
    output logic rd_valid,
    output wire signed [31:0] rd_data,
    output logic [31:0] cycle_count, active_cycles
);
    localparam integer A_DEPTH=MAX_M*MAX_K, B_DEPTH=MAX_K*MAX_N;
    localparam integer P_DEPTH=MAX_M*MAX_N;
    localparam integer AAW=(A_DEPTH<=1)?1:$clog2(A_DEPTH);
    localparam integer BAW=(B_DEPTH<=1)?1:$clog2(B_DEPTH);
    localparam integer PAW=(P_DEPTH<=1)?1:$clog2(P_DEPTH);
    localparam integer KW=(TILE_K<=1)?1:$clog2(TILE_K);
    localparam integer RW=(ROWS<=1)?1:$clog2(ROWS);
    localparam integer CW=(COLS<=1)?1:$clog2(COLS);
    typedef enum logic [3:0] {IDLE,CLEAR,A_REQ,A_WRITE,B_REQ,B_WRITE,
                            PRIME,RUN,SAVE,ADVANCE,WAIT_B} state_t;
    state_t state;
    logic [15:0] m,n,k,mt,nt,kt;
    logic [15:0] load_lane,load_k,run_k,save_lane,k_len;
    localparam bit USE_DB=OPTIMIZED && DOUBLE_BUFFER;
    logic step,a_in_range,b_in_range,save_in_range;
    logic db_ready,db_mem_rd_en;
    logic [BAW-1:0] db_mem_rd_addr;
    logic [15:0] db_read_lane,db_read_k_abs,b_read_k_abs;
    wire signed [7:0] db_vec [0:COLS-1];
    localparam integer A_CACHE_K=OPTIMIZED?MAX_K:TILE_K;
    localparam integer AKW=(A_CACHE_K<=1)?1:$clog2(A_CACHE_K);
    logic [15:0] a_load_limit,next_lane,next_k,a_read_lane,a_read_k,b_read_lane,b_read_k;
    logic a_load_last,b_load_last,a_read_valid,b_read_valid;
    logic [AKW-1:0] a_compute_k;
    logic a_rd_en,b_rd_en,p_wr_en,tile_rd_en,a_wr_en,b_wr_en;
    logic [AAW-1:0] a_rd_addr,a_wr_addr;
    logic [BAW-1:0] b_rd_addr,b_wr_addr;
    logic [PAW-1:0] p_wr_addr,p_rd_addr;
    logic signed [7:0] a_q,b_q,a_tile_data,b_tile_data;
    logic [KW-1:0] tile_rd_k;
    wire signed [7:0] a_vec [0:ROWS-1],b_vec [0:COLS-1];
    wire signed [31:0] acc [0:ROWS*COLS-1];
    logic signed [31:0] p_wr_data;

    assign busy = state!=IDLE;
    assign step = !pause && !rst;
    assign start_ready = !busy && step && !wr_valid && !rd_req;
    assign wr_ready = !busy && step && !start && !rd_req &&
                      ((!wr_matrix && wr_row<MAX_M && wr_col<MAX_K) ||
                       (wr_matrix && wr_row<MAX_K && wr_col<MAX_N));
    assign rd_ready = !busy && step && !start && !wr_valid &&
                      result_available && rd_row<m && rd_col<n;
    assign k_len = ((k-kt)<TILE_K)?(k-kt):TILE_K;
    assign a_in_range = (mt+load_lane<m) && (kt+load_k<k);
    assign b_in_range = (nt+load_lane<n) && (kt+load_k<k);
    assign save_in_range = (mt+save_lane/COLS<m) && (nt+save_lane%COLS<n);
    // One synchronous matrix read port: WRITE commits current q and issues
    // the next address. Cache A for the entire K of one M block.
    assign a_load_limit = OPTIMIZED?k:TILE_K;
    assign a_load_last = load_k==a_load_limit-1 && load_lane==ROWS-1;
    assign b_load_last = load_k==(OPTIMIZED?k_len:TILE_K)-1 && load_lane==COLS-1;
    always_comb begin
        next_lane=load_lane; next_k=load_k+1;
        if ((state==A_WRITE && load_k==a_load_limit-1) ||
            (state==B_WRITE && load_k==(OPTIMIZED?k_len:TILE_K)-1)) begin
            next_lane=load_lane+1; next_k=0;
        end
    end
    assign a_read_lane = (OPTIMIZED && state==A_WRITE)?next_lane:load_lane;
    assign a_read_k = (OPTIMIZED && state==A_WRITE)?next_k:load_k;
    assign b_read_lane = USE_DB?db_read_lane:((OPTIMIZED && state==B_WRITE)?next_lane:load_lane);
    assign b_read_k = (OPTIMIZED && state==B_WRITE)?next_k:load_k;
    assign a_read_valid = mt+a_read_lane<m && kt+a_read_k<k;
    assign b_read_k_abs = USE_DB?db_read_k_abs:kt+b_read_k;
    assign b_read_valid = nt+b_read_lane<n && b_read_k_abs<k;
    assign a_rd_en = step && a_read_valid &&
        (state==A_REQ || (OPTIMIZED && state==A_WRITE && !a_load_last));
    assign b_rd_en = USE_DB?db_mem_rd_en:(step && b_read_valid &&
        (state==B_REQ || (OPTIMIZED && state==B_WRITE && !b_load_last)));
    assign a_rd_addr = (mt+a_read_lane)*MAX_K+kt+a_read_k;
    assign b_rd_addr = USE_DB?db_mem_rd_addr:((kt+b_read_k)*MAX_N+nt+b_read_lane);
    assign a_wr_addr = wr_row*MAX_K+wr_col;
    assign b_wr_addr = wr_row*MAX_N+wr_col;
    assign a_wr_en = wr_valid && wr_ready && !wr_matrix;
    assign b_wr_en = wr_valid && wr_ready && wr_matrix;
    assign a_tile_data = a_in_range?a_q:8'sd0;
    assign b_tile_data = b_in_range?b_q:8'sd0;
    assign tile_rd_en = step && (state==PRIME || (state==RUN && run_k+1<k_len));
    assign tile_rd_k = (state==PRIME)?0:run_k+1;
    assign a_compute_k = OPTIMIZED?(kt+tile_rd_k):tile_rd_k;
    assign p_wr_en = step && state==SAVE && save_in_range;
    assign p_wr_addr = (mt+save_lane/COLS)*MAX_N+nt+save_lane%COLS;
    assign p_wr_data = acc[save_lane];
    assign p_rd_addr = rd_row*MAX_N+rd_col;

    sync_sdp_ram #(.WIDTH(8),.DEPTH(A_DEPTH)) activation_memory (
        .clk(clk),.wr_en(a_wr_en),.wr_addr(a_wr_addr),.wr_data(wr_data),
        .rd_en(a_rd_en),.rd_addr(a_rd_addr),.rd_data(a_q));
    sync_sdp_ram #(.WIDTH(8),.DEPTH(B_DEPTH)) weight_memory (
        .clk(clk),.wr_en(b_wr_en),.wr_addr(b_wr_addr),.wr_data(wr_data),
        .rd_en(b_rd_en),.rd_addr(b_rd_addr),.rd_data(b_q));
    tile_buffer #(.LANES(ROWS),.TILE_K(A_CACHE_K)) activation_tile (
        .clk(clk),.wr_en(step && state==A_WRITE),.wr_lane(load_lane[RW-1:0]),
        .wr_k(load_k[AKW-1:0]),.wr_data(a_tile_data),
        .rd_en(tile_rd_en),.rd_k(a_compute_k),.data(a_vec));
    generate if(USE_DB) begin: g_db
        b_pingpong #(.COLS(COLS),.TILE_K(TILE_K),.MAX_N(MAX_N),.MAX_K(MAX_K),
                     .LOAD_GAP(B_LOAD_GAP)) prefetch (
            .clk(clk),.rst(rst),.enable(step),.init(state==CLEAR),
            .task_n(n),.task_k(k),.tile_n(nt),.consume_kt(kt),
            .mem_rd_en(db_mem_rd_en),.mem_rd_addr(db_mem_rd_addr),.mem_q(b_q),
            .take(state==WAIT_B && db_ready),.release_tile(state==ADVANCE),
            .rd_en(tile_rd_en),.rd_k(tile_rd_k),.ready(db_ready),.data(db_vec),
            .read_lane(db_read_lane),.read_k_abs(db_read_k_abs));
        for(genvar c=0;c<COLS;c=c+1) begin: connect
            assign b_vec[c]=db_vec[c];
        end
    end else begin: g_single
        assign db_ready=0;assign db_mem_rd_en=0;assign db_mem_rd_addr=0;
        assign db_read_lane=0;assign db_read_k_abs=0;
        tile_buffer #(.LANES(COLS),.TILE_K(TILE_K)) weight_tile (
            .clk(clk),.wr_en(step && state==B_WRITE),.wr_lane(load_lane[CW-1:0]),
            .wr_k(load_k[KW-1:0]),.wr_data(b_tile_data),
            .rd_en(tile_rd_en),.rd_k(tile_rd_k),.data(b_vec));
    end endgenerate
    mac_array #(.ROWS(ROWS),.COLS(COLS)) array_core (
        .clk(clk),.rst(rst),.clear(step && state==CLEAR),
        .en(step && state==RUN),.a(a_vec),.b(b_vec),.acc(acc));
    // Optimized mode writes final K only; baseline checkpoints each K tile.
    // PE accumulators remain authoritative across K in both modes.
    sync_sdp_ram #(.WIDTH(32),.DEPTH(P_DEPTH)) partial_sum_memory (
        .clk(clk),.wr_en(p_wr_en),.wr_addr(p_wr_addr),.wr_data(p_wr_data),
        .rd_en(rd_req && rd_ready),.rd_addr(p_rd_addr),.rd_data(rd_data));

    always_ff @(posedge clk) begin
        if (rst) begin
            state<=IDLE; done<=0; error<=0; rd_valid<=0; result_available<=0;
            m<=0; n<=0; k<=0; mt<=0; nt<=0; kt<=0;
            load_lane<=0; load_k<=0; run_k<=0; save_lane<=0;
            cycle_count<=0; active_cycles<=0;
        end else begin
            done<=0; error<=0;
            rd_valid<=rd_req && rd_ready;
            if (wr_valid && wr_ready) result_available<=0;
            if (busy) begin
                cycle_count<=cycle_count+1;
                if (!pause) active_cycles<=active_cycles+1;
            end
            if (!pause) begin
                case (state)
                    IDLE: if (start && start_ready) begin
                        if (cfg_m==0 || cfg_n==0 || cfg_k==0 ||
                            cfg_m>MAX_M || cfg_n>MAX_N || cfg_k>MAX_K) error<=1;
                        else begin
                            m<=cfg_m; n<=cfg_n; k<=cfg_k;
                            mt<=0; nt<=0; kt<=0; state<=CLEAR;
                            result_available<=0; cycle_count<=0; active_cycles<=0;
                        end
                    end
                    CLEAR: begin
                        load_lane<=0; load_k<=0;
                        state<=(OPTIMIZED && nt!=0)?(USE_DB?WAIT_B:B_REQ):A_REQ;
                    end
                    A_REQ: state<=A_WRITE;
                    A_WRITE: begin
                        if (load_k==a_load_limit-1) begin
                            load_k<=0;
                            if (load_lane==ROWS-1) begin load_lane<=0; state<=USE_DB?WAIT_B:B_REQ; end
                            else begin load_lane<=load_lane+1; state<=OPTIMIZED?A_WRITE:A_REQ; end
                        end else begin load_k<=load_k+1; state<=OPTIMIZED?A_WRITE:A_REQ; end
                    end
                    B_REQ: state<=B_WRITE;
                    B_WRITE: begin
                        if (load_k==(OPTIMIZED?k_len:TILE_K)-1) begin
                            load_k<=0;
                            if (load_lane==COLS-1) begin load_lane<=0; state<=PRIME; end
                            else begin load_lane<=load_lane+1; state<=OPTIMIZED?B_WRITE:B_REQ; end
                        end else begin load_k<=load_k+1; state<=OPTIMIZED?B_WRITE:B_REQ; end
                    end
                    WAIT_B: if(db_ready) state<=PRIME;
                    PRIME: begin run_k<=0; state<=RUN; end
                    RUN: begin
                        if (run_k==k_len-1) begin
                            save_lane<=0;
                            state<=(OPTIMIZED && kt+TILE_K<k)?ADVANCE:SAVE;
                        end
                        else run_k<=run_k+1;
                    end
                    SAVE: begin
                        if (save_lane==ROWS*COLS-1) state<=ADVANCE;
                        else save_lane<=save_lane+1;
                    end
                    ADVANCE: begin
                        if (kt+TILE_K<k) begin
                            kt<=kt+TILE_K; load_lane<=0; load_k<=0; state<=USE_DB?WAIT_B:(OPTIMIZED?B_REQ:A_REQ);
                        end else begin
                            kt<=0;
                            if (nt+COLS<n) begin nt<=nt+COLS; state<=CLEAR; end
                            else if (mt+ROWS<m) begin mt<=mt+ROWS; nt<=0; state<=CLEAR; end
                            else begin state<=IDLE; done<=1; result_available<=1; end
                        end
                    end
                    default: begin state<=IDLE; error<=1; result_available<=0; end
                endcase
            end
        end
    end
endmodule
