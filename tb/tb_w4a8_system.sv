module tb_w4a8_system;
    import task_desc_pkg::*;
    logic clk=0,rst=1,task_valid=0,task_ready,load_pause=0;
    task_desc_t desc;
    logic req_valid,req_ready,in_valid,in_ready,req_scale;
    logic [31:0] mem_task_id;
    logic [63:0] a_addr,w_addr,sx_addr,sw_addr;
    logic [31:0] a_stride,w_stride,sx_stride,sw_stride;
    logic [15:0] req_m,req_n,req_k,req_ml,req_nl,req_kl,req_group;
    logic [63:0] in_data;
    logic [7:0] in_keep;
    logic wr_valid,wr_ready=1,wr_ack=0,wr_last;
    logic [31:0] wr_task_id;
    logic [63:0] wr_addr;
    logic [15:0] wr_m,wr_n;
    logic signed [31:0] wr_data;
    logic completion_valid,completion_ready=0,result_available;
    logic [31:0] completion_task_id,elapsed_cycles;
    logic [7:0] completion_status;
    integer write_count=0,ack_delay=0,scenario=0,cycle_total=0;
    logic req_gate=1;
    always #5 clk=~clk;

    w4a8_system_top #(.ROWS(2),.COLS(2),.TILE_K(4),.GROUP_SIZE(4),
        .MAX_M(8),.MAX_N(8),.MAX_K(32),.TIMEOUT_CYCLES(1800)) dut (
        .clk(clk),.rst(rst),.task_valid(task_valid),.task_ready(task_ready),.task_desc(desc),
        .load_pause(load_pause),.mem_req_valid(req_valid),.mem_req_ready(req_ready && req_gate),
        .mem_task_id(mem_task_id),.mem_a_addr(a_addr),.mem_w_addr(w_addr),.mem_sx_addr(sx_addr),.mem_sw_addr(sw_addr),
        .mem_a_stride(a_stride),.mem_w_stride(w_stride),.mem_sx_stride(sx_stride),.mem_sw_stride(sw_stride),
        .mem_req_m(req_m),.mem_req_n(req_n),.mem_req_k(req_k),
        .mem_req_ml(req_ml),.mem_req_nl(req_nl),.mem_req_kl(req_kl),.mem_req_group(req_group),.mem_req_scale(req_scale),
        .mem_in_valid(in_valid),.mem_in_ready(in_ready),.mem_in_data(in_data),.mem_in_keep(in_keep),
        .mem_wr_valid(wr_valid),.mem_wr_ready(wr_ready),.mem_wr_task_id(wr_task_id),.mem_wr_addr(wr_addr),
        .mem_wr_m(wr_m),.mem_wr_n(wr_n),.mem_wr_data(wr_data),.mem_wr_last(wr_last),.mem_wr_ack(wr_ack),
        .completion_valid(completion_valid),.completion_ready(completion_ready),
        .completion_task_id(completion_task_id),.completion_status(completion_status),
        .result_available(result_available),.elapsed_cycles(elapsed_cycles));

    w4a8_stream_memory #(.GROUP_SIZE(4),.MAX_DATA(64),.FIRST_DELAY(0),.BURST_GAP(0),.REQUEST_PERIOD(1)) memory (
        .clk(clk),.rst(rst),.task_start(1'b0),.mode(0),.m(3),.n(3),.k(5),.ng(2),
        .req_valid(req_valid && req_gate),.req_scale(req_scale),.req_ready(req_ready),
        .req_m(req_m),.req_n(req_n),.req_k(req_k),.req_ml(req_ml),.req_nl(req_nl),.req_kl(req_kl),.req_group(req_group),
        .in_valid(in_valid),.in_ready(in_ready),.in_data(in_data),.in_keep(in_keep));

    always @(posedge clk) begin
        if(rst) begin wr_ack<=0;ack_delay<=0;end
        else begin
            wr_ack<=0;
            if(wr_valid && wr_ready) begin
                if(wr_task_id!=desc.task_id) $fatal(1,"write task id mismatch");
                if(wr_addr!=desc.y_addr+wr_m*desc.y_stride+wr_n*4) $fatal(1,"write address mismatch");
                if(wr_data!==$signed(desc.k*65536)) $fatal(1,"Q16.16 output mismatch");
                write_count<=write_count+1;ack_delay<=4;
            end else if(ack_delay>0) begin
                ack_delay<=ack_delay-1;
                if(ack_delay==1) wr_ack<=1;
            end
        end
    end

    task automatic check(input logic cond,input string message);
        if(!cond) $fatal(1,"SYSTEM_CHECK: %s",message);
    endtask
    task automatic reset_all;
        begin @(negedge clk);rst=1;task_valid=0;load_pause=0;req_gate=1;wr_ready=1;
            repeat(3) @(negedge clk);rst=0;repeat(2) @(negedge clk);end
    endtask
    task automatic make_desc(input integer id,input integer m,input integer n,input integer k);
        begin desc='0;desc.task_id=id;desc.m=m;desc.n=n;desc.k=k;
            desc.a_addr=64'h1000;desc.w_addr=64'h4000;desc.sx_addr=64'h8000;
            desc.sw_addr=64'h9000;desc.y_addr=64'hA000;desc.a_stride=k;
            desc.w_stride=(k+1)/2;desc.sx_stride=((k+3)/4)*2;desc.sw_stride=n*2;desc.y_stride=n*4;
            desc.activation_format=FORMAT_INT8;desc.weight_format=FORMAT_SINT4_PACKED;
            desc.scale_format=FORMAT_UQ4_12;desc.output_format=FORMAT_Q16_16;desc.group_size=4;
        end
    endtask
    task automatic submit;
        begin wait(task_ready);@(negedge clk);task_valid=1;@(negedge clk);task_valid=0;end
    endtask
    task automatic wait_completion(input integer expected_status);
        integer ticks;
        begin ticks=0;while(!completion_valid && ticks<5000) begin @(negedge clk);ticks=ticks+1;end
            check(completion_valid,"completion timeout in test");
            $display("SYSTEM_COMPLETION id=%0d status=%0d expected=%0d cycles=%0d writes=%0d out_count=%0d exp=%0d last=%0b pending=%0b core_done=%0b",
                completion_task_id,completion_status,expected_status,elapsed_cycles,write_count,
                dut.control.output_count,dut.control.expected_outputs,dut.control.accepted_last,dut.control.write_pending,dut.core_done);
            check(completion_status==expected_status,"completion status");
            check(completion_task_id==desc.task_id,"completion task id");
            cycle_total=cycle_total+elapsed_cycles;
        end
    endtask
    task automatic drain;
        begin @(negedge clk);completion_ready=1;@(negedge clk);completion_ready=0;end
    endtask

    initial begin
        for(integer i=0;i<64;i++) begin memory.a[i]=1;memory.packed_w[i]=8'h11;memory.sx[i]=4096;memory.sw[i]=4096;end
        reset_all();
        make_desc(10,3,3,5);submit();wait_completion(STATUS_OK);
        check(write_count==9,"tail M/N/K writes");check(result_available,"result available only after write ack");drain();
        make_desc(11,2,1,1);write_count=0;submit();wait_completion(STATUS_OK);
        check(write_count==2,"second task output count");drain();

        make_desc(12,0,1,1);submit();wait_completion(STATUS_BAD_DIM);check(!result_available,"invalid dimensions hide result");drain();
        make_desc(13,1,1,1);desc.weight_format=8'd9;submit();wait_completion(STATUS_BAD_FORMAT);drain();
        make_desc(14,1,1,1);desc.group_size=8;submit();wait_completion(STATUS_BAD_GROUP);drain();
        make_desc(140,1,1,1);desc.y_addr=64'hA002;submit();wait_completion(STATUS_BAD_ADDRESS);drain();
        make_desc(141,1,3,1);desc.y_stride=8;submit();wait_completion(STATUS_BAD_STRIDE);drain();
        make_desc(142,2,1,1);desc.y_addr=64'hffff_ffff_ffff_fffc;submit();wait_completion(STATUS_BAD_ADDRESS);drain();

        make_desc(15,3,3,5);write_count=0;load_pause=1;submit();repeat(12) @(negedge clk);
        check(write_count==0,"input pause prevents early writes");load_pause=0;wait_completion(STATUS_OK);drain();

        make_desc(16,3,3,5);wr_ready=0;submit();wait(wr_valid);
        begin logic [63:0] held_addr;logic signed [31:0] held_data;
            held_addr=wr_addr;held_data=wr_data;repeat(5) @(negedge clk);
            check(wr_valid && wr_addr==held_addr && wr_data==held_data,"write payload stable under backpressure");
        end
        wr_ready=1;wait_completion(STATUS_OK);drain();

        make_desc(17,3,3,5);req_gate=0;submit();wait_completion(STATUS_TIMEOUT);check(!result_available,"timeout hides result");drain();
        req_gate=1;

        make_desc(18,3,3,5);submit();wait(dut.core_busy);reset_all();
        check(!completion_valid && !result_available,"reset clears completion and result");
        $display("W4A8_SYSTEM_PASS cycles=%0d writes=%0d",cycle_total,write_count);
        $finish;
    end
    initial begin #2000000;$fatal(1,"W4A8_SYSTEM_GLOBAL_TIMEOUT");end
endmodule
