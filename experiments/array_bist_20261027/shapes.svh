function automatic [15:0] rows_for(input logic [2:0] cid);
case(cid)
3'd0: rows_for=16'd4;
3'd1: rows_for=16'd4;
3'd2: rows_for=16'd3;
3'd3: rows_for=16'd1;
3'd4: rows_for=16'd2;
3'd5: rows_for=16'd4;
3'd6: rows_for=16'd4;
3'd7: rows_for=16'd4;
default: rows_for=0;
endcase
endfunction
function automatic [15:0] cols_for(input logic [2:0] cid);
case(cid)
3'd0: cols_for=16'd4;
3'd1: cols_for=16'd4;
3'd2: cols_for=16'd2;
3'd3: cols_for=16'd4;
3'd4: cols_for=16'd3;
3'd5: cols_for=16'd4;
3'd6: cols_for=16'd4;
3'd7: cols_for=16'd4;
default: cols_for=0;
endcase
endfunction
function automatic [15:0] k_for(input logic [2:0] cid);
case(cid)
3'd0: k_for=16'd32;
3'd1: k_for=16'd31;
3'd2: k_for=16'd17;
3'd3: k_for=16'd1;
3'd4: k_for=16'd8;
3'd5: k_for=16'd16;
3'd6: k_for=16'd32;
3'd7: k_for=16'd37;
default: k_for=0;
endcase
endfunction
