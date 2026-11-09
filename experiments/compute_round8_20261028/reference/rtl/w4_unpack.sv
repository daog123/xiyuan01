module w4_unpack(input logic [7:0] packed_byte, input logic high,
                 output wire signed [7:0] value);
    wire [3:0] nibble=high?packed_byte[7:4]:packed_byte[3:0];
    assign value={{4{nibble[3]}},nibble};
endmodule
