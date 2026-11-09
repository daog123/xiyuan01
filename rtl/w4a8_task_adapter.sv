// Map the A/D host ABI onto the bounded B/F storage contract.
// Capacities describe caller-owned allocations; never infer them from shape.
module w4a8_task_adapter #(
    parameter integer ADDR_WIDTH=32,GROUP_SIZE=32,MAX_M=64,MAX_N=64,MAX_K=4096
)(
    input task_desc_pkg::task_desc_t host_desc,
    input logic [31:0] a_bytes,w_bytes,sx_bytes,sw_bytes,y_bytes,
    output w4a8_memory_pkg::memory_task_t memory_desc,
    output logic [7:0] status
);
    import task_desc_pkg::*;
    import w4a8_memory_pkg::*;
    logic memory_legal;
    logic [63:0] groups;
    w4a8_memory_validate #(.ADDR_WIDTH(ADDR_WIDTH),.GROUP_SIZE(GROUP_SIZE),.MAX_M(MAX_M),.MAX_N(MAX_N),.MAX_K(MAX_K))
        validate(.desc(memory_desc),.legal(memory_legal));
    always_comb begin
        groups=(64'(host_desc.k)+GROUP_SIZE-1)/GROUP_SIZE;
        memory_desc='0;
        memory_desc.task_id=host_desc.task_id;
        memory_desc.m=host_desc.m;memory_desc.n=host_desc.n;memory_desc.k=host_desc.k;
        memory_desc.format_id=MEMORY_FORMAT_V1;memory_desc.group_size=host_desc.group_size;
        memory_desc.a_base=host_desc.a_addr;memory_desc.w_base=host_desc.w_addr;
        memory_desc.sx_base=host_desc.sx_addr;memory_desc.sw_base=host_desc.sw_addr;
        memory_desc.y_base=host_desc.y_addr;
        memory_desc.a_stride=host_desc.a_stride;memory_desc.w_stride=host_desc.w_stride;
        memory_desc.sx_stride=host_desc.sx_stride;memory_desc.sw_stride=host_desc.sw_stride;
        memory_desc.y_stride=host_desc.y_stride;
        memory_desc.a_bytes=a_bytes;memory_desc.w_bytes=w_bytes;
        memory_desc.sx_bytes=sx_bytes;memory_desc.sw_bytes=sw_bytes;memory_desc.y_bytes=y_bytes;
        if(host_desc.m==0 || host_desc.n==0 || host_desc.k==0 ||
            host_desc.m>MAX_M || host_desc.n>MAX_N || host_desc.k>MAX_K) status=STATUS_BAD_DIM;
        else if(host_desc.activation_format!=FORMAT_INT8 || host_desc.weight_format!=FORMAT_SINT4_PACKED ||
            host_desc.scale_format!=FORMAT_UQ4_12 || host_desc.output_format!=FORMAT_Q16_16) status=STATUS_BAD_FORMAT;
        else if(host_desc.group_size!=GROUP_SIZE) status=STATUS_BAD_GROUP;
        else if(host_desc.flags!=0) status=STATUS_BAD_FLAGS;
        else if(host_desc.a_addr==0 || host_desc.w_addr==0 || host_desc.sx_addr==0 ||
            host_desc.sw_addr==0 || host_desc.y_addr==0 ||
            host_desc.sx_addr[0] || host_desc.sw_addr[0] || |host_desc.y_addr[1:0] ||
            65'(host_desc.a_addr)+65'(a_bytes)>(65'd1<<ADDR_WIDTH) ||
            65'(host_desc.w_addr)+65'(w_bytes)>(65'd1<<ADDR_WIDTH) ||
            65'(host_desc.sx_addr)+65'(sx_bytes)>(65'd1<<ADDR_WIDTH) ||
            65'(host_desc.sw_addr)+65'(sw_bytes)>(65'd1<<ADDR_WIDTH) ||
            65'(host_desc.y_addr)+65'(y_bytes)>(65'd1<<ADDR_WIDTH)) status=STATUS_BAD_ADDRESS;
        else if(64'(host_desc.a_stride)<64'(host_desc.k) ||
            64'(host_desc.w_stride)<(64'(host_desc.k)+1)/2 ||
            64'(host_desc.sx_stride)<2*groups || 64'(host_desc.sw_stride)<2*64'(host_desc.n) ||
            64'(host_desc.y_stride)<4*64'(host_desc.n) ||
            host_desc.sx_stride[0] || host_desc.sw_stride[0] || |host_desc.y_stride[1:0]) status=STATUS_BAD_STRIDE;
        else if(!memory_legal) status=STATUS_BAD_REGION;
        else status=STATUS_OK;
    end
endmodule
