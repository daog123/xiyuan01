// Incoming vectors are unskewed; PE(r,c) consumes them r+c advances later.
module systolic_array #(
    parameter integer ROWS=4,COLS=4
)(
    input logic clk,rst,clear,advance,inject_valid,
    input logic [15:0] valid_rows,valid_cols,
    input logic signed [7:0] a[0:ROWS-1],b[0:COLS-1],
    output wire signed [31:0] acc[0:ROWS*COLS-1],
    output wire [ROWS*COLS-1:0] pe_fire
);
    wire signed [7:0] a_path[0:ROWS-1][0:COLS];
    wire signed [7:0] b_path[0:ROWS][0:COLS-1];
    wire a_vpath[0:ROWS-1][0:COLS];
    wire b_vpath[0:ROWS][0:COLS-1];
    for(genvar r=0;r<ROWS;r++) begin: a_skew
        if(r==0) begin: direct
            assign a_path[r][0]=a[r];
            assign a_vpath[r][0]=inject_valid && r<valid_rows;
        end else begin: delay_line
            logic signed [7:0] data[0:r-1];
            logic valid[0:r-1];
            always_ff @(posedge clk) begin
                if(rst || clear) begin
                    for(integer d=0;d<r;d++) begin data[d]<=0;valid[d]<=0;end
                end else if(advance) begin
                    data[0]<=a[r];valid[0]<=inject_valid && r<valid_rows;
                    for(integer d=1;d<r;d++) begin data[d]<=data[d-1];valid[d]<=valid[d-1];end
                end
            end
            assign a_path[r][0]=data[r-1];
            assign a_vpath[r][0]=valid[r-1];
        end
    end
    for(genvar c=0;c<COLS;c++) begin: b_skew
        if(c==0) begin: direct
            assign b_path[0][c]=b[c];
            assign b_vpath[0][c]=inject_valid && c<valid_cols;
        end else begin: delay_line
            logic signed [7:0] data[0:c-1];
            logic valid[0:c-1];
            always_ff @(posedge clk) begin
                if(rst || clear) begin
                    for(integer d=0;d<c;d++) begin data[d]<=0;valid[d]<=0;end
                end else if(advance) begin
                    data[0]<=b[c];valid[0]<=inject_valid && c<valid_cols;
                    for(integer d=1;d<c;d++) begin data[d]<=data[d-1];valid[d]<=valid[d-1];end
                end
            end
            assign b_path[0][c]=data[c-1];
            assign b_vpath[0][c]=valid[c-1];
        end
    end
    for(genvar r=0;r<ROWS;r++) begin: row
        for(genvar c=0;c<COLS;c++) begin: col
            systolic_pe pe(.clk(clk),.rst(rst),.clear(clear),.advance(advance),
                .a_in(a_path[r][c]),.b_in(b_path[r][c]),
                .a_valid(a_vpath[r][c]),.b_valid(b_vpath[r][c]),
                .a_out(a_path[r][c+1]),.b_out(b_path[r+1][c]),
                .a_valid_out(a_vpath[r][c+1]),.b_valid_out(b_vpath[r+1][c]),
                .acc(acc[r*COLS+c]),.fire(pe_fire[r*COLS+c]));
        end
    end
endmodule
