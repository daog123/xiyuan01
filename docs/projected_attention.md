# ABI v4：Q投影、动态量化、Attention

当前实现一个单query、单head、已有已提交KV的自动链路。它复用LINEAR核和Attention核，不增加第二套矩阵阵列；不含K/V投影、KV自动append、RoPE或O投影，不能称为完整Transformer层。

## 一次提交

`OP_Q_ATTENTION=5` 同时锁存现有 `linear_task` 和 `attention_task`。根任务ID使用 `attention_task.task_id`，投影的子任务ID只在内部使用。软件封装为 `ProjectedAttentionPlan(projection, attention)`，通过一个 `SystemJob(Opcode.Q_ATTENTION, plan)` 提交。

执行顺序：图形状/分配区别名检查 → LINEAR Q投影 → 全部Q16.16写确认 → 读取Q16.16 → 完整group动态量化 → Attention读取已提交KV → 输出写确认 → 一条根完成记录。中间投影成功不会作为主机completion暴露；完成记录反压期间保留根ID和状态，不接收下一个任务。

投影须M=1、N=dimension；`attention.q_source=2`，`q_addr=projection.desc.y_addr`，`q_bytes=projection.y_bytes`。`q_addr`按4字节对齐、容量至少4×dimension；`qs_addr=qs_bytes=0`，scale在片上生成。Attention输出不得与Q临时区、投影输入或持久KV分配区重叠；Q投影输出不得与KV重叠。普通LINEAR描述符检查仍执行。32位地址模式使用65位端点检查，禁止高位截断后访问。

KV配置及append是单独任务，须事先成功；layer/head/dimension须匹配现有配置。提交的tokens是否超过已提交长度由Attention阶段检查。因此本链路不是原子事务：投影成功后若KV前缀检查或后续存储失败，Q临时区可能已更新，Y也可能部分写入；失败时 `result_available=0`，不承诺回滚。新增测试检查错误阻止后续阶段、已有外部事务排空及后续任务恢复。

## Q输入兼容

描述符字段布局保持不变，扩展取值：

| q_source | 输入 |
|---|---|
| 0 | 主机INT8流，内存Q/scale字段全零 |
| 1 | 有界连续INT8 Q及little-endian UQ4.12 group scales |
| 2 | 有界连续little-endian signed32 Q16.16，片上动态量化，scale字段全零 |

`OP_ATTENTION`也可直接使用source2，以验证已经存在于内存的Q16.16结果。source2及自动链路都不消耗主机Q流。

## 数值合同

复用原 `requant_dynamic`/`requant_group`，没有另写一种近似量化。对每个完整group（尾group可短）：

```text
absmax = max(abs(signed32 Q16.16))       # abs(INT32_MIN)保留33位中间量
scale  = clamp(ceil(absmax / 2032), 1, 65535)
q      = saturate_int8(round_away(Q16.16 / (16*scale)))
```

round_away为最近舍入、恰好半数远离零。零group的scale为1；scale上限或INT8饱和沿用原合同。全部group量化、缓存并排空读事务后才发出Q流；后续QK/Softmax/AV的定义不变。测试用独立整数模型逐项比较Q、scale、Q投影输出、Attention输出以及完整外存镜像，覆盖零、随机、clipped数据和dimension1/9/64。

## 有界连续读取

`w4a8_axi_read_chunk`一次命令携带1..8字节的合法连续上限，选择满足地址自然对齐且不超过上限的最大1/2/4/8字节AXI单拍。返回实际字节数和右对齐数据。packet按W行、A行或scale片段给出连续上限，跨行、跨padding或打包孔洞必须分开请求。Q16.16使用对齐4字节读取，INT8 Q/scale也使用该读取器。

仍为ARLEN=0、单outstanding；这不是AXI burst或多请求并行。保持AR/响应反压缓存、错误ID/RRESP检查、异常多拍排空以及全局复位与fabric同步恢复的合同。读取有用字节计数按 `1<<ARSIZE` 累加，总线占用按每个R beat的8字节计数，二者不再等同。

## 复现

```powershell
python scripts/project.py test
python scripts/round3_checks.py
python scripts/round3_storage_checks.py
python scripts/benchmark_round3.py
python experiments/round3_memory/run_large.py
python scripts/project.py implement
python scripts/project.py status
```

`project.py test`包含16配置（既有12配置及4种新链路配置）。协议/独立存储检查、配对性能实验另外保留日志与source_sha256。核心接口、主系统存储路径及板级DDR/PCIe属于不同计时边界；本轮结果不替代板测或模型吞吐。
