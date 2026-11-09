// Finite layout and overflow validation. All strides and addresses are bytes.
module kv_cache_address #(
    parameter integer ADDR_WIDTH=32,GROUP_SIZE=32,MAX_LAYERS=4,MAX_HEADS=8,MAX_TOKENS=4096,MAX_DIM=128
)(
    input kv_cache_pkg::kv_config_t cfg,
    input logic [1:0] plane,input logic [15:0] layer,head,token,offset,
    output logic config_legal,access_legal,output logic [ADDR_WIDTH-1:0] address
);
    import kv_cache_pkg::*;
    logic [3:0][63:0] widths,head_extents,layer_extents,total_extents;
    logic [64:0] wide_address;
    always_comb begin
        config_legal=cfg.layers>0 && cfg.layers<=MAX_LAYERS && cfg.heads>0 && cfg.heads<=MAX_HEADS &&
            cfg.capacity>0 && cfg.capacity<=MAX_TOKENS && cfg.dimension>0 && cfg.dimension<=MAX_DIM &&
            cfg.group_size==GROUP_SIZE && cfg.format_id==KV_INT8_UQ412_V1;
        for(integer p=0;p<4;p++) begin
            widths[p]=64'(kv_plane_bytes(cfg,2'(p),GROUP_SIZE));
            head_extents[p]=(64'(cfg.capacity)-1)*64'(cfg.token_stride[p])+widths[p];
            layer_extents[p]=(64'(cfg.heads)-1)*64'(cfg.head_stride[p])+head_extents[p];
            total_extents[p]=(64'(cfg.layers)-1)*64'(cfg.layer_stride[p])+layer_extents[p];
            if(cfg.bytes[p]==0 || 64'(cfg.token_stride[p])<widths[p] ||
                64'(cfg.head_stride[p])<head_extents[p] || 64'(cfg.layer_stride[p])<layer_extents[p] ||
                total_extents[p]>64'(cfg.bytes[p]) || 65'(cfg.base[p])+65'(cfg.bytes[p])>(65'd1<<ADDR_WIDTH))
                config_legal=0;
            if(p>=2 && (cfg.base[p][0] || cfg.token_stride[p][0] || cfg.head_stride[p][0] || cfg.layer_stride[p][0])) config_legal=0;
            for(integer q=0;q<p;q++) if(65'(cfg.base[p])<65'(cfg.base[q])+65'(cfg.bytes[q]) &&
                65'(cfg.base[q])<65'(cfg.base[p])+65'(cfg.bytes[p])) config_legal=0;
        end
        wide_address=65'(cfg.base[plane])+64'(layer)*64'(cfg.layer_stride[plane])+
            64'(head)*64'(cfg.head_stride[plane])+64'(token)*64'(cfg.token_stride[plane])+64'(offset);
        address=wide_address[ADDR_WIDTH-1:0];
        access_legal=config_legal && layer<cfg.layers && head<cfg.heads && token<cfg.capacity &&
            64'(offset)<widths[plane] && wide_address<(65'd1<<ADDR_WIDTH) &&
            wide_address>=65'(cfg.base[plane]) && wide_address<65'(cfg.base[plane])+65'(cfg.bytes[plane]);
    end
endmodule
