module mac_array #(
    parameter integer ROWS=4, COLS=4
)(
    input logic clk, rst, clear, en,
    input logic signed [7:0] a [0:ROWS-1],
    input logic signed [7:0] b [0:COLS-1],
    output wire signed [31:0] acc [0:ROWS*COLS-1]
);
    for (genvar r=0; r<ROWS; r=r+1) begin : row
        for (genvar c=0; c<COLS; c=c+1) begin : col
            mac_pe pe (.clk(clk),.rst(rst),.load(clear),.seed(32'sd0),
                       .en(en),.a(a[r]),.b(b[c]),.acc(acc[r*COLS+c]));
        end
    end
endmodule
