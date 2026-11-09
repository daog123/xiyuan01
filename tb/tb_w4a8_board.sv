`timescale 1ns/1ps
module tb_w4a8_board;
    import task_desc_pkg::*;
    import w4a8_memory_pkg::*;
    localparam logic [63:0] DDR_BASE=64'h0000000800000000;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,ddr_ready=0;
    logic [11:0] s_axi_awaddr=0,s_axi_araddr=0;
    logic s_axi_awvalid=0,s_axi_awready,s_axi_wvalid=0,s_axi_wready;
    logic [31:0] s_axi_wdata=0,s_axi_rdata;logic [3:0] s_axi_wstrb=0;
    logic [1:0] s_axi_bresp,s_axi_rresp;
    logic s_axi_bvalid,s_axi_bready=0,s_axi_arvalid=0,s_axi_arready,s_axi_rvalid,s_axi_rready=0;
    logic arvalid,arready,rvalid,rready,rlast,awvalid,awready,wvalid,wready,wlast,bvalid,bready;
    logic [63:0] araddr,awaddr,rdata,wdata;logic [3:0] arid,rid,awid,bid;
    logic [7:0] arlen,awlen,wstrb;logic [2:0] arsize,awsize;logic [1:0] arburst,awburst,rresp,bresp;
    logic setup=0,random_stalls=1,hold_b=0,inject_r=0,inject_b=0;
    logic inject_rlast=0,inject_rid=0,inject_bid=0;
    memory_task_t loaded_desc;
    integer reads,writes,b_count,checks=0,completions=0,outputs=0;
    integer golden[0:4095];logic [7:0] original[0:65535];
    w4a8_board_ip dut(.m_axi_arvalid(arvalid),.m_axi_arready(arready),.m_axi_araddr(araddr),.m_axi_arid(arid),.m_axi_arlen(arlen),.m_axi_arsize(arsize),.m_axi_arburst(arburst),.m_axi_rvalid(rvalid),.m_axi_rready(rready),.m_axi_rdata(rdata),.m_axi_rid(rid),.m_axi_rresp(rresp),.m_axi_rlast(rlast),.m_axi_awvalid(awvalid),.m_axi_awready(awready),.m_axi_awaddr(awaddr),.m_axi_awid(awid),.m_axi_awlen(awlen),.m_axi_awsize(awsize),.m_axi_awburst(awburst),.m_axi_wvalid(wvalid),.m_axi_wready(wready),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_bvalid(bvalid),.m_axi_bready(bready),.m_axi_bid(bid),.m_axi_bresp(bresp),.*);
    w4a8_axi_memory memory(.desc(loaded_desc),.araddr(araddr[31:0]),.awaddr(awaddr[31:0]),.*);
    task automatic require(input bit condition,input string message);
        checks++;if(!condition)$fatal(1,"BOARD_CHECK_FAILED %s time=%0t",message,$time);
    endtask
    always @(posedge clk)if(!rst)begin
        if(arvalid && arready)require(araddr[63:32]==DDR_BASE[63:32],"64-bit read address preserved");
        if(awvalid && awready)require(awaddr[63:32]==DDR_BASE[63:32],"64-bit write address preserved");
    end
    task automatic wr(input logic [11:0] address,input logic [31:0] value,
                      input logic [3:0] strobes=15,input integer order=0,input logic [1:0] response=0);
        logic [1:0] held;
        @(negedge clk);
        fork
            begin
                if(order==2)repeat(3)@(negedge clk);
                s_axi_awaddr=address;s_axi_awvalid=1;
                do @(posedge clk);while(!s_axi_awready);
                @(negedge clk);s_axi_awvalid=0;
            end
            begin
                if(order==1)repeat(3)@(negedge clk);
                s_axi_wdata=value;s_axi_wstrb=strobes;s_axi_wvalid=1;
                do @(posedge clk);while(!s_axi_wready);
                @(negedge clk);s_axi_wvalid=0;
            end
        join
        while(!s_axi_bvalid)@(negedge clk);
        held=s_axi_bresp;require(held===response,"AXI-Lite B response");
        repeat(3)begin @(negedge clk);require(s_axi_bvalid && s_axi_bresp===held,"B stable under backpressure");end
        s_axi_bready=1;@(negedge clk);s_axi_bready=0;
    endtask
    task automatic rd(input logic [11:0] address,output logic [31:0] value,input logic [1:0] response=0);
        logic [31:0] held;
        @(negedge clk);s_axi_araddr=address;s_axi_arvalid=1;
        do @(posedge clk);while(!s_axi_arready);
        @(negedge clk);s_axi_arvalid=0;
        while(!s_axi_rvalid)@(negedge clk);
        held=s_axi_rdata;require(s_axi_rresp===response,"AXI-Lite R response");
        repeat(2)begin @(negedge clk);require(s_axi_rvalid && s_axi_rdata===held && s_axi_rresp===response,"R stable under backpressure");end
        value=held;s_axi_rready=1;@(negedge clk);s_axi_rready=0;
    endtask
    task automatic load_job(input integer job);
        integer f,rc,v;
        logic [31:0] mailbox_words[0:25];
        f=$fopen($sformatf("g32_job%0d.txt",job),"r");require(f!=0,"vector opened");
        rc=$fscanf(f,"%d %d %d %d %d %d",loaded_desc.task_id,loaded_desc.m,loaded_desc.n,
            loaded_desc.k,loaded_desc.format_id,loaded_desc.group_size);require(rc==6,"shape read");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_base,loaded_desc.w_base,loaded_desc.sx_base,
            loaded_desc.sw_base,loaded_desc.y_base);require(rc==5,"bases read");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_stride,loaded_desc.w_stride,loaded_desc.sx_stride,
            loaded_desc.sw_stride,loaded_desc.y_stride);require(rc==5,"strides read");
        rc=$fscanf(f,"%d %d %d %d %d",loaded_desc.a_bytes,loaded_desc.w_bytes,loaded_desc.sx_bytes,
            loaded_desc.sw_bytes,loaded_desc.y_bytes);require(rc==5,"sizes read");
        for(integer i=0;i<loaded_desc.m*loaded_desc.n;i++)begin
            rc=$fscanf(f,"%d",v);require(rc==1,"golden read");golden[i]=v;
        end
        $fclose(f);
        if($test$plusargs("corrupt_expected"))golden[0]++;
        $readmemh($sformatf("g32_job%0d.hex",job),memory.mem);
        for(integer i=0;i<65536;i++)original[i]=memory.mem[i];
        @(negedge clk);setup=1;@(negedge clk);setup=0;
        $readmemh($sformatf("g32_job%0d_mailbox.hex",job),mailbox_words);
        for(integer i=0;i<26;i++)wr(12'('h020+4*i),mailbox_words[i],15,i%3);
    endtask
    task automatic finish_task(input logic [7:0] expected);
        logic [31:0] state_word,id_word,status_word,cycles_word;
        integer wd;
        wd=0;state_word=0;
        while(!state_word[2])begin rd('h00c,state_word);wd++;require(wd<50000,"completion watchdog");end
        rd('h010,id_word);rd('h014,status_word);rd('h018,cycles_word);
        require(id_word===loaded_desc.task_id && status_word==expected,"completion identity/status");
        require(state_word[4]==(expected==STATUS_OK) && !state_word[1] && !state_word[0],"completion state");
        require(cycles_word>0,"real core cycles observed");
        repeat(3)begin
            rd('h010,id_word);rd('h014,status_word);
            require(id_word===loaded_desc.task_id && status_word==expected,"completion snapshot persists");
        end
        wr('h008,1,15,0,2); // Cannot replay a completed task before ACK.
        wr('h020,0,15,1,2); // Cannot overwrite its descriptor either.
        wr('h008,2);completions++;
        rd('h00c,state_word);require(state_word==9,"ACK reopens admission");
    endtask
    task automatic compare_memory;
        integer addr,v;bit destination;
        for(integer r=0;r<loaded_desc.m;r++)for(integer c=0;c<loaded_desc.n;c++)begin
            addr=loaded_desc.y_base+r*loaded_desc.y_stride+4*c;
            v={memory.mem[addr+3],memory.mem[addr+2],memory.mem[addr+1],memory.mem[addr]};
            require(v===golden[r*loaded_desc.n+c],"external Y bit exact");outputs++;
        end
        for(integer i=0;i<65536;i++)begin
            destination=i>=loaded_desc.y_base && i<loaded_desc.y_base+loaded_desc.y_bytes &&
                (i-loaded_desc.y_base)%loaded_desc.y_stride<4*loaded_desc.n;
            if(!destination)require(memory.mem[i]===original[i],"input/padding/guards unchanged");
        end
    endtask
    logic [31:0] word_read;
    initial begin
        repeat(5)@(negedge clk);rst=0;
        rd('h000,word_read);require(word_read==32'h58495738,"image magic");
        rd('h004,word_read);require(word_read==1,"mailbox ABI");
        rd('h09c,word_read);require(word_read==64,"address width capability");
        wr('h008,1,15,0,2); // Calibration unavailable.
        wr('h000,0,15,0,2);wr('h008,3,15,0,2);wr('h021,1,15,1,2);
        rd('h003,word_read,2);rd('h100,word_read,2);
        wr('h020,32'h11223344,15,1);wr('h020,32'hffeeddcc,5,2);
        rd('h020,word_read);require(word_read==32'h11ee33cc,"byte strobes merge");
        wr('h024,32'h00010001,15,0,2);
        wr('h008,1,0);require(reads==0 && writes==0,"zero strobes do not launch");
        // A partially accepted AXI-Lite write must be discarded by shared reset.
        @(negedge clk);s_axi_awaddr='h020;s_axi_awvalid=1;
        do @(posedge clk);while(!s_axi_awready);
        @(negedge clk);s_axi_awvalid=0;rst=1;
        repeat(3)@(negedge clk);rst=0;ddr_ready=1;
        rd('h020,word_read);require(word_read==0 && !s_axi_bvalid,"reset discards partial write");
        for(integer job=0;job<2;job++)begin
            load_job(job);wr('h008,1);wr('h024,0,15,2,2);
            finish_task(STATUS_OK);compare_memory();
        end
        load_job(0);hold_b=1;wr('h008,1);
        wait(writes>0);repeat(80)@(negedge clk);
        rd('h00c,word_read);require(word_read[1] && !word_read[2],"pending B prevents DONE");
        wr('h008,2,15,0,2);wr('h008,1,15,2,2);
        hold_b=0;finish_task(STATUS_OK);compare_memory();
        load_job(0);inject_r=1;wr('h008,1);finish_task(STATUS_READ_ERROR);inject_r=0;
        require(writes==0,"read error does not invent output");
        load_job(0);inject_b=1;wr('h008,1);finish_task(STATUS_WRITE_ERROR);inject_b=0;
        load_job(1);wr('h008,1);finish_task(STATUS_OK);compare_memory();
        load_job(0);wr('h074,1);wr('h008,1);finish_task(STATUS_BAD_REGION);
        require(reads==0 && writes==0,"invalid capacity has no memory traffic");
        load_job(0);wr('h070,12);wr('h008,1);finish_task(STATUS_BAD_GROUP);
        require(reads==0 && writes==0,"invalid group has no memory traffic");
        $display("W4A8_BOARD_TESTS_PASS completions=%0d outputs=%0d checks=%0d high_address=%h",completions,outputs,checks,DDR_BASE);
        $finish;
    end
    initial begin #300000000;$fatal(1,"BOARD_GLOBAL_TIMEOUT");end
    initial if($test$plusargs("timeout_probe"))begin #10000;$fatal(1,"BOARD_FORCED_TIMEOUT");end
endmodule
