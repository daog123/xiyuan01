package llm_graph_pkg;
    localparam logic [7:0] OP_QKV_ATTENTION=6;
    // Single-token, single-head decode step; KV must already be configured.
    typedef struct packed {
        accelerator_pkg::bounded_task_t q_task,k_task,v_task;
        attention_pkg::attention_task_t attention;
        logic [15:0] token;
    } qkv_plan_t;
endpackage
