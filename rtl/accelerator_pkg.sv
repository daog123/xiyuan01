// Versioned common ABI: host descriptors plus explicit allocation bounds.
package accelerator_pkg;
    localparam logic [7:0] ABI_VERSION=5,OP_LINEAR=0,OP_FFN=1;
    localparam logic [7:0] OP_ATTENTION=2,OP_KV_CONFIG=3,OP_KV_COMMAND=4,OP_Q_ATTENTION=5;
    typedef struct packed {
        task_desc_pkg::task_desc_t desc;
        logic [31:0] a_bytes,w_bytes,sx_bytes,sw_bytes,y_bytes;
    } bounded_task_t;
    typedef struct packed {
        logic [31:0] task_id;
        bounded_task_t gate_task,up_task,down_task;
    } ffn_plan_t;
endpackage
