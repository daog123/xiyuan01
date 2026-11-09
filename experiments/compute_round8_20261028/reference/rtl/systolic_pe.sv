// Output-stationary PE: data/valid forwarding and MAC share one advance.
module systolic_pe(
    input logic clk,rst,clear,advance,
    input logic signed [7:0] a_in,b_in,
    input logic a_valid,b_valid,
    output logic signed [7:0] a_out,b_out,
    output logic a_valid_out,b_valid_out,
    output wire signed [31:0] acc,
    output wire fire
);
    assign fire=!rst && !clear && advance && a_valid && b_valid;
    mac_pe mac(.clk(clk),.rst(rst),.load(clear),.seed(32'sd0),
        .en(fire),.a(a_in),.b(b_in),.acc(acc));
    always_ff @(posedge clk) begin
        if(rst || clear) begin
            a_out<=0;b_out<=0;a_valid_out<=0;b_valid_out<=0;
        end else if(advance) begin
            a_out<=a_in;b_out<=b_in;
            a_valid_out<=a_valid;b_valid_out<=b_valid;
        end
    end
endmodule
