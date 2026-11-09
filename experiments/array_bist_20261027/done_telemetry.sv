// Manchester diagnostic frame on the dedicated DONE signal, after startup.
// Idle high 12 units, sync low 6, sync high 2, then 64 Manchester bits (MSB first).
module done_telemetry #(parameter integer UNIT_BITS=18,WARMUP_BITS=24,parameter bit ALTERNATE=0)(
    input logic clk,rst,input logic [55:0] payload,payload_negative,output logic done_level
);
    logic [UNIT_BITS-1:0] unit_count=0;
    logic [WARMUP_BITS-1:0] warmup=0;
    logic enabled=0;
    logic [7:0] phase=0;
    logic [63:0] frame=0;
    logic negative_frame=0;
    function automatic [7:0] crc8(input logic [55:0] value);
        logic [7:0] crc;crc=0;
        for(integer i=55;i>=0;i--)begin
            if(crc[7]^value[i])crc={crc[6:0],1'b0}^8'h07;
            else crc={crc[6:0],1'b0};
        end
        return crc;
    endfunction
    always_comb begin
        done_level=1;
        if(!rst && enabled)begin
            if(phase>=12 && phase<18)done_level=0;
            else if(phase>=20)begin
                // A '1' is high/low; a '0' is low/high.
                done_level=frame[63-((phase-20)>>1)] ^ phase[0];
            end
        end
    end
    always_ff @(posedge clk)begin
        if(rst)begin warmup<=0;enabled<=0;phase<=0;unit_count<=0;frame<=0;negative_frame<=0;end
        else if(!enabled)begin
            warmup<=warmup+1;
            if(&warmup)begin enabled<=1;frame<={payload,crc8(payload)};end
        end else begin
            unit_count<=unit_count+1;
            if(&unit_count)begin
                if(phase==147)begin
                    phase<=0;
                    if(ALTERNATE && !negative_frame)frame<={payload_negative,crc8(payload_negative)};
                    else frame<={payload,crc8(payload)};
                    if(ALTERNATE)negative_frame<=~negative_frame;
                end
                else phase<=phase+1;
            end
        end
    end
endmodule
