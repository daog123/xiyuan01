`timescale 1ns/1ps
module tb_packed_pair;
    logic signed [7:0] a;logic signed [3:0] w0,w1;wire signed [15:0] p0,p1;
    integer checks=0;
    w4a8_packed_pair dut(.*);
    initial begin
        for(integer av=-128;av<=127;av++)for(integer x=-8;x<=7;x++)for(integer y=-8;y<=7;y++) begin
            a=8'(av);w0=4'(x);w1=4'(y);#1;
            if(p0!==16'(av*x) || p1!==16'(av*y))$fatal(1,"PACKED_PAIR_FAILED a=%0d w0=%0d w1=%0d p0=%0d p1=%0d",av,x,y,p0,p1);
            checks++;
        end
        $display("PACKED_PAIR_EXHAUSTIVE_PASS combinations=%0d products=%0d",checks,2*checks);$finish;
    end
endmodule
