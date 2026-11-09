// No general-purpose I/O, DDR, GT, Aurora or external clock pins.
module array_selftest_top #(parameter integer MODE=1,parameter bit CORRUPT_GOLDEN=0)();
    wire osc,eos,clk,done_level;
    STARTUPE3 #(.PROG_USR("FALSE"),.SIM_CCLK_FREQ(0.0)) startup(
        .CFGCLK(),.CFGMCLK(osc),.DI(),.EOS(eos),.PREQ(),
        .DO(4'b0000),.DTS(4'b1111),.FCSBO(1'b1),.FCSBTS(1'b1),
        .GSR(1'b0),.GTS(1'b0),.KEYCLEARB(1'b1),.PACK(1'b0),
        .USRCCLKO(1'b0),.USRCCLKTS(1'b1),.USRDONEO(rst || done_level),.USRDONETS(1'b0));
    BUFGCE_DIV #(.BUFGCE_DIVIDE(8)) clock_divider(.I(osc),.CE(1'b1),.CLR(1'b0),.O(clk));
    (* async_reg="true" *) logic [3:0] startup_sync=0;
    always_ff @(posedge clk)startup_sync<={startup_sync[2:0],eos};
    wire rst=!startup_sync[3];
    wire finished;wire [7:0] errors;wire [15:0] checksum,comparisons;
    wire negative_finished;wire [7:0] negative_errors;wire [15:0] negative_checksum,negative_comparisons;
    generate if(MODE==0)begin: diagnostic_only
        assign finished=1;assign errors=0;assign checksum=16'hd10a;assign comparisons=0;
        assign negative_finished=1;assign negative_errors=0;assign negative_checksum=0;assign negative_comparisons=0;
    end else begin: selftest
        array_bist_engine #(.CORRUPT_GOLDEN(CORRUPT_GOLDEN)) engine(.*);
        array_bist_engine #(.CORRUPT_GOLDEN(1)) negative_engine(.clk(clk),.rst(rst),.finished(negative_finished),
            .errors(negative_errors),.checksum(negative_checksum),.comparisons(negative_comparisons));
    end endgenerate
    wire [3:0] status=MODE==0?4'hd:!finished?4'h3:errors!=0?4'h2:4'h1;
    wire [55:0] payload={16'hc64a,4'h1,status,MODE==0?8'd0:8'd8,checksum,errors};
    wire [3:0] negative_status=!negative_finished?4'h3:negative_errors!=0?4'h2:4'h1;
    wire [55:0] payload_negative={16'hc64a,4'h1,negative_status,8'd8,negative_checksum,negative_errors};
    done_telemetry #(.ALTERNATE(MODE!=0)) telemetry(.*);
endmodule
