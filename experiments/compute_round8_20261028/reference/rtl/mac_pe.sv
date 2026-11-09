module mac_pe (
    input logic clk, rst, load,
    input logic signed [31:0] seed,
    input logic en,
    input logic signed [7:0] a, b,
    output logic signed [31:0] acc
);
    (* use_dsp="yes" *) logic signed [15:0] product;
    logic signed [31:0] product32;
    assign product = a * b;
    assign product32 = {{16{product[15]}},product};
    // Carry beyond bit 31 is discarded: modulo 2^32, no saturation.
    always_ff @(posedge clk) begin
        if (rst) acc <= 32'sd0;
        else if (load) acc <= seed;
        else if (en) acc <= acc + product32;
    end
endmodule
