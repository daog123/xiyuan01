# ABI v5：自动Q/K/V、KV追加与Attention

主顶层改为 `llm_graph_top`，内部复用已有 `llm_top` 引擎。原opcode0..5在握手当拍直接转发，描述符由已有引擎锁存；新增opcode6锁存整份 `llm_graph_pkg::qkv_plan_t`。公开入口仍是一个活动任务、一套AXI所有权、一条根完成记录。

## 请求与执行顺序

新增 `OP_QKV_ATTENTION=6`。计划包含 `q_task`、`k_task`、`v_task` 三份 bounded_task、`attention` 描述符和 `token`。根ID为 `attention.task_id`。Q/K/V均为M1、N=dimension、相同K的投影，子任务ID互异；只支持一个head和一个新token，KV必须事先配置。

```text
整图预检
 → K投影 → 全部写确认 → K按完整group动态量化并缓存
 → V投影 → 全部写确认 → V按完整group动态量化并缓存
 → KV_APPEND(token, count=1)：K、V、SK、SV → 全部B确认及长度提交
 → 既有Q_ATTENTION：Q投影 → 写确认 → Q动态量化 → Attention → Y写确认
 → 根完成
```

共享原矩阵核；K/V顺序复用同一个Q16.16量化器。缓存保存两条INT8向量和group scales，按KV已有little-endian协议发出，无须主机提供append或Q字节流。原有KV配置、手工append和普通任务继续转发。

`attention.q_source=2`，`q_addr=q_task.desc.y_addr`，`q_bytes=q_task.y_bytes`；scale地址/容量为0。`attention.tokens=token+1`；layer/head/dimension须匹配配置，token不得超出容量。实际token是否等于该head的已提交长度，由权威KV管理器检查。

## 整图预检

在任何投影访存前，先检查三份投影的全部格式、地址、stride、容量和范围，再检查Q/K/V临时输出与最终Y互不重叠、均不覆盖任一投影的活跃输入或持久KV分配区。只读输入可以共享。检查覆盖完整分配区，包含stride间隙，采用保守的生命周期约束。

三份投影顺序复用一个有界任务检查器；别名检查顺序遍历，减少检查逻辑复制。只有先证明M=1、dimension≤64、K≤4096，才把检查器的几何操作数缩窄。负例包括K8192、N129、高位地址溢出、非法flags及跨投影别名，均要求零AXI副作用。

## 数值合同

Q/K/V矩阵及Attention整数定义不变。K/V量化复用 `attention_q_dma` 的Q16.16源模式及原 `requant_dynamic/group`：

```text
scale = clamp(ceil(group_absmax / 2032), 1, 65535)
q = saturate_int8(round_away(value_Q16.16 / (16*scale)))
```

完整group确定scale后输出，尾group用真实长度，半数远离零；零group scale=1。V不进行额外非线性变换。当前没有RoPE，因此这是固定数值合同下的合成Attention链，尚不是完整真实模型层。

## 完成阶段与恢复

新增根图完成时保留stage，完成反压期间ID/status/stage均稳定：

| stage | 含义 |
|---|---|
| 0 | 预检失败 |
| 8 / 9 | K投影 / K量化 |
| 10 / 11 | V投影 / V量化 |
| 12 | KV追加及提交确认 |
| 13 | KV已提交，进入Q投影/Attention |

这不是整图原子事务。stage8..12失败时不会启动Q；投影临时区或未提交KV字节可能部分改变，KV追加失败不增加已提交长度。stage13失败时本次KV追加已成功，不能直接重放同一个完整追加请求。可在解除错误原因后使用既有 `Q_ATTENTION` 只重算Q/Attention。

软件的 `Completion` 新增可选stage；transport须在completion有效、写ACK之前采样task_id/status/elapsed_cycles/stage，再确认完成。`TaskExecutionError`保留 `.completion`。`QKVAttentionPlan.kv_committed(event)` 返回本次执行是否越过提交确认点；无stage的失败记录返回None。False只表示本次没有越过该确认点，不代表缓存里不存在同一token。

`plan.resume_query()` 返回 `ProjectedAttentionPlan`，可构造 `SystemJob(Opcode.Q_ATTENTION, plan.resume_query())`。库不自动重试或重放append。复位须与外部fabric同步，会清空配置和已提交长度；重新配置后再提交。

## FFN word读取

`ffn_dma`的gate/up输入为已确认写回的对齐Q16.16。现在每个值用一次4字节读取替代四次字节读取；保留原输入顺序、SiLU/SwiGLU、动态量化、qx/sx写确认和down发射条件。每个中间元素减少6个读取事务，有效字节仍为8字节；写入和数值合同不变。AXI仍为单拍、单outstanding。

## 复现

```powershell
python scripts/project.py test
python scripts/benchmark_round4.py
python experiments/round4_qkv_large/run_large.py
python scripts/round3_checks.py
python scripts/round3_storage_checks.py
python scripts/project.py implement
python scripts/project.py status
```

主系统测试现有20配置；新增4种整链配置覆盖group32/3/1及32位地址，维度1/9/64、连续token与多head、clipping、提交前后错误、仅Q恢复和与fabric一起复位。独立大例实测M1/N64/K4096的两步连续追加/查询，每步检查完整1MiB镜像。性能实验只切换FFN DMA，12组FFN及12组LINEAR对照均检查完整外存。

仍缺O投影、RoPE、RMSNorm/残差、多head整体调度、完整Block与模型运行时；尚未接入板级DDR/PCIe。当前最大上下文16、dimension64及既有FFN容量限制仍有效。详细数字与资源见system_round4.md。
