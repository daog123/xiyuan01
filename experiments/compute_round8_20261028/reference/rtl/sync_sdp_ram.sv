// One synchronous read port and one synchronous write port. No memory reset.
module sync_sdp_ram #(
    parameter integer WIDTH=8, DEPTH=512,
    parameter STYLE="block",
    parameter integer AW=(DEPTH<=1)?1:$clog2(DEPTH)
)(
    input logic clk, wr_en,
    input logic [AW-1:0] wr_addr,
    input logic [WIDTH-1:0] wr_data,
    input logic rd_en,
    input logic [AW-1:0] rd_addr,
    output logic [WIDTH-1:0] rd_data
);
    (* ram_style=STYLE *) logic [WIDTH-1:0] mem [0:DEPTH-1];
    always_ff @(posedge clk) begin
        if (wr_en) mem[wr_addr] <= wr_data;
        if (rd_en) rd_data <= mem[rd_addr];
    end
endmodule
