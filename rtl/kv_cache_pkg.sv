package kv_cache_pkg;
    localparam logic [15:0] KV_INT8_UQ412_V1=1;
    localparam logic [1:0] KV_K=0,KV_V=1,KV_SK=2,KV_SV=3;
    localparam logic [1:0] KV_APPEND=0,KV_READ=1,KV_CLEAR=2;
    localparam logic [3:0] KV_OK=0,KV_BAD_CONFIG=1,KV_BAD_COMMAND=2,
        KV_WRITE_ERROR=3,KV_READ_ERROR=4,KV_STREAM_ERROR=5;
    typedef struct packed {
        logic [31:0] config_id;
        logic [15:0] layers,heads,capacity,dimension,group_size,format_id;
        logic [3:0][63:0] base;
        logic [3:0][31:0] bytes,token_stride,head_stride,layer_stride;
    } kv_config_t;
    typedef struct packed {
        logic [31:0] task_id;
        logic [1:0] operation,plane;
        logic [15:0] layer,head,token,count,offset,length;
    } kv_command_t;
    function automatic logic [31:0] kv_plane_bytes(input kv_config_t cfg,input logic [1:0] plane,input integer group_size);
        return (plane<2)?32'(cfg.dimension):2*((32'(cfg.dimension)+group_size-1)/group_size);
    endfunction
endpackage
