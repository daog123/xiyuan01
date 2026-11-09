// Streaming grouped W4A8 linear layer. Reuses validated INT8 MAC array.
module w4a8_wave #(
    parameter integer ROWS=4,COLS=4,TILE_K=8,GROUP_SIZE=32,
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096,
    parameter bit DOUBLE_BUFFER=1,
    parameter integer BUS_BYTES=8,
    parameter bit SCALE_ONCE=1,PACK_COLS=1,
    parameter bit POST_OVERLAP=1,POST_PIPELINE=1,
    parameter bit A_REUSE=1,SYSTOLIC=1,GROUP_STREAM=1
)(
    input logic clk,rst,load_pause,post_pause,array_pause,
    input logic start,
    output logic start_ready,busy,done,error,
    input logic [15:0] cfg_m,cfg_n,cfg_k,
    output logic req_valid,
    input logic req_ready,
    output logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group,
    input logic in_valid,
    output logic in_ready,
    input logic [BUS_BYTES*8-1:0] in_data,
    input logic [BUS_BYTES-1:0] in_keep,
    output logic req_scale,req_activation,
    output logic out_valid,
    input logic out_ready,
    output logic [15:0] out_m,out_n,
    output logic out_last,
    output logic signed [31:0] out_data,
    output logic [31:0] total_cycles,weight_bytes,activation_bytes,scale_bytes,
    output logic [31:0] valid_macs,compute_cycles,input_wait_cycles,output_wait_cycles,overlap_cycles,
    output logic [31:0] input_beats,padding_bytes,
    output logic [31:0] psum_wait_cycles,post_drain_cycles,post_active_cycles,
    output logic [31:0] post_issue_cycles,post_retire_cycles,compute_post_overlap_cycles,psum_groups,
    output logic [31:0] array_cycles,array_drain_cycles,array_pause_cycles,array_mac_cycles,
    output logic [31:0] tile_handoffs,wave_hold_cycles,wave_input_wait_cycles
);
    localparam integer BANKS=DOUBLE_BUFFER?2:1, RC=ROWS*COLS;
    localparam integer KW=(TILE_K<=1)?1:$clog2(TILE_K);
    localparam integer WDEPTH=(TILE_K+2)/2;
    localparam integer WW=(WDEPTH<=1)?1:$clog2(WDEPTH);
    localparam integer AD=(TILE_K+BUS_BYTES-1)/BUS_BYTES;
    localparam integer W_LANES=(PACK_COLS && BUS_BYTES==8)?2:1;
    localparam integer W_BYTES=BUS_BYTES/W_LANES;
    localparam integer WD=(WDEPTH+W_BYTES-1)/W_BYTES;
    localparam integer CACHE_TILES=(GROUP_SIZE+TILE_K-1)/TILE_K;
    localparam integer CACHE_GROUPS=(MAX_K+GROUP_SIZE-1)/GROUP_SIZE;
    localparam integer CACHE_DEPTH=CACHE_GROUPS*CACHE_TILES*AD;
    localparam integer CAW=(CACHE_DEPTH<=1)?1:$clog2(CACHE_DEPTH);
    wire [BUS_BYTES*8-1:0] cache_q[0:ROWS-1];
    wire signed [7:0] cached_a[0:ROWS-1];
    logic load_activation;
    localparam integer AW=(AD<=1)?1:$clog2(AD), WAW=(WD<=1)?1:$clog2(WD);
    localparam integer SELW=(BUS_BYTES<=1)?1:$clog2(BUS_BYTES);
    localparam integer PW=(RC<=1)?1:$clog2(RC);
    localparam integer WAVE_DELAY=ROWS+COLS-2;
    logic [15:0] drain_left;
    logic group_open;
    typedef enum logic [3:0] {IDLE,INIT_Y,WAIT_TILE,CLEAR_PE,PRIME,RUN,DRAIN,WAIT_PSUM,SAVE_G,WAIT_POST,OUT_REQ,OUT_LATCH,OUT_SEND,FINISH} state_t;
    typedef enum logic [1:0] {FREE,LOADING,READY,COMPUTING} bank_state_t;
    typedef enum logic [1:0] {WEIGHTS,ACTIVATIONS,SX,SW} phase_t;
    state_t state;
    wire array_step=!rst && !array_pause && (state==RUN || (SYSTOLIC && state==DRAIN));
    wire [RC-1:0] mac_fire;
    logic [7:0] mac_count;
    always_comb begin
        mac_count=0;
        for(integer p=0;p<RC;p++) mac_count=mac_count+mac_fire[p];
    end

    bank_state_t bank_state[0:BANKS-1];
    phase_t phase;
    logic [15:0] m,n,k,pm,pn,pk,mt,nt,ck;
    logic producer_bank,consumer_bank,load_bank,loading,producer_done,load_scale;
    logic [15:0] bank_m[0:BANKS-1],bank_n[0:BANKS-1],bank_k[0:BANKS-1];
    logic [15:0] bank_ml[0:BANKS-1],bank_nl[0:BANKS-1],bank_kl[0:BANKS-1],bank_wbytes[0:BANKS-1];
    logic [15:0] sx[0:BANKS-1][0:ROWS-1],sw[0:BANKS-1][0:COLS-1];
    logic [15:0] load_lane,load_pos,clen,run_k,slot,cm_len,cn_len;
    logic accept_input,read_tile,read_high;
    logic [KW-1:0] read_k;
    logic [WW-1:0] read_wp;
    wire [BUS_BYTES*8-1:0] aq_word[0:BANKS-1][0:ROWS-1];
    wire signed [7:0] aq[0:BANKS-1][0:ROWS-1];
    wire [W_BYTES*8-1:0] wq_word[0:BANKS-1][0:COLS-1];
    wire [COLS-1:0] w_write;
    wire [7:0] wq[0:BANKS-1][0:COLS-1];
    logic [SELW-1:0] a_sel;
    localparam integer WSEL=(W_BYTES<=1)?1:$clog2(W_BYTES);
    logic [WSEL-1:0] w_sel;
    wire [CAW-1:0] cache_wr_addr=CAW'((bank_k[load_bank]/GROUP_SIZE*CACHE_TILES+
        (bank_k[load_bank]%GROUP_SIZE)/TILE_K)*AD+load_pos/BUS_BYTES);
    wire [CAW-1:0] cache_rd_addr=CAW'((ck/GROUP_SIZE*CACHE_TILES+
        (ck%GROUP_SIZE)/TILE_K)*AD+read_k/BUS_BYTES);
    logic [15:0] beat_count;
    always_comb begin
        beat_count=0;
        for(integer j=0;j<BUS_BYTES;j=j+1) beat_count=beat_count+in_keep[j];
    end
    wire signed [7:0] unpacked[0:BANKS-1][0:COLS-1];
    wire signed [7:0] av[0:ROWS-1],bv[0:COLS-1];
    wire signed [31:0] acc[0:RC-1];
    logic slot_valid;
    typedef enum logic [1:0] {P_FREE,P_WRITING,P_READY,P_SCALING} psum_state_t;
    typedef enum logic {P_IDLE,P_STREAM} post_state_t;
    psum_state_t psum_state[0:1];
    post_state_t pstate;
    logic psum_prod,psum_cons;
    logic [15:0] psum_m[0:1],psum_n[0:1],psum_group[0:1];
    logic [15:0] psum_ml[0:1],psum_nl[0:1];
    logic [15:0] psum_sx[0:1][0:ROWS-1],psum_sw[0:1][0:COLS-1];
    logic [15:0] issue_slot,tag0,tag1,groups_scaled,wait_group;
    logic wait_last,issue_done,v0,v1;
    logic [1:0] issue_gap;
    wire signed [31:0] psum_q[0:1];
    wire signed [63:0] y_q;
    logic [31:0] factor;
    (* use_dsp="yes" *) wire signed [64:0] full_scaled=$signed(psum_q[psum_cons])*$signed({1'b0,factor});
    logic signed [63:0] scaled,y_base;
    wire p_issue=!rst && busy && !post_pause && pstate==P_STREAM && !issue_done && issue_gap==0;
    wire p_retire=!rst && busy && !post_pause && v1;
    wire psum_write=!rst && state==SAVE_G;
    wire signed [63:0] y_write=(state==INIT_Y)?64'sd0:(y_base+scaled);
    wire post_slot_valid=issue_slot/COLS<psum_ml[psum_cons] && issue_slot%COLS<psum_nl[psum_cons];

    assign busy=state!=IDLE;
    assign start_ready=!rst && !busy;
    assign req_m=pm;assign req_n=pn;assign req_k=pk;
    assign req_ml=(m-pm<ROWS)?m-pm:ROWS;
    assign req_nl=(n-pn<COLS)?n-pn:COLS;
    always_comb begin
        req_kl=TILE_K;
        if(k-pk<req_kl) req_kl=k-pk;
        if(GROUP_SIZE-pk%GROUP_SIZE<req_kl) req_kl=GROUP_SIZE-pk%GROUP_SIZE;
    end
    assign req_group=pk/GROUP_SIZE;
    assign req_scale=!SCALE_ONCE || pk+req_kl==k || (pk+req_kl)%GROUP_SIZE==0;
    assign req_activation=!A_REUSE || pn==0;
    assign req_valid=(!A_REUSE || pm==mt) && busy && !rst && !loading && !producer_done && bank_state[producer_bank]==FREE;
    assign in_ready=busy && !rst && loading && !load_pause;
    assign accept_input=in_ready && in_valid;
    assign cm_len=(m-mt<ROWS)?m-mt:ROWS;
    assign cn_len=(n-nt<COLS)?n-nt:COLS;
    assign slot_valid=slot/COLS<cm_len && slot%COLS<cn_len;
    assign read_tile=!rst && (state==PRIME || (state==RUN && !array_pause && run_k+1<clen));
    assign read_k=(state==PRIME)?0:run_k+1;
    assign read_wp=({15'd0,ck[0]}+read_k)>>1;
    assign out_valid=!rst && state==OUT_SEND;
    assign out_m=mt+slot/COLS;assign out_n=nt+slot%COLS;
    assign out_last=out_m==m-1 && out_n==n-1;

    for(genvar c=0;c<COLS;c=c+1)
        assign w_write[c]=accept_input && phase==WEIGHTS &&
            c>=load_lane && c<load_lane+W_LANES && c<bank_nl[load_bank];
    if(A_REUSE) begin: activation_cache
        for(genvar r=0;r<ROWS;r=r+1) begin: row_bank
            sync_sdp_ram #(.WIDTH(BUS_BYTES*8),.DEPTH(CACHE_DEPTH),.STYLE("block")) ram(
                .clk(clk),.wr_en(accept_input && phase==ACTIVATIONS && load_lane==r),
                .wr_addr(cache_wr_addr),.wr_data(in_data),
                .rd_en(read_tile),.rd_addr(cache_rd_addr),.rd_data(cache_q[r]));
            assign cached_a[r]=cache_q[r][a_sel*8 +:8];
        end
    end else begin: no_activation_cache
        for(genvar r=0;r<ROWS;r=r+1) assign cached_a[r]=8'sd0;
    end
    for(genvar b=0;b<BANKS;b=b+1) begin: buffers
        for(genvar r=0;r<ROWS;r=r+1) begin: a_bank
          if(!A_REUSE) begin: local_tile
            sync_sdp_ram #(.WIDTH(BUS_BYTES*8),.DEPTH(AD),.STYLE("distributed")) ram(
                .clk(clk),.wr_en(accept_input && load_bank==b && phase==ACTIVATIONS && load_lane==r),
                .wr_addr(AW'(load_pos/BUS_BYTES)),.wr_data(in_data),
                .rd_en(read_tile && consumer_bank==b),.rd_addr(AW'(read_k/BUS_BYTES)),.rd_data(aq_word[b][r]));
            assign aq[b][r]=aq_word[b][r][a_sel*8 +:8];
          end else begin: bypass
            assign aq_word[b][r]=0;assign aq[b][r]=0;
          end
        end
        for(genvar c=0;c<COLS;c=c+1) begin: w_bank
            sync_sdp_ram #(.WIDTH(W_BYTES*8),.DEPTH(WD),.STYLE("distributed")) ram(
                .clk(clk),.wr_en(load_bank==b && w_write[c]),
                .wr_addr(WAW'(load_pos/W_BYTES)),.wr_data(in_data[(c%W_LANES)*W_BYTES*8 +:W_BYTES*8]),
                .rd_en(read_tile && consumer_bank==b),.rd_addr(WAW'(read_wp/W_BYTES)),.rd_data(wq_word[b][c]));
            assign wq[b][c]=wq_word[b][c][w_sel*8 +:8];
            w4_unpack unpack(.packed_byte(wq[b][c]),.high(read_high),.value(unpacked[b][c]));
        end
    end
    for(genvar r=0;r<ROWS;r=r+1) assign av[r]=(r<cm_len)?(A_REUSE?cached_a[r]:aq[consumer_bank][r]):8'sd0;
    for(genvar c=0;c<COLS;c=c+1) assign bv[c]=(c<cn_len)?unpacked[consumer_bank][c]:8'sd0;
    if(SYSTOLIC) begin: systolic_core
        systolic_array #(.ROWS(ROWS),.COLS(COLS)) array_core(
            .clk(clk),.rst(rst),.clear(state==CLEAR_PE),.advance(array_step),
            .inject_valid(state==RUN),.valid_rows(cm_len),.valid_cols(cn_len),
            .a(av),.b(bv),.acc(acc),.pe_fire(mac_fire));
    end else begin: broadcast_core
        mac_array #(.ROWS(ROWS),.COLS(COLS)) array_core(.clk(clk),.rst(rst),
            .clear(state==CLEAR_PE),.en(array_step),.a(av),.b(bv),.acc(acc));
        for(genvar r=0;r<ROWS;r++) for(genvar c=0;c<COLS;c++)
            assign mac_fire[r*COLS+c]=array_step && r<cm_len && c<cn_len;
    end
    for(genvar b=0;b<2;b=b+1) begin: psum_banks
        sync_sdp_ram #(.WIDTH(32),.DEPTH(RC)) ram(
            .clk(clk),.wr_en(psum_write && psum_prod==b),.wr_addr(slot[PW-1:0]),.wr_data(acc[slot]),
            .rd_en(p_issue && psum_cons==b),.rd_addr(issue_slot[PW-1:0]),.rd_data(psum_q[b]));
    end
    sync_sdp_ram #(.WIDTH(64),.DEPTH(RC)) output_accumulator(
        .clk(clk),.wr_en(!rst && (state==INIT_Y || p_retire)),
        .wr_addr((state==INIT_Y)?slot[PW-1:0]:tag1[PW-1:0]),.wr_data(y_write),
        .rd_en(!rst && (p_issue || state==OUT_REQ)),
        .rd_addr(p_issue?issue_slot[PW-1:0]:slot[PW-1:0]),.rd_data(y_q));

    function automatic signed [31:0] round_output(input logic signed [63:0] value);
        logic [63:0] magnitude,rounded;
        begin
            magnitude=value[63]?$unsigned(-value):$unsigned(value);
            rounded=(magnitude+64'd128)>>8;
            if(!value[63]) round_output=(rounded>64'd2147483647)?32'sh7fffffff:$signed(rounded[31:0]);
            else round_output=(rounded>64'd2147483648)?32'sh80000000:-$signed(rounded[31:0]);
        end
    endfunction
    task automatic next_output;
        begin
            if(slot==RC-1) begin
                slot<=0;ck<=0;
                if(nt+COLS>=n) begin
                    nt<=0;
                    if(mt+ROWS>=m) state<=FINISH;
                    else begin mt<=mt+ROWS;state<=INIT_Y;end
                end else begin nt<=nt+COLS;state<=INIT_Y;end
            end else begin slot<=slot+1;state<=OUT_REQ;end
        end
    endtask

    // Group-stream mode releases a tile after injection; all group tokens drain before snapshot.
    task automatic finish_compute_tile;
        begin
            if(ck+clen==k || (ck+clen)%GROUP_SIZE==0) begin group_open<=0;slot<=0;state<=WAIT_PSUM;end
            else begin
                if(SYSTOLIC && GROUP_STREAM) tile_handoffs<=tile_handoffs+1;
                bank_state[consumer_bank]<=FREE;consumer_bank<=DOUBLE_BUFFER?~consumer_bank:1'b0;
                ck<=ck+clen;state<=WAIT_TILE;
            end
        end
    endtask
    task automatic finish_packet;
        begin
            loading<=0;bank_state[load_bank]<=READY;
            producer_bank<=DOUBLE_BUFFER?~producer_bank:1'b0;
            if(pk+bank_kl[load_bank]<k) pk<=pk+bank_kl[load_bank];
            else begin
                pk<=0;
                if(pn+COLS<n) pn<=pn+COLS;
                else begin
                    pn<=0;
                    if(pm+ROWS<m) pm<=pm+ROWS;else producer_done<=1;
                end
            end
        end
    endtask
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;done<=0;error<=0;m<=0;n<=0;k<=0;
            pm<=0;pn<=0;pk<=0;mt<=0;nt<=0;ck<=0;
            producer_bank<=0;consumer_bank<=0;load_bank<=0;loading<=0;producer_done<=0;
            phase<=WEIGHTS;load_lane<=0;load_pos<=0;clen<=0;run_k<=0;slot<=0;
            read_high<=0;a_sel<=0;w_sel<=0;load_scale<=0;load_activation<=0;factor<=0;scaled<=0;out_data<=0;
            input_beats<=0;padding_bytes<=0;
            psum_prod<=0;psum_cons<=0;pstate<=P_IDLE;issue_slot<=0;issue_done<=0;issue_gap<=0;
            v0<=0;v1<=0;tag0<=0;tag1<=0;y_base<=0;groups_scaled<=0;wait_group<=0;wait_last<=0;
            psum_wait_cycles<=0;post_drain_cycles<=0;post_active_cycles<=0;
            post_issue_cycles<=0;post_retire_cycles<=0;compute_post_overlap_cycles<=0;psum_groups<=0;
            for(integer b=0;b<2;b=b+1) begin
                psum_state[b]<=P_FREE;psum_m[b]<=0;psum_n[b]<=0;psum_group[b]<=0;psum_ml[b]<=0;psum_nl[b]<=0;
                for(integer r=0;r<ROWS;r=r+1) psum_sx[b][r]<=0;
                for(integer c=0;c<COLS;c=c+1) psum_sw[b][c]<=0;
            end
            total_cycles<=0;weight_bytes<=0;activation_bytes<=0;scale_bytes<=0;
            group_open<=0;tile_handoffs<=0;wave_hold_cycles<=0;wave_input_wait_cycles<=0;
            array_cycles<=0;array_drain_cycles<=0;array_pause_cycles<=0;array_mac_cycles<=0;drain_left<=0;
            valid_macs<=0;compute_cycles<=0;input_wait_cycles<=0;output_wait_cycles<=0;overlap_cycles<=0;
            for(integer b=0;b<BANKS;b=b+1) begin
                bank_state[b]<=FREE;bank_m[b]<=0;bank_n[b]<=0;bank_k[b]<=0;
                bank_ml[b]<=0;bank_nl[b]<=0;bank_kl[b]<=0;bank_wbytes[b]<=0;
            end
        end else begin
            done<=0;error<=0;
            if(start && start_ready) begin
                if(cfg_m==0 || cfg_n==0 || cfg_k==0 || cfg_m>MAX_M || cfg_n>MAX_N || cfg_k>MAX_K) error<=1;
                else begin
                    m<=cfg_m;n<=cfg_n;k<=cfg_k;state<=INIT_Y;
                    input_beats<=0;padding_bytes<=0;
                    psum_prod<=0;psum_cons<=0;pstate<=P_IDLE;issue_slot<=0;issue_done<=0;issue_gap<=0;
                    v0<=0;v1<=0;groups_scaled<=0;wait_group<=0;wait_last<=0;
                    psum_wait_cycles<=0;post_drain_cycles<=0;post_active_cycles<=0;
                    post_issue_cycles<=0;post_retire_cycles<=0;compute_post_overlap_cycles<=0;psum_groups<=0;
                    for(integer b=0;b<2;b=b+1) psum_state[b]<=P_FREE;
                    pm<=0;pn<=0;pk<=0;mt<=0;nt<=0;ck<=0;slot<=0;
                    producer_bank<=0;consumer_bank<=0;loading<=0;producer_done<=0;
                    for(integer b=0;b<BANKS;b=b+1) bank_state[b]<=FREE;
                    total_cycles<=0;weight_bytes<=0;activation_bytes<=0;scale_bytes<=0;
                    group_open<=0;tile_handoffs<=0;wave_hold_cycles<=0;wave_input_wait_cycles<=0;
            array_cycles<=0;array_drain_cycles<=0;array_pause_cycles<=0;array_mac_cycles<=0;drain_left<=0;
            valid_macs<=0;compute_cycles<=0;input_wait_cycles<=0;output_wait_cycles<=0;overlap_cycles<=0;
                end
            end else if(busy) begin
                total_cycles<=total_cycles+1;
                if(state==WAIT_PSUM && psum_state[psum_prod]!=P_FREE) psum_wait_cycles<=psum_wait_cycles+1;
                if(state==WAIT_POST) post_drain_cycles<=post_drain_cycles+1;
                if(pstate!=P_IDLE) post_active_cycles<=post_active_cycles+1;
                if(p_issue) post_issue_cycles<=post_issue_cycles+1;
                if(p_retire) post_retire_cycles<=post_retire_cycles+1;
                if(state==RUN && array_step && pstate!=P_IDLE) compute_post_overlap_cycles<=compute_post_overlap_cycles+1;
                // Globally stalled two-stage scale pipeline. One issue/retire per enabled clock.
                if(!post_pause) begin
                    v0<=p_issue;v1<=v0;
                    if(p_issue) begin
                        factor<=post_slot_valid?(psum_sx[psum_cons][issue_slot/COLS]*psum_sw[psum_cons][issue_slot%COLS]):32'd0;
                        tag0<=issue_slot;
                        if(issue_slot==RC-1) issue_done<=1;else issue_slot<=issue_slot+1;
                        issue_gap<=POST_PIPELINE?0:2;
                    end else if(issue_gap!=0) issue_gap<=issue_gap-1;
                    if(v0) begin scaled<=full_scaled[63:0];y_base<=y_q;tag1<=tag0;end
                    if(pstate==P_IDLE && psum_state[psum_cons]==P_READY) begin
                        pstate<=P_STREAM;psum_state[psum_cons]<=P_SCALING;
                        issue_slot<=0;issue_done<=0;issue_gap<=0;
                    end
                    if(p_retire && tag1==RC-1) begin
                        pstate<=P_IDLE;psum_state[psum_cons]<=P_FREE;psum_cons<=~psum_cons;
                        groups_scaled<=groups_scaled+1;
                    end
                end
                if(SYSTOLIC && GROUP_STREAM && group_open && (state==WAIT_TILE || state==PRIME)) begin
                    wave_hold_cycles<=wave_hold_cycles+1;
                    if(state==WAIT_TILE && bank_state[consumer_bank]!=READY)
                        wave_input_wait_cycles<=wave_input_wait_cycles+1;
                end
                if(array_step) begin
                    array_cycles<=array_cycles+1;
                    valid_macs<=valid_macs+mac_count;
                    if(mac_count!=0) array_mac_cycles<=array_mac_cycles+1;
                    if(state==DRAIN) array_drain_cycles<=array_drain_cycles+1;
                end
                if(array_pause && (state==RUN || state==DRAIN)) array_pause_cycles<=array_pause_cycles+1;
                if(state==RUN && array_step) begin
                    compute_cycles<=compute_cycles+1;
                    if(accept_input) overlap_cycles<=overlap_cycles+1;
                end
                if(state==WAIT_TILE && bank_state[consumer_bank]!=READY) input_wait_cycles<=input_wait_cycles+1;
                if(state==OUT_SEND && !out_ready) output_wait_cycles<=output_wait_cycles+1;
                if(read_tile) begin
                    read_high<=(ck[0]+read_k)&1;a_sel<=read_k%BUS_BYTES;w_sel<=read_wp%W_BYTES;
                end
                // Producer: one request outstanding, column-pair word writes; each bank has one write port.
                if(req_valid && req_ready) begin
                    load_bank<=producer_bank;loading<=1;load_scale<=req_scale;load_activation<=req_activation;
                    bank_state[producer_bank]<=LOADING;
                    bank_m[producer_bank]<=pm;bank_n[producer_bank]<=pn;bank_k[producer_bank]<=pk;
                    bank_ml[producer_bank]<=req_ml;bank_nl[producer_bank]<=req_nl;
                    bank_kl[producer_bank]<=req_kl;bank_wbytes[producer_bank]<=(pk[0]+req_kl+1)>>1;
                    phase<=WEIGHTS;load_lane<=0;load_pos<=0;
                end
                if(accept_input) begin
                    input_beats<=input_beats+1;padding_bytes<=padding_bytes+BUS_BYTES-beat_count;
                    case(phase)
                        WEIGHTS: begin
                            weight_bytes<=weight_bytes+beat_count;
                            if(load_pos+W_BYTES<bank_wbytes[load_bank]) load_pos<=load_pos+W_BYTES;
                            else begin
                                load_pos<=0;
                                if(load_lane+W_LANES<bank_nl[load_bank]) load_lane<=load_lane+W_LANES;
                                else begin
                                    load_lane<=0;
                                    if(load_activation) phase<=ACTIVATIONS;
                                    else if(load_scale) phase<=SX;
                                    else finish_packet();
                                end
                            end
                        end
                        ACTIVATIONS: begin
                            activation_bytes<=activation_bytes+beat_count;
                            if(load_pos+BUS_BYTES<bank_kl[load_bank]) load_pos<=load_pos+BUS_BYTES;
                            else begin
                                load_pos<=0;
                                if(load_lane+1<bank_ml[load_bank]) load_lane<=load_lane+1;
                                else if(load_scale) begin load_lane<=0;phase<=SX;end
                                else finish_packet();
                            end
                        end
                        SX: begin
                            scale_bytes<=scale_bytes+beat_count;
                            for(integer j=0;j<BUS_BYTES;j=j+1)
                                if(in_keep[j] && load_pos+j<2*bank_ml[load_bank])
                                    sx[load_bank][(load_pos+j)/2][((load_pos+j)%2)*8 +:8]<=in_data[j*8 +:8];
                            if(load_pos+BUS_BYTES<2*bank_ml[load_bank]) load_pos<=load_pos+BUS_BYTES;
                            else begin load_pos<=0;phase<=SW;end
                        end
                        SW: begin
                            scale_bytes<=scale_bytes+beat_count;
                            for(integer j=0;j<BUS_BYTES;j=j+1)
                                if(in_keep[j] && load_pos+j<2*bank_nl[load_bank])
                                    sw[load_bank][(load_pos+j)/2][((load_pos+j)%2)*8 +:8]<=in_data[j*8 +:8];
                            if(load_pos+BUS_BYTES<2*bank_nl[load_bank]) load_pos<=load_pos+BUS_BYTES;
                            else finish_packet();
                        end
                    endcase
                end
                // Consumer: PE keeps one group's integer sum across K tiles.
                case(state)
                    INIT_Y: begin
                        if(slot==0) groups_scaled<=0;
                        if(slot==RC-1) begin slot<=0;state<=WAIT_TILE;end else slot<=slot+1;
                    end
                    WAIT_TILE: if(bank_state[consumer_bank]==READY && bank_m[consumer_bank]==mt &&
                                  bank_n[consumer_bank]==nt && bank_k[consumer_bank]==ck) begin
                        bank_state[consumer_bank]<=COMPUTING;clen<=bank_kl[consumer_bank];run_k<=0;
                        state<=(ck%GROUP_SIZE==0)?CLEAR_PE:PRIME;
                    end
                    CLEAR_PE: begin group_open<=0;state<=PRIME;end
                    PRIME: state<=RUN;
                    RUN: if(!array_pause) begin
                        group_open<=1;
                        if(run_k+1<clen) run_k<=run_k+1;
                        else if(SYSTOLIC && WAVE_DELAY!=0 &&
                            (!GROUP_STREAM || ck+clen==k || (ck+clen)%GROUP_SIZE==0)) begin
                            drain_left<=WAVE_DELAY;state<=DRAIN;
                        end else finish_compute_tile();
                    end
                    DRAIN: if(!array_pause) begin
                        if(drain_left==1) finish_compute_tile();
                        else drain_left<=drain_left-1;
                    end
                    WAIT_PSUM: if(psum_state[psum_prod]==P_FREE) begin
                        psum_state[psum_prod]<=P_WRITING;
                        psum_m[psum_prod]<=mt;psum_n[psum_prod]<=nt;psum_group[psum_prod]<=ck/GROUP_SIZE;
                        psum_ml[psum_prod]<=cm_len;psum_nl[psum_prod]<=cn_len;
                        for(integer r=0;r<ROWS;r=r+1)
                            psum_sx[psum_prod][r]<=(r<cm_len)?sx[consumer_bank][r]:16'd0;
                        for(integer c=0;c<COLS;c=c+1)
                            psum_sw[psum_prod][c]<=(c<cn_len)?sw[consumer_bank][c]:16'd0;
                        slot<=0;state<=SAVE_G;
                    end
                    SAVE_G: if(slot==RC-1) begin
                        psum_state[psum_prod]<=P_READY;psum_prod<=~psum_prod;psum_groups<=psum_groups+1;
                        bank_state[consumer_bank]<=FREE;consumer_bank<=DOUBLE_BUFFER?~consumer_bank:1'b0;
                        slot<=0;wait_group<=ck/GROUP_SIZE;wait_last<=ck+clen==k;
                        ck<=ck+clen;
                        state<=(!POST_OVERLAP || ck+clen==k)?WAIT_POST:WAIT_TILE;
                    end else slot<=slot+1;
                    WAIT_POST: if(groups_scaled>wait_group) state<=wait_last?OUT_REQ:WAIT_TILE;
                    OUT_REQ: if(slot_valid) state<=OUT_LATCH;else next_output();
                    OUT_LATCH: begin out_data<=round_output(y_q);state<=OUT_SEND;end
                    OUT_SEND: if(out_ready) next_output();
                    FINISH: begin state<=IDLE;done<=1;end
                    default: begin state<=IDLE;error<=1;end
                endcase
            end
        end
    end
endmodule
