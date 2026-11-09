// LANES independent 1R1W banks; one scalar write, parallel synchronous read.
module tile_buffer #(
    parameter integer LANES=4, TILE_K=8,
    parameter integer KW=(TILE_K<=1)?1:$clog2(TILE_K),
    parameter integer LW=(LANES<=1)?1:$clog2(LANES)
)(
    input logic clk, wr_en,
    input logic [LW-1:0] wr_lane,
    input logic [KW-1:0] wr_k,
    input logic signed [7:0] wr_data,
    input logic rd_en,
    input logic [KW-1:0] rd_k,
    output wire signed [7:0] data [0:LANES-1]
);
    for (genvar lane=0; lane<LANES; lane=lane+1) begin : bank
        sync_sdp_ram #(.WIDTH(8),.DEPTH(TILE_K),.STYLE("distributed")) ram (
            .clk(clk),.wr_en(wr_en && wr_lane==lane),.wr_addr(wr_k),
            .wr_data(wr_data),.rd_en(rd_en),.rd_addr(rd_k),.rd_data(data[lane]));
    end
endmodule
