`timescale 1ns/1ps
module tb_array_bist;
    logic clk=0;always #5 clk=~clk;
    logic rst=1;
    wire finished,negative_finished;wire [7:0] errors,negative_errors;
    wire [15:0] checksum,negative_checksum,comparisons,negative_comparisons;
    array_bist_engine good(.*);
    array_bist_engine #(.CORRUPT_GOLDEN(1)) bad(.clk(clk),.rst(rst),.finished(negative_finished),
        .errors(negative_errors),.checksum(negative_checksum),.comparisons(negative_comparisons));
    wire [55:0] payload={16'hc64a,4'h1,4'h1,8'd8,checksum,errors};
    wire [55:0] payload_negative={16'hc64a,4'h1,4'h2,8'd8,negative_checksum,negative_errors};
    wire done_level;
    done_telemetry #(.UNIT_BITS(3),.WARMUP_BITS(4),.ALTERNATE(1)) serial(.*);
    integer f;
    initial begin
        repeat(5)@(negedge clk);rst=0;
        wait(finished && negative_finished);@(negedge clk);
        if(errors!=0 || negative_errors!=1 || checksum!=negative_checksum || comparisons!=128 || negative_comparisons!=128)
            $fatal(1,"ARRAY_BIST_CHECK_FAILED errors=%0d negative=%0d checksum=%h",errors,negative_errors,checksum);
        $display("ARRAY_BIST_SIM_PASS cases=8 outputs=128 errors=%0d negative_errors=%0d checksum=%h",errors,negative_errors,checksum);
        f=$fopen("telemetry_samples.csv","w");
        repeat(10000)begin @(negedge clk);$fdisplay(f,"%0d,%0d",$time,done_level);end
        $fclose(f);$display("ARRAY_TELEMETRY_SAMPLES_READY");$finish;
    end
    initial begin #1000000;$fatal(1,"ARRAY_BIST_TIMEOUT");end
endmodule
