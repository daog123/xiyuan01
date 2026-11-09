module w4a8_memory_validate #(
    parameter integer ADDR_WIDTH=32,GROUP_SIZE=32,MAX_M=64,MAX_N=64,MAX_K=4096
)(
    input w4a8_memory_pkg::memory_task_t desc,
    output logic legal
);
    import w4a8_memory_pkg::*;
    logic [63:0] groups,wb,ae,we,se,te,ye;
    always_comb begin
        groups=(64'(desc.k)+GROUP_SIZE-1)/GROUP_SIZE;
        wb=(64'(desc.k)+1)/2;
        ae=(64'(desc.m)-1)*64'(desc.a_stride)+64'(desc.k);
        we=(64'(desc.n)-1)*64'(desc.w_stride)+wb;
        se=(64'(desc.m)-1)*64'(desc.sx_stride)+2*groups;
        te=(groups-1)*64'(desc.sw_stride)+2*64'(desc.n);
        ye=(64'(desc.m)-1)*64'(desc.y_stride)+4*64'(desc.n);
        legal=desc.m>0 && desc.m<=MAX_M && desc.n>0 && desc.n<=MAX_N &&
            desc.k>0 && desc.k<=MAX_K && desc.group_size==GROUP_SIZE &&
            desc.format_id==MEMORY_FORMAT_V1 && desc.a_stride>=desc.k &&
            64'(desc.w_stride)>=wb && 64'(desc.sx_stride)>=2*groups &&
            64'(desc.sw_stride)>=2*64'(desc.n) && 64'(desc.y_stride)>=4*64'(desc.n) &&
            desc.sx_base[0]==0 && desc.sw_base[0]==0 && desc.sx_stride[0]==0 &&
            desc.sw_stride[0]==0 && desc.y_base[1:0]==0 && desc.y_stride[1:0]==0 &&
            region_ok(desc.a_base,desc.a_bytes,ae,ADDR_WIDTH) && region_ok(desc.w_base,desc.w_bytes,we,ADDR_WIDTH) &&
            region_ok(desc.sx_base,desc.sx_bytes,se,ADDR_WIDTH) && region_ok(desc.sw_base,desc.sw_bytes,te,ADDR_WIDTH) &&
            region_ok(desc.y_base,desc.y_bytes,ye,ADDR_WIDTH) &&
            !overlaps(desc.y_base,desc.y_bytes,desc.a_base,desc.a_bytes) &&
            !overlaps(desc.y_base,desc.y_bytes,desc.w_base,desc.w_bytes) &&
            !overlaps(desc.y_base,desc.y_bytes,desc.sx_base,desc.sx_bytes) &&
            !overlaps(desc.y_base,desc.y_bytes,desc.sw_base,desc.sw_bytes);
    end
endmodule
