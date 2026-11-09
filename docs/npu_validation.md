# NPU 任务前端：实际验证结果

本报告由 scripts/report_npu.py 从已审计的 build/npu_summary.json 生成。仿真、综合与 OOC 使用本机 Vivado 2025.2 / Build 6299465，Windows PowerShell 5.1、Python 3.13.5；本轮执行日期为 2026-10-11。器件为 xcvu9p-flga2104-2L-e，仅作评估，板卡尚未确定。

## 已实现并实际验证

- 深度 4/3 的描述符 FIFO，包括非 2 次幂回绕、同拍入队/出队、满队列恢复。
- 有序 GEMM/GEMV 调度、任务 ID 回传（含重复 ID）、尺寸和不支持操作码的错误完成。
- 完成记录在背压下稳定，单一结果 RAM 在确认前不会被后续任务覆盖。
- 队列/活动/完成期间阻止输入写；描述符与写入同拍时描述符优先；确认与读取同拍时确认优先。
- 提交、计算、结果读暂停恢复；最后计算边沿之后暂停仍能捕获核心 done；暂停中允许完成确认。
- 活动任务带非空队列复位、持有完成记录带非空队列复位；不重新加载 A/B 的恢复计算。
- 固定种子 20261012：零输入、正负随机数、INT8 边界、矩形、全部尾块、跨 K tile、M=1、满容量连续任务。

## 自检汇总

| 阵列 / K tile / 队列深度 | 批量描述符 | 成功 / 拒绝 | 复位后成功任务 | INT32 输出比较 | 自检数量 | 同拍入队/出队 |
|---|---:|---:|---:|---:|---:|---:|
| 4×4 / 8 / 4 | 36 | 24 / 12 | 2 | 1191 | 59119 | 3 |
| 2×3 / 5 / 3 | 36 | 24 / 12 | 2 | 1191 | 88661 | 3 |

合计 **72 个按序批量描述符**（48 成功、24 拒绝），另有 **4 个复位后恢复任务**，共 **2382 个逐元素 INT32 比较**。为复位测试发出的被取消任务不计为成功完成。每配置批量向量含 1173 个输出，另加两个 GEMV 的 18 个输出；每个结果均与 Python 任意精度整数参考模型逐元素比较。

测试日志、PASS 标记、逐任务 CSV 与实际命令：

- [默认配置运行日志](../build/sim_npu_4x4_k8_q4/run.log)、[任务周期 CSV](../build/sim_npu_4x4_k8_q4/results.csv)、[实际命令](../build/sim_npu_4x4_k8_q4/commands.txt)。
- [2×3 / 深度 3 日志](../build/sim_npu_2x3_k5_q3/run.log)、[任务周期 CSV](../build/sim_npu_2x3_k5_q3/results.csv)。
- [参考向量清单](../build/npu_vectors/manifest.json)、[机器可读审计](../build/npu_summary.json)。

本轮也重新运行原默认矩阵核心的 13 个任务、480 个输出、8 个 PE 测试，以及独立双缓冲单元的 3 个 tile、18 个数据比较、53 项检查，均通过。其余原核心配置保留此前结果，核心 RTL 未修改。

RTL/TB 源码 SHA256 与执行前记录核对；正常仿真向量与参考生成器输出核对；逐任务核心活动周期由独立 Python 双缓冲周期模型核对。每次仿真有任务 100000 周期及全局 20 ms watchdog。首次测试中“同拍入队/出队”未被激励触发，自检正确失败；补充连续两拍提交后，两种配置各实际覆盖 3 次。

首轮完整工具调用中 Vivado 原生阶段均通过，但 PowerShell 把 Tcl 回显中的字面 ERROR: 误判，导致包装脚本退出 1。已将判定修正为行首真实 ERROR:，并让完整执行/只审计入口共用同一个检查函数；修正后实际通过 AuditOnly 重新检查全部报告。没有为日志匹配修复重复综合或布线。

### 故障注入

独立 *_negative 目录中篡改第一个 golden 输出，实际触发 NPU_CHECK_FAILED，PowerShell 退出码 **1**，无 PASS 标记。正常报告未受影响。脚本额外检查日志和 PASS 文本，避免 xsim 的 $fatal 返回原生 0 时误判成功。

[故障注入日志](../build/sim_npu_4x4_k8_q4_negative/run.log)、[实际退出码](../build/sim_npu_4x4_k8_q4_negative/observed_exit_code.txt)。

## 周期：核心与任务前端分开计量

| 任务形状 M×N×K | 4×4/K8 核心活动周期 | 2×3/K5 核心活动周期 |
|---|---:|---:|
| 4×4×8 | 61 | 156 |
| 7×9×13 | 494 | 672 |
| 1×9×17 | 308 | 215 |
| 16×16×32 | 2856 | 5896 |
| 3×7×6 | 102 | 210 |
| 2×5×7 | 112 | 72 |
| 1×1×1 | 26 | 15 |
| 5×3×11 | 158 | 153 |

满容量 16×16×32 在默认配置仍为 **2856 核心活动周期**。前三个批次的第一个 4×4×8 任务活动周期 61、总 busy 周期 64，差额为定向暂停的 3 拍。FIFO 等待、调度器取出/启动/完成捕获、主机装载与结果读取不计入这两个核心计数。

新增队列提升控制结构和可提前提交能力，未降低单任务 tile 装载周期；单一结果 RAM 仍需要主机读完并确认。当前不能据此宣称算子链吞吐、Decode token/s 或端到端加速比。16 MAC/拍是默认阵列计算阶段的理论峰值，100 MHz 是 10 ns 评估时钟。

## VU9P 综合与 OOC

| 指标 | 综合 npu_top | OOC npu_top |
|---|---:|---:|
| LUT | 1307 | 1282 |
| 逻辑 LUT | 1211 | 1186 |
| LUTRAM | 96 | 96 |
| FF | 872 | 872 |
| DSP48E2 | 16 | 16 |
| RAMB18 | 3 | 3 |
| RAMB36 | 0 | 0 |
| BRAM tile 等效 | 1.5 | 1.5 |
| URAM | 0 | 0 |
| latch | 0 | 综合源设计为 0 |
| WNS (ns) | +6.540 | +5.208 |
| WHS (ns) | +0.062 | +0.016 |
| TNS (ns) | +0.000 | +0.000 |
| THS (ns) | +0.000 | +0.000 |

[综合利用率](../build/synth_npu/utilization_synth.rpt)、[层级利用率](../build/synth_npu/utilization_hier_synth.rpt)、[RAM 实际推断](../build/synth_npu/ram_synth.rpt)、[原语计数](../build/synth_npu/primitive_counts.txt)、[综合时序](../build/synth_npu/timing_synth.rpt)、[综合/实现日志](../build/synth_npu/synth_npu.log)、[实际工具命令](../build/synth_npu/commands.txt)。

描述符 FIFO 采用 4×72 bit 寄存器；RTL 组件报告列出 4 个 72 bit 寄存器。层级报告中前端自身为 429 FF（包含 FIFO、活动字段、完成周期和控制）；引擎为 443 FF。存储报告仅有 A/B/P 三个 RAMB18，A cache 与两组 B tile 使用 12 个 RAM32M16、96 LUTRAM；队列未消耗额外 BRAM/LUTRAM。乘法/累加实际映射为 16 DSP48E2，DSP MREG=0、PREG=1；额外前端不新增乘法器。

### 告警与约束范围

- 综合有 6 条 Synth 8-3917：completion_status[7:2] 恒为 0。接口预留 8 位状态，当前只用 0..3；这是可解释的常量输出，无 latch。未屏蔽这些告警。
- 无综合 Critical Warning 或 Error；同步 RAM 输出可选寄存器不合并的 INFO 保持现有读时序合同。
- 10 ns 时钟已约束，no_clock=0、unconstrained_internal_endpoints=0；输入/输出延迟未设置，不能作为板级签核。
- OOC 完成 opt/place/route：2175 个可布线网络，2175 个 fully routed，0 个 routing errors，1 个 explicit gap。最终 DRC 的 Design State 为 Partially Routed，需保留该边界。
- OOC 无 setup/hold 失败端点，内部 WNS +5.208 ns、WHS +0.016 ns；这仅是该器件/虚拟时钟源下的内部实现结果。

[OOC 时序](../build/synth_npu/timing_ooc.rpt)、[布线状态](../build/synth_npu/route_status_ooc.rpt)、[最终 DRC](../build/synth_npu/drc_ooc.rpt)。最终 DRC 文件的检查项如下，不能只看日志中的警告数：

- DPIP-2 / Warning / 16 checks：Input pipelining
- RTSTAT-10 / Warning / 1 checks：No routable loads

内部 hold 裕量较小，确认真实时钟、板卡和父级连接后必须重新实现与签核。

DPIP-2 指出 DSP B 输入未使用 DSP 内部输入寄存器，是后续流水线优化项；修改时必须同步对齐 A/B、enable 和 tile 收尾。RTSTAT-10、HD.PARTPIN_LOCS 和 DRC 23-814 与 OOC 外部边界有关，未被屏蔽。虚拟 HD.CLK_SRC=BUFGCE_X0Y0 为评估假设，无板级 I/O、管脚约束、真实时钟源或 bitstream。

## 已实现但未验证 / 未来计划

- 状态 3 的核心错误转发已写入 RTL，但在前端预检查之后正常任务不可达，未做强制故障注入。
- 除深度 3/4 与两种阵列之外的前端参数组合未验证；INT32 矩阵自然溢出未在容量 K≤32 内发生。PE 的种子溢出/下溢检查仍由原核心测试覆盖。
- 任务独立 A/B/C 地址、行步长、B 转置、多个结果槽、量化后处理、向量归约、片上 FFN/Attention 链、外部 DDR/HBM、DMA/PCIe 均未实现。
- 没有板上性能、功耗或模型精度测量。优先扩展张量地址/依赖合同与 B 供数带宽，见 [next_steps.md](next_steps.md)。

## Windows 复现

~~~powershell
Set-Location E:\speed-up
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_npu.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_npu.ps1 -Synthesize -Implement
# 预期失败退出 1，仅影响独立 negative 目录
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_npu.ps1 -SingleConfig -CorruptExpected
python .\scripts\summarize_npu.py
python .\scripts\report_npu.py
~~~

源码、脚本和约束放在各自目录；全部向量、日志、CSV、checkpoint 和报告在 build。未修改全局环境变量或执行策略，也未安装依赖。
