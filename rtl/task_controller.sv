module task_controller #(
    parameter integer MAX_M=64,MAX_N=64,MAX_K=4096,GROUP_SIZE=32,TIMEOUT_CYCLES=1000000
)(
    input logic clk,rst,
    input logic task_valid, output logic task_ready,
    input task_desc_pkg::task_desc_t task_desc,
    output logic core_reset,core_start, output logic [15:0] core_cfg_m,core_cfg_n,core_cfg_k,
    input logic core_start_ready,core_busy,core_done,core_error,
    input logic core_req_valid, output logic core_req_ready,
    input logic [15:0] core_req_m,core_req_n,core_req_k,core_req_ml,core_req_nl,core_req_kl,core_req_group,
    input logic core_req_scale, output logic mem_req_valid, input logic mem_req_ready,
    output logic [31:0] mem_task_id,
    output logic [63:0] mem_a_addr,mem_w_addr,mem_sx_addr,mem_sw_addr,
    output logic [31:0] mem_a_stride,mem_w_stride,mem_sx_stride,mem_sw_stride,
    output logic [15:0] mem_req_m,mem_req_n,mem_req_k,mem_req_ml,mem_req_nl,mem_req_kl,mem_req_group,
    output logic mem_req_scale,
    input logic core_in_ready, output logic mem_in_ready,
    input logic core_out_valid, output logic core_out_ready,
    input logic [15:0] core_out_m,core_out_n, input logic core_out_last,
    input logic signed [31:0] core_out_data,
    output logic mem_wr_valid, input logic mem_wr_ready,
    output logic [31:0] mem_wr_task_id, output logic [63:0] mem_wr_addr,
    output logic [15:0] mem_wr_m,mem_wr_n, output logic signed [31:0] mem_wr_data,
    output logic mem_wr_last, input logic mem_wr_ack,
    output logic completion_valid, input logic completion_ready,
    output logic [31:0] completion_task_id, output logic [7:0] completion_status,
    output logic result_available, output logic [31:0] elapsed_cycles
);
    import task_desc_pkg::*;
    typedef enum logic [2:0] {IDLE,LAUNCH,RUN,WAIT_ACK,COMPLETE,ABORT_CORE} state_t;
    state_t state;
    task_desc_t active;
    logic write_pending,accepted_last;
    logic [31:0] watchdog,output_count,expected_outputs;
    logic [7:0] pending_status;
    wire output_accept=mem_wr_valid && mem_wr_ready;
    wire timeout_hit=(TIMEOUT_CYCLES>0) && watchdog>=TIMEOUT_CYCLES-1;
    function automatic logic [7:0] validate(input task_desc_t d);
        logic [64:0] a_end,w_end,sx_end,sw_end,y_end;
        logic [16:0] groups;
        begin
            groups=(d.k+GROUP_SIZE-1)/GROUP_SIZE;
            a_end={1'b0,d.a_addr}+({49'b0,d.m}-65'd1)*{33'b0,d.a_stride}+d.k;
            w_end={1'b0,d.w_addr}+({49'b0,d.n}-65'd1)*{33'b0,d.w_stride}+((d.k+1)>>1);
            sx_end={1'b0,d.sx_addr}+({49'b0,d.m}-65'd1)*{33'b0,d.sx_stride}+groups*2;
            sw_end={1'b0,d.sw_addr}+({48'b0,groups}-65'd1)*{33'b0,d.sw_stride}+d.n*2;
            y_end={1'b0,d.y_addr}+({49'b0,d.m}-65'd1)*{33'b0,d.y_stride}+d.n*4;
            if(d.m==0 || d.n==0 || d.k==0 || d.m>MAX_M || d.n>MAX_N || d.k>MAX_K) validate=STATUS_BAD_DIM;
            else if(d.activation_format!=FORMAT_INT8 || d.weight_format!=FORMAT_SINT4_PACKED ||
                    d.scale_format!=FORMAT_UQ4_12 || d.output_format!=FORMAT_Q16_16) validate=STATUS_BAD_FORMAT;
            else if(d.group_size!=GROUP_SIZE) validate=STATUS_BAD_GROUP;
            else if(d.flags!=0) validate=STATUS_BAD_FLAGS;
            else if(d.a_addr==0 || d.w_addr==0 || d.sx_addr==0 || d.sw_addr==0 || d.y_addr==0 ||
                    d.sx_addr[0] || d.sw_addr[0] || d.y_addr[1:0] ||
                    (a_end[64] && |a_end[63:0]) || (w_end[64] && |w_end[63:0]) ||
                    (sx_end[64] && |sx_end[63:0]) || (sw_end[64] && |sw_end[63:0]) ||
                    (y_end[64] && |y_end[63:0])) validate=STATUS_BAD_ADDRESS;
            else if(d.a_stride<d.k || d.w_stride<((d.k+1)>>1) ||
                    d.sx_stride<groups*2 ||
                    d.sw_stride<d.n*2 || d.y_stride<({16'b0,d.n,2'b00}))
                validate=STATUS_BAD_STRIDE;
            else validate=STATUS_OK;
        end
    endfunction
    assign task_ready=!rst && state==IDLE;
    assign core_reset=rst || state==ABORT_CORE;
    assign core_start=!rst && state==LAUNCH && core_start_ready;
    assign core_cfg_m=active.m; assign core_cfg_n=active.n; assign core_cfg_k=active.k;
    assign mem_task_id=active.task_id;
    assign mem_a_addr=active.a_addr; assign mem_w_addr=active.w_addr;
    assign mem_sx_addr=active.sx_addr; assign mem_sw_addr=active.sw_addr;
    assign mem_a_stride=active.a_stride; assign mem_w_stride=active.w_stride;
    assign mem_sx_stride=active.sx_stride; assign mem_sw_stride=active.sw_stride;
    assign mem_req_valid=!rst && state==RUN && core_req_valid;
    assign core_req_ready=state==RUN && mem_req_ready;
    assign mem_req_m=core_req_m; assign mem_req_n=core_req_n; assign mem_req_k=core_req_k;
    assign mem_req_ml=core_req_ml; assign mem_req_nl=core_req_nl;
    assign mem_req_kl=core_req_kl; assign mem_req_group=core_req_group;
    assign mem_req_scale=core_req_scale;
    assign mem_in_ready=!rst && state==RUN && core_in_ready && !timeout_hit;
    assign core_out_ready=!rst && state==RUN && !write_pending && mem_wr_ready;
    assign mem_wr_valid=!rst && state==RUN && !write_pending && core_out_valid;
    assign mem_wr_task_id=active.task_id;
    assign mem_wr_addr=active.y_addr+({48'b0,core_out_m}*{32'b0,active.y_stride})+
                       {48'b0,core_out_n,2'b00};
    assign mem_wr_m=core_out_m; assign mem_wr_n=core_out_n;
    assign mem_wr_data=core_out_data; assign mem_wr_last=core_out_last;
    assign completion_valid=!rst && state==COMPLETE;
    assign completion_task_id=active.task_id; assign completion_status=pending_status;
    assign result_available=completion_valid && pending_status==STATUS_OK;
    always_ff @(posedge clk) begin
        if(rst) begin
            state<=IDLE;active<='0;write_pending<=0;accepted_last<=0;
            watchdog<=0;elapsed_cycles<=0;output_count<=0;expected_outputs<=0;pending_status<=STATUS_OK;
        end else begin
            if(state!=IDLE && state!=COMPLETE) begin watchdog<=watchdog+1'b1;elapsed_cycles<=elapsed_cycles+1'b1;end
            if(task_valid && task_ready) begin
                active<=task_desc;watchdog<=0;elapsed_cycles<=0;output_count<=0;
                expected_outputs<=task_desc.m*task_desc.n;write_pending<=0;accepted_last<=0;
                pending_status<=validate(task_desc);
                state<=validate(task_desc)==STATUS_OK?LAUNCH:COMPLETE;
            end else case(state)
                LAUNCH: if(timeout_hit) begin pending_status<=STATUS_TIMEOUT;state<=ABORT_CORE;end
                        else if(core_start) begin watchdog<=0;state<=RUN;end
                RUN: begin
                    if(mem_wr_ack && !write_pending) begin pending_status<=STATUS_WRITE_PROTOCOL;state<=ABORT_CORE;end
                    if(output_accept) begin
                        output_count<=output_count+1'b1;accepted_last<=core_out_last;write_pending<=1;watchdog<=0;
                    end
                    if(write_pending && mem_wr_ack) begin write_pending<=0;watchdog<=0;end
                    if(timeout_hit) begin pending_status<=STATUS_TIMEOUT;state<=ABORT_CORE;end
                    else if(core_error) begin pending_status<=STATUS_CORE_ERROR;state<=ABORT_CORE;end
                    else if(core_done) begin
                        if(output_count+(output_accept?1:0)==expected_outputs &&
                           (accepted_last || (output_accept && core_out_last))) begin
                            if(write_pending || output_accept) state<=WAIT_ACK;
                            else state<=COMPLETE;
                        end else begin
                            pending_status<=STATUS_WRITE_PROTOCOL;
                            if(write_pending) state<=WAIT_ACK;
                            else state<=COMPLETE;
                        end
                    end
                end
                WAIT_ACK: begin
                    if(write_pending && mem_wr_ack) begin write_pending<=0;watchdog<=0;end
                    if(timeout_hit) begin pending_status<=STATUS_TIMEOUT;state<=ABORT_CORE;end
                    else if(!write_pending) state<=COMPLETE;
                end
                ABORT_CORE: begin write_pending<=0;if(!core_busy) state<=COMPLETE;end
                COMPLETE: if(completion_ready) begin state<=IDLE;pending_status<=STATUS_OK;end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
