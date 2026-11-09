# ABI v3：统一系统架构

> 当前主顶层为llm_graph_top / ABI v5，内部复用llm_top。第四轮阶段与恢复合同见[qkv_attention.md](qkv_attention.md)；下文旧顶层描述用于说明内部引擎与历史结构。

当前主顶层为 `rtl/llm_top.sv`，硬件参数与软件入口由 `config/system_profile.json` 描述，综合与仿真共用 `config/system_sources.txt`。`scripts/project.py` 负责生成参考数据、编译、仿真、实现与当前源码证据校验。

## 公共任务与总线所有权

主机以 `job_valid/job_ready` 提交一个完整任务。顶层锁存 opcode 和相应描述符，在 ISSUE 阶段交给子系统；一个任务完成并由主机接收完成记录后，才接受下一个任务。所有共享 AXI 的读写响应都返回当前所有者，子系统没有独立接收新任务的旁路。

| opcode | 名称 | 描述符 | 成功边界 |
|---:|---|---|---|
| 0 | LINEAR | `bounded_task_t` | 全部 Q16.16 结果收到 AXI B response |
| 1 | FFN | `ffn_plan_t` | gate、up、SwiGLU/requant、down 顺序完成，最终 down 写确认 |
| 2 | ATTENTION | `attention_task_t` | KV 前缀读取完毕，QK/Softmax/AV 完成，全部 Y 写确认 |
| 3 | KV_CONFIG | `kv_config_t` | 布局、容量、地址与格式校验完成 |
| 4 | KV_COMMAND | `kv_command_t` | APPEND 全部写确认后提交长度；READ 排空响应；CLEAR 更新元数据 |

完成记录统一为 `completion_valid/ready`、32 位 task ID、8 位 status。成功时 `result_available=1`。完成反压期间，ID/status 保持稳定，系统继续持有任务所有权。状态 0–9 沿用 A/D 定义，10 为读错误，11 为写错误，12 为区域/容量/计划非法，13 为存储或流协议错误。KV 配置和管理命令的成功表示对应事务完成。

```mermaid
flowchart TD
    H[版本化任务与流输入] --> R[llm_top：单活动任务与完成路由]
    R --> F[accelerator_top：LINEAR / FFN]
    R --> A[attention_kv_top：KV / Attention]
    F --> G[gate 投影与写确认]
    G --> U[up 投影与写确认]
    U --> D[ffn_dma：读取 gate/up]
    D --> V[原 ffn_bridge：SwiGLU 与动态量化]
    V --> Q[qx/sx 写回与写确认]
    Q --> W[down 投影与写确认]
    A --> QD[可选：Q 与 scale 内存预取并排空响应]
    QD --> K[事务式 KV Cache 与提交长度]
    K --> C[QK → Softmax → AV]
    C --> Y[Q16.16 Y 写回与写确认]
    F --> X[共享 AXI：当前任务独占]
    A --> X
    W --> E[统一完成记录]
    Y --> E
```

## FFN 外存闭环

`ffn_plan_t` 包含主任务 ID 和 gate/up/down 三个有独立容量边界的线性描述符。三个子任务 ID 必须不同；gate/up 的 M/N/K 一致，down.M=gate.M，down.K=gate.N。当前三次投影共用一份硬件 GROUP_SIZE。

所有子任务在第一次外部访问之前完成校验。gate.Y、up.Y、down.A、down.sx、down.Y 五个写入分配区互不重叠，也不允许覆盖任何活跃的原始输入、权重或 scale。当前采用保守的完整分配区检查，不进行 scratch 别名复用。

同一个 W4A8 核心顺序执行 gate/up/down。gate 和 up 的 Q16.16 结果真实写入外存；两个投影均收到写确认后，`ffn_dma` 按 row/column 读取并组合 signed32 元素，送入原 C/E `ffn_bridge`。SwiGLU 和 dynamic requant 的算术、舍入、饱和及 LUT 保留原实现。

量化输出按 down.A 的 byte stride 写回 qx，每个 row/group 的 UQ4.12 sx 以 little-endian 两字节写入 down.sx。只有 `M*H` 个激活字节和 `2*M*ceil(H/GROUP_SIZE)` 个 scale 字节全部写确认，才进入 down。桥内部 done、最后一个输出握手和 AXI 写确认是不同事件。

默认 MAX_H=64、CAPACITY=512；M*H 超过桥容量会整计划拒绝。当前顺序执行，不包含 gate/up 并行、输出 FIFO 或计算/搬运重叠。

## KV 与有界 Attention

KV 保留独立 layer/head 的已提交长度，K、V、SK、SV 四个分配区采用可配置 byte stride。APPEND 必须从当前已提交尾部开始；一个批次全部字节收到成功写确认后，才提交新长度。读失败和写失败返回非零状态，未确认或失败的部分数据不会扩大有效长度。

Attention 接收一个量化 Q 向量：每个维度一个 signed INT8 字节、该 group 的 UQ4.12 scale，以及最后维度的 q_last。组内重复的 scale 必须一致。query 指定 layer/head、dimension、可见 tokens 前缀、score_scale 和 Y 分配区。

计算核心向 KV 发出四个真实 READ 命令，依次读取可见前缀的 K、V、SK、SV，并等待每个命令的 fence。然后执行动态 QK 点积、稳定 Softmax 和 AV。分数保留 64 位，指数查表、归一化逐位除法和乘加使用分阶段寄存。最终 Q16.16 Y 经过 AXI 写回且全部收到 B response 后才完成。

默认最大维度 64、最大可见前缀 16 个 token。当前为单 query、指定 layer/head 的顺序 Attention。Prefill 可按位置提交 query，令 tokens=position+1；Decode 可先 APPEND 新 KV，再对已提交前缀提交 query。tokens 不得超过已提交长度。任意稀疏 mask、滑窗/分页、GQA 自动映射以及跨 query 并行尚未实现。

Q 输入支持两种来源。`q_source=0` 使用公开流，Q 内存字段必须全零；`q_source=1` 由 `attention_q_dma` 读取已量化 Q 和每组一个 scale。Q 为 dimension 个紧凑 signed INT8 字节，scale 为 `ceil(dimension/GROUP_SIZE)` 个 little-endian UQ4.12；分配区容量、65 位范围、Q/scale 互斥和与 Y 的重叠都在访问前检查。Q 预取阶段独占 AR/R，读响应全部排空才移交给 KV；错误会阻止 Attention 启动。Q 本地流遇到反压保持 data/scale/last，内存模式忽略主机 Q 流。

Q/K/V/O 投影仍可作为 LINEAR 任务提交。当前内存 Q 接入只消费已经量化的 Q，尚未连接投影 Q16.16 结果到 Q 的自动量化、RoPE、完整 Q/K/V/O 图和输出重定量化，因此仍不是完整 Transformer block。

## 地址与错误处理

主通路 ADDR_WIDTH=64；低层读、写、packet、区域校验以及 KV 都支持 32/64 位配置。旧 `w4a8_team_top`、bridge 和 KV 模块仍默认 32 位，兼容原测试和接口。allocation capacity/stride 为 uint32，地址为 uint64；区域加法与重叠比较使用 65 位，越过 2^64 会拒绝，不会回绕或静默截断。

一个阶段出错后，不再启动后续阶段。已发出的 AXI 事务先排空，才允许报告失败和移交总线。系统不在外部 fabric 永久失去响应时伪造写确认；测试中的超时探针负责使验证失败，不能替代实际总线取消协议。系统复位必须同时复位/清空外部 fabric，再复用分配区。

## 模块归属与兼容入口

| 层级 | 文件 | 用途 |
|---|---|---|
| 公共 ABI | task_desc_pkg / w4a8_memory_pkg / accelerator_pkg / attention_pkg / kv_cache_pkg | 主机、边界与计划类型 |
| 主入口 | llm_top | 五类任务、总线所有权和完成路由 |
| 线性/FFN | accelerator_top / ffn_dma / w4a8_team_top | 投影调度、真实中间存储与 fence |
| Attention/KV | attention_kv_top / attention_q_dma / attention_compute / kv_cache | KV 事务、动态 QK/AV 与近似 Softmax |
| C/E 算术 | w4a8_wave、rtl/vector 中的原模块 | 保留的 W4A8、SiLU、动态 requant |
| 软件 | software/system.py | ABI v3 的任务、计划、校验与传输无关运行时 |
| 兼容入口 | 原 task_controller / w4a8_system_top / 各阶段脚本 | 原三方接口和独立模块回归 |

## 第二轮计算核内部结构

主系统默认TILE_K32、group32，4×4阵列。M1在对齐条件满足时把PE行用于K分片，列用于输出N；组内整数归约后进入既有scale合同。其他任务使用普通矩阵路径，有效行列决定波前排空长度。部分和及64位Y按列分bank，一拍快照一行，两个独立后处理lane共享背压和组完成边界。

PACKED_MAC是默认关闭的广播研究路径，两个INT4权重共享一个INT8激活乘法，低位借位修正后分别32位累加；不改变group scale或最终舍入规则。研究核资源和时序不替代主系统或板级结果，详见compute_round2.md。

## ABI v4自动Q链和连续读取

llm_top在Q_ATTENTION任务内部切换LINEAR和Attention所有权，仅在投影写确认后发出内存Q请求，使用Attention ID返回根完成。Q16.16在attention_q_dma内复用动态group量化；共享原矩阵核。w4a8_memory_packet按合法连续字节上限发起1/2/4/8字节读取并一次填充多个packet槽位；其他单字节消费者继续使用原读取接口。详细阶段、边界和复现见[projected_attention.md](projected_attention.md)。

## 第五轮小行数M/K映射

MULTIROW_FOLD默认开启，按当前M块有效行数选择2次幂K并行，激活bank与子树归约保持逻辑行/分组scale对应。支持M2/M4及尾块；不满足tile/group/字宽约束时回到原路径。详见compute_round5.md。

## 第六轮有界激活burst

矩阵packet只为当前有效激活行提供连续范围；最多4拍/32字节、单outstanding、四槽预留和整burst错误检查，按4KiB和有效字节边界截断。权重离散行及向量/Q/KV读取仍保留各自旧路径。数值、B确认、错误排空和stage13恢复合同不变。完整限制与验证见[第六轮报告](system_round6.md)。

## 第七轮权重窗口与sx复用

矩阵packet内部使用两条16字节权重行窗口，按真实连续地址读取后维持原packet顺序；sx以M起点、ml和group为上下文，缓存前128组，任务间或abort清除有效位。默认4行的数据为1KiB分布式RAM；超容量组走外存。单outstanding、写确认和错误排空保持不变。详见[第七轮报告](system_round7.md)。
