// Exercises the project's unchanged production compute array, in systolic mode.
module array_bist_engine #(parameter bit CORRUPT_GOLDEN=0)(
    input logic clk,rst,
    output logic finished,output logic [7:0] errors,
    output logic [15:0] checksum,output logic [15:0] comparisons
);
    `include "shapes.svh"
    logic [7:0] a_rom[0:2047],b_rom[0:2047];
    logic [31:0] golden_rom[0:127];
    initial begin $readmemh("a.hex",a_rom);$readmemh("b.hex",b_rom);$readmemh("golden.hex",golden_rom);end
    typedef enum logic [1:0] {CLEAR,RUN,CHECK,REPORT} state_t;
    state_t state;
    logic [2:0] cid;
    logic [6:0] step;
    logic [3:0] slot;
    logic [7:0] wall;
    wire clear=state==CLEAR;
    wire advance=state==RUN && wall[2:0]!=3'd5;
    wire inject_valid=state==RUN && step<k_for(cid);
    logic signed [7:0] a[0:3],b[0:3],vector_a[0:3],vector_b[0:3][0:3];
    wire signed [31:0] acc[0:15];wire [15:0] pe_fire;
    always_comb begin
        for(integer r=0;r<4;r++)begin
            a[r]=step<64?a_rom[integer'(cid)*256+r*64+integer'(step)]:0;
            b[r]=step<64?b_rom[integer'(cid)*256+r*64+integer'(step)]:0;
            vector_a[r]=0;
            for(integer c=0;c<4;c++)vector_b[r][c]=0;
        end
    end
    (* keep_hierarchy="yes", dont_touch="yes" *)
    w4a8_compute_array #(.ROWS(4),.COLS(4),.BROADCAST_MAC(0),.PACKED_MAC(0)) array(
        .clk(clk),.rst(rst),.clear(clear),.advance(advance),.inject_valid(inject_valid),
        .valid_rows(rows_for(cid)),.valid_cols(cols_for(cid)),
        .vector_mode(1'b0),.vector_shift(3'd0),.vector_lanes(16'd0),
        .vector_a(vector_a),.vector_b(vector_b),.a(a),.b(b),.acc(acc),.pe_fire(pe_fire));
    wire [31:0] expected=golden_rom[{cid,slot}] ^ ((CORRUPT_GOLDEN && cid==0 && slot==0)?32'd1:32'd0);
    always_ff @(posedge clk)begin
        if(rst)begin state<=CLEAR;cid<=0;step<=0;slot<=0;wall<=0;finished<=0;errors<=0;checksum<=0;comparisons<=0;end
        else begin
            wall<=wall+1;
            case(state)
                CLEAR:begin step<=0;slot<=0;state<=RUN;end
                RUN:if(advance)begin
                    if(step>=k_for(cid)+8)begin slot<=0;state<=CHECK;end
                    else step<=step+1;
                end
                CHECK:begin
                    if(acc[slot]!==expected && errors!=255)errors<=errors+1;
                    checksum<={checksum[14:0],checksum[15]} ^ acc[slot][15:0] ^ acc[slot][31:16] ^ {9'd0,cid,slot};
                    comparisons<=comparisons+1;
                    if(slot==15)begin
                        if(cid==7)state<=REPORT;
                        else begin cid<=cid+1;state<=CLEAR;end
                    end else slot<=slot+1;
                end
                REPORT:finished<=1;
            endcase
        end
    end
endmodule
