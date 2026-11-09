`timescale 1ns/1ps
// Harness only. The DUT is pinned upstream RTL with a declaration-order fix for XSim.
module tb_opentpu_controlled;
    localparam integer IMPL=2;
    import otpu_pkg::*;import otpu_fp::*;
    localparam integer D=64,MCOLS=1,LANES=8,DEPTH=64;
    logic clk=0;always #5 clk=~clk;
    logic rst=1,start=0,go=0,rdy,done,computing;
    cmd_t cmd;
    logic [6:0] pf_level;logic pf_starve,pf_block,pf_u;logic [3:0][31:0] pf_uv;
    logic [15:0] act_blk,act_blk2;logic [3:0] act_hi;logic [7:0] act_grp;logic act_ren;
    logic [MCOLS*D*8-1:0] act_data='0;logic [MCOLS*32-1:0] act_scale='0;
    logic a_req,b_req;logic [31:0] a_addr,b_addr;
    logic a_gnt,b_gnt,a_rvalid=0,b_rvalid=0;logic [31:0] a_rdata=0,a_rdata2=0;logic [D*8-1:0] b_rdata=0;
    logic [LANES-1:0] t_ren,t_wen;logic [LANES-1:0][31:0] t_raddr,t_rdata='0,t_waddr,t_wdata;logic t_gnt=1;
    integer a[0:32767],w[0:262143],golden[0:511];bit seen[0:511];
    integer credit=0,preload_cycles,command_started;bit feeding=0;integer act_mem[0:32767];
    assign a_gnt=credit>=(dut.need_b?D:0)+4;assign b_gnt=a_gnt;
    integer m,n,k,format_id,row_stride,checks=0,outputs=0,macs=0,pops=0,requests=0,ticks=0,report;
    bit checking=0;
    otpu_mxu #(.D(D),.MCOLS(MCOLS),.ROWS(8),.DEPTH(DEPTH),.LANES(LANES),.IMPL(IMPL)) dut(.*);
    task automatic require(input bit ok,input string message);
        checks++;if(!ok)$fatal(1,"OPENTPU_CORE_FAILED %s time=%0t",message,$time);
    endtask
    function automatic logic [3:0] nibble(input integer value);
        if(format_id==2) return value<0?4'ha:value>0?4'h2:4'h0;
        return 4'(value);
    endfunction
    always @(posedge clk) begin
        ticks++;
        if(rst) begin b_rvalid<=0;a_rvalid<=0;credit<=0;end
        else begin
            b_rvalid<=b_req;a_rvalid<=a_req;
            if(feeding) begin
                require(credit>=(b_req?D:0)+(a_req?4:0),"shared ingress budget never overspends");
                credit<=credit+8-(b_req?D:0)-(a_req?4:0)>4*D?4*D:credit+8-(b_req?D:0)-(a_req?4:0);
            end else credit<=0;
            if(a_req) begin a_rdata<=format_id==2?32'h11113f00:32'h11113f80;a_rdata2<=32'h11113f80;end
            if(b_req) begin
                integer offset,col,q;
                offset=4*integer'(b_addr);col=offset/row_stride;offset=offset%row_stride;
                require(col<n,"weight row address");
                for(integer j=0;j<D;j++) begin
                    if(format_id==0) begin q=offset+j;b_rdata[j*8 +:8]<=q<k?8'(w[col*k+q]):8'd0;end
                    else begin
                        q=2*(offset+j);
                        b_rdata[j*8 +:8]<={q+1<k?nibble(w[col*k+q+1]):4'd0,q<k?nibble(w[col*k+q]):4'd0};
                    end
                end
                if(checking) requests++;
            end
            if(act_ren) for(integer j=0;j<MCOLS;j++) begin
                integer row,block_index,q;
                row=integer'(act_grp)*MCOLS+j;block_index=act_hi[j]?integer'(act_blk2):integer'(act_blk);
                if(dut.c_pair && j>=m) row=j-m;
                act_scale[j*32 +:32]<=32'h3f800000;
                for(integer i=0;i<D;i++) begin
                    q=block_index*D+i;
                    act_data[(j*D+i)*8 +:8]<=(row<m && q<k)?8'(act_mem[row*k+q]):8'd0;
                end
            end
            if(checking && computing) begin
                integer useful_rows,terms;
                useful_rows=m-integer'(act_grp)*MCOLS;if(useful_rows>MCOLS)useful_rows=MCOLS;
                terms=D;
                if(dut.c_pair) begin useful_rows=m;if(!(dut.last_k && dut.c_KB[0]))terms=2*D;end
                macs+=useful_rows*terms;pops++;
            end
            if(checking) for(integer lane=0;lane<LANES;lane++) if(t_wen[lane]) begin
                integer index;logic [31:0] expected;
                index=integer'(t_waddr[lane]);require(index<m*n,"TMEM output coordinate");
                require(!seen[index],"TMEM output exactly once");expected=32'(golden[index]);
                require(t_wdata[lane]===expected || ((t_wdata[lane]&32'h7fffffff)==0 && expected==0),
                    $sformatf("numeric result index=%0d got=%h expected=%h",index,t_wdata[lane],expected));
                seen[index]=1;outputs++;
            end
        end
    end
    initial begin
        integer f,rc,count,cid,started,wd;
        cmd='0;report=$fopen("opentpu_results.csv","w");
        $fdisplay(report,"format_id,case_id,M,N,K,cycles,valid_macs,input_issue_cycles,weight_requests,core_cycles,preload_cycles");
        for(integer fmt=1;fmt<2;fmt++) begin
            format_id=fmt;f=$fopen("common_vectors.txt","r");require(f!=0,"vectors opened");rc=$fscanf(f,"%d",count);require(rc==1 && count==8,"case count");
            for(integer test=0;test<count;test++) begin
                rc=$fscanf(f,"%d %d %d %d",cid,m,n,k);require(rc==4,"shape");
                for(integer i=0;i<m*k;i++)rc=$fscanf(f,"%d",a[i]);
                for(integer i=0;i<n*k;i++)rc=$fscanf(f,"%d",w[i]);
                for(integer i=0;i<m*n;i++)rc=$fscanf(f,"%d",golden[i]);
                @(negedge clk);rst=1;start=0;go=0;checking=0;feeding=0;
                // Upstream pipeline delay lines have no reset. Hold the public
                // reset until invalid metadata has flushed in four-state XSim.
                repeat(100)@(negedge clk);rst=0;repeat(20)@(negedge clk);
                row_stride=fmt==0?k:((k+2*D-1)/(2*D))*D;
                cmd='0;cmd.op=OP_MM;cmd.flags=fmt==0?8'h01:fmt==1?8'h10:8'h20;
                if(fmt!=0 && 2*m<=MCOLS)cmd.flags[6]=1;
                cmd.w1=0;cmd.w2=32'h10000000;cmd.w3=0;cmd.w4={16'(k/D),16'(n)};
                cmd.w5=row_stride;cmd.w6={8'd0,8'(m),16'(n)};
                // Native PAIR scale reads span two words, including a padded
                // partner for odd KB. Keep every output row 8-byte aligned.
                cmd.w7=cmd.flags[6]?8*((k/D+1)/2):4*(k/D);
                outputs=0;macs=0;pops=0;requests=0;for(integer i=0;i<m*n;i++)seen[i]=0;
                require(rdy,"command admission");checking=1;started=ticks+1;
                // Same empty-cache boundary: preload INT8 ACT at 8 bytes/clock.
                for(integer offset=0;offset<m*k;offset+=8) begin
                    @(negedge clk);for(integer byte_index=0;byte_index<8;byte_index++) if(offset+byte_index<m*k)act_mem[offset+byte_index]=a[offset+byte_index];
                end
                // Native FP32 ACT-scale cache: same useful bytes as UQ4.12/group32.
                repeat((4*m*(k/D)+7)/8)@(negedge clk);
                command_started=ticks+1;preload_cycles=command_started-started;feeding=1;start=1;
                @(negedge clk);start=0;go=1;@(negedge clk);go=0;
                wd=0;while(!done)begin @(negedge clk);wd++;require(wd<200000,"watchdog");end
                require(outputs==m*n && macs==m*n*k,"all mathematical work and outputs");
                $fdisplay(report,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",fmt,cid,m,n,k,ticks-started,macs,pops,requests,ticks-command_started,preload_cycles);
                $display("OPENTPU_CORE_CASE_PASS format=%0d case=%0d cycles=%0d macs=%0d",fmt,cid,ticks-started,macs);
                checking=0;
            end
            $fclose(f);
        end
        $fclose(report);$display("OPENTPU_CORE_PASS checks=%0d cases=8",checks);$finish;
    end
    initial begin #100000000;$fatal(1,"OPENTPU_CORE_TIMEOUT");end
endmodule
