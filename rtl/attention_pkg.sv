package attention_pkg;
    typedef struct packed {
        logic [31:0] task_id;
        logic [15:0] layer,head,tokens,dimension,score_scale;
        logic [63:0] y_addr;
        logic [31:0] y_bytes;
        // ABI v4: 0 keeps the host Q stream, 1 loads contiguous INT8 Q and
        // little-endian UQ4.12 scales. Source 2 reads aligned Q16.16 values
        // and dynamically quantizes complete groups on chip; qs fields are zero.
        logic [7:0] q_source;
        logic [63:0] q_addr,qs_addr;
        logic [31:0] q_bytes,qs_bytes;
    } attention_task_t;
endpackage
