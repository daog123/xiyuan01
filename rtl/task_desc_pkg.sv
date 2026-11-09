package task_desc_pkg;
    localparam logic [7:0] FORMAT_INT8=8'd1, FORMAT_SINT4_PACKED=8'd1, FORMAT_UQ4_12=8'd1, FORMAT_Q16_16=8'd1;
    localparam logic [7:0] STATUS_OK=8'd0, STATUS_BAD_DIM=8'd1, STATUS_BAD_FORMAT=8'd2, STATUS_BAD_ADDRESS=8'd3;
    localparam logic [7:0] STATUS_BAD_STRIDE=8'd4, STATUS_BAD_GROUP=8'd5, STATUS_BAD_FLAGS=8'd6;
    localparam logic [7:0] STATUS_CORE_ERROR=8'd7, STATUS_WRITE_PROTOCOL=8'd8, STATUS_TIMEOUT=8'd9;
    // Team AXI wrapper extensions; original A/D status codes remain stable.
    localparam logic [7:0] STATUS_READ_ERROR=8'd10, STATUS_WRITE_ERROR=8'd11;
    localparam logic [7:0] STATUS_BAD_REGION=8'd12, STATUS_MEMORY_PROTOCOL=8'd13;
    typedef struct packed {
        logic [31:0] task_id;
        logic [15:0] m,n,k;
        logic [63:0] a_addr,w_addr,sx_addr,sw_addr,y_addr;
        logic [31:0] a_stride,w_stride,sx_stride,sw_stride,y_stride;
        logic [7:0] activation_format,weight_format,scale_format,output_format;
        logic [15:0] group_size,flags;
    } task_desc_t;
endpackage
