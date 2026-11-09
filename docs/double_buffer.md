# B tile 双缓冲：实现与实际验证

本轮默认 OPTIMIZED=1、DOUBLE_BUFFER=1、B_LOAD_GAP=0，4×4 阵列、TILE_K=8，容量 M/N≤16、K≤32。评估 part 为 xcvu9p-flga2104-2L-e，板卡未确认，时钟目标 100 MHz。实际使用 Windows PowerShell 5.1、Vivado 2025.2 Build 6299465、Python 3.13.5 和 NumPy 2.2.6。

## 已实现

- rtl/b_pingpong.sv：两个 B tile 银行组、独立同步装载流水、生产者/消费者游标及 EMPTY/FILLING/READY/COMPUTING 归属。
- B 预取在 CLEAR 后启动，与 A cache 装载并发；计算一个银行组时装载另一个。A 仍为完整行 cache，没有新增 A 双缓冲。
- 每组具有 K 起点标签；READY 握手和同步银行读取都实际检查标签与消费 kt 一致。源 B BRAM 仍只有一个同步读端口。
- WAIT_B 允许消费者等待未完成填充；仅 ADVANCE 释放当前组。归属由完成写入、take 和 release 决定，不依赖固定计时猜测数据有效。
- 暂停冻结生产者和消费者；复位清归属与游标，RAM 内容不清，重新开始时不得消费旧 READY。
- 保留 DOUBLE_BUFFER=0 的上一轮单缓冲，以及 OPTIMIZED=0 的原始模式。

架构、同步时序与精确事件递推见 [architecture.md](architecture.md)。默认 B tile 容量由 32 增至 64 字节，A cache 为 128 字节。未接 DDR/AXI/DMA，装载间隔参数不等同于真实内存响应延迟。

## 实际仿真

独立 tb_b_pingpong 单元测试另通过 3 个 tile、18 个数据比较、53 项检查，直接验证错误 K 标签拒绝 take/读取、两组占用停止源读取、尾列填零和并发暂停。

八组配置均通过，每组 13 个矩阵、480 个输出逐元素比较，共 **104 个完整任务、3840 个结果比较**，另有每组 8 个 PE 数值与溢出用例。种子固定为 20261011，Python/NumPy 参考逐元素一致。

| 阵列 | K tile | OPT | DB | 装载间隔 G | 输出比较 | 检查数 |
|---|---:|---:|---:|---:|---:|---:|
| 4×4 | 8 | 1 | 1 | 0 | 480 | 57380 |
| 2×3 | 5 | 1 | 1 | 0 | 480 | 88295 |
| 2×3 | 5 | 1 | 1 | 3 | 480 | 155331 |
| 2×1 | 3 | 1 | 1 | 0 | 480 | 117741 |
| 4×4 | 8 | 1 | 0 | 0 | 480 | 47970 |
| 2×3 | 5 | 1 | 0 | 0 | 480 | 69381 |
| 4×4 | 8 | 0 | 0 | 0 | 480 | 87380 |
| 2×3 | 5 | 0 | 0 | 0 | 480 | 133595 |

覆盖原有零矩阵、混合符号、INT8 极值、随机/矩形、跨 K、M/N/K 尾块、GEMV、连续任务、复位与背压。双缓冲额外检查：

- 写入组必须 FILLING，不能覆盖 COMPUTING；同步读取组必须 COMPUTING 且 K 标签匹配。
- 每任务 take/release 次数等于输出块数×K tile 数，A/B/P 有效访问次数与单缓冲一致。
- 下一组提前 READY、两个组占用而装载器等待、消费者等待供数、K 尾块和交替复用均由数值/周期及归属检查覆盖。
- GAP=3 的 2×3 配置独立减慢装载器，消费者照常运行；2×1/K3 配置让装载快于计算，覆盖不同相对速度。
- 在装载器与 RUN 同时活动时暂停与复位，然后恢复/重新启动；归属复位为 EMPTY，逐元素结果正确。
- 全局 20 ms 与每任务 100000 周期 watchdog；脚本要求 ALL_TESTS_PASS 且不存在 Fatal/MISMATCH/CHECK_FAILED。
- 错误期望值注入实际触发 CHECK_FAILED，PowerShell 退出码为 1。

## 同一向量的活动周期

下表不含主机装载、读回和 pause。单缓冲列来自本轮同一 RTL 的 DOUBLE_BUFFER=0 回归，不是理论估计。

| 用例 | 阵列 | 单缓冲 | 双缓冲 | 周期比 | 未就绪等待 | RUN/写重叠 |
|---|---|---:|---:|---:|---:|---:|
| zero | 4×4 | 93 | 61 | 1.525 | 0 | 0 |
| signed | 4×4 | 57 | 41 | 1.390 | 0 | 0 |
| int8_bounds | 4×4 | 93 | 61 | 1.525 | 0 | 0 |
| random_rect | 4×4 | 125 | 102 | 1.225 | 25 | 0 |
| cross_k | 4×4 | 198 | 124 | 1.597 | 2 | 8 |
| all_tails | 4×4 | 634 | 494 | 1.283 | 172 | 32 |
| gemv | 4×4 | 402 | 308 | 1.305 | 110 | 25 |
| consecutive_nonzero | 4×4 | 246 | 158 | 1.557 | 0 | 0 |
| consecutive_zero | 4×4 | 246 | 158 | 1.557 | 0 | 0 |
| minimal | 4×4 | 30 | 26 | 1.154 | 0 | 0 |
| full_capacity | 4×4 | 3540 | 2856 | 1.239 | 1364 | 352 |
| tall_rect | 4×4 | 420 | 276 | 1.522 | 0 | 0 |
| resume_after_reset | 4×4 | 139 | 112 | 1.241 | 29 | 0 |
| zero | 2×3 | 214 | 156 | 1.372 | 38 | 20 |
| signed | 2×3 | 122 | 108 | 1.130 | 34 | 0 |
| int8_bounds | 2×3 | 214 | 156 | 1.372 | 38 | 20 |
| random_rect | 2×3 | 248 | 210 | 1.181 | 70 | 12 |
| cross_k | 2×3 | 458 | 330 | 1.388 | 100 | 50 |
| all_tails | 2×3 | 924 | 672 | 1.375 | 216 | 112 |
| gemv | 2×3 | 296 | 215 | 1.377 | 72 | 40 |
| consecutive_nonzero | 2×3 | 249 | 153 | 1.627 | 3 | 21 |
| consecutive_zero | 2×3 | 249 | 153 | 1.627 | 3 | 21 |
| minimal | 2×3 | 17 | 15 | 1.133 | 1 | 0 |
| full_capacity | 2×3 | 8008 | 5896 | 1.358 | 2496 | 1400 |
| tall_rect | 2×3 | 476 | 301 | 1.581 | 14 | 35 |
| resume_after_reset | 2×3 | 97 | 72 | 1.347 | 17 | 10 |

默认满容量 16×16×32：3540→2856 活动周期，减少 19.32%，周期比 1.239；相对第一版 9872 周期为 3.457。A/B/P 有效次数仍为 512/2048/256。RUN=512，RUN/写重叠=352，WAIT_B 未就绪=1364；352 只统计 B tile WRITE 与 RUN 同拍，不含源请求拍和 A 装载重叠。

该用例明确注入 382 个全局 pause 周期，因此 elapsed=3238；活动周期比较仍使用 2856。假设 100 MHz 时活动 busy 时间为 28.56 us，这是 RTL 周期换算，没有板上计时。阵列理论峰值仍为 16 MAC/周期；实测任务平均有效 MAC 为 8192/2856=2.868 MAC/活动周期。

标量 B 源带宽仍是瓶颈：一个满 tile 填充要 33 拍，RUN 仅 8 拍。双缓冲没有改变 B 读取总字节数，也不能在任意任务上保证同一加速比；同步 take 额外边界拍可能使部分很小任务的收益降低。

## 实际综合

| 项目 | 上一轮单缓冲综合 | 当前双缓冲综合 |
|---|---:|---:|
| LUT | 954.0 | 1149.0 |
| 逻辑 LUT | 890.0 | 1053.0 |
| LUTRAM | 64.0 | 96.0 |
| FF | 225.0 | 443.0 |
| DSP48E2 | 16.0 | 16.0 |
| RAMB18 | 3.0 | 3.0 |
| RAMB36 | 0.0 | 0.0 |
| URAM | 0.0 | 0.0 |
| WNS (ns) | 5.526 | 6.54 |
| WHS (ns) | 0.063 | 0.062 |
| TNS (ns) | 0.0 | 0.0 |
| THS (ns) | 0.0 | 0.0 |
| latch | 0 | 0 |

矩阵 A/B/P 各 1 个 RAMB18E2，共 3；A 四个 32×8 银行，加 B 两组共八个 8×8 银行，共 12 个 RAM32M16、96 LUTRAM。16 个 MAC 仍映射 DSP48E2；没有增加 DSP 或 URAM，没有 latch。最终 RTL/XDC SHA256 与执行前 source_inputs.json 匹配。

第一遍综合发现 bank_kt 仅用于 TB 诊断，被 Synth 8-6014 移除；已将其接入实际 READY 和同步读保护，重新跑八组回归及完整综合/OOC。第一遍源文件与日志保留在 build/db_initial_debug_tags；交付数据使用修正后的最终结果。

外部约束范围仍未确认：no_clock=0、unconstrained_internal_endpoints=0，126 输入缺 input_delay、104 输出缺 output_delay。HD.CLK_SRC=BUFGCE_X0Y0 是虚拟 OOC 评估假设。BRAM 可选输出寄存器未合并的 INFO 仍需在更高频目标时评估，当前使用一拍同步读。

## OOC 实现

已实际完成 opt_design、place_design、route_design，脚本返回 0，生成 routed_ooc.dcp。以下为最终报告。

| 项目 | 上一轮单缓冲 OOC | 当前双缓冲 OOC |
|---|---:|---:|
| LUT | 940.0 | 1121.0 |
| FF | 225.0 | 443.0 |
| DSP | 16.0 | 16.0 |
| RAMB18 | 3.0 | 3.0 |
| URAM | 0.0 | 0.0 |
| WNS (ns) | 3.989 | 4.713 |
| WHS (ns) | 0.049 | 0.008 |
| TNS (ns) | 0.0 | 0.0 |
| THS (ns) | 0.0 | 0.0 |

可路由 net=1730，完全路由=1730，路由错误=0，显式 gap=1。

utilization 状态为 Routed，最终 DRC 状态为 Partially Routed。保留 Route 35-198、DRC 23-814、RTSTAT-10 等 OOC 边界警告；这些结果只评估内部路径，不是板级签核、完整外部布线或实际频率证明。

最终 DRC 检查项：

- DPIP-2：Warning，16 项，Input pipelining。
- RTSTAT-10：Warning，1 项，No routable loads。

DPIP-2 指出 16 个 DSP B 输入未使用 DSP 内部输入寄存级；双缓冲银行输出经选择器进入 DSP，当前 MREG=0、PREG=1。它是性能建议，当前内部 10 ns 时序通过；如增加 DSP 输入流水，必须同时对齐 A/B、MAC enable 和 tile 结束时序，不能只加寄存器而不改控制。没有屏蔽该 DRC。

本次内部 hold 余量为 0.008 ns，余量较小；后续真实时钟、接口约束与布局必须重新评估，不能由本次 OOC 声称板上频率已经达标。

最终综合日志中的 Synth warning 条数：0。工具日志 warning 保存在 summary.json 的 warnings_in_report_and_impl_log；最终 DRC 具体项保存在 ooc_implementation.drc_checks，没有静默屏蔽。

## 复现与证据

```powershell
Set-Location E:\speed-up
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_sim.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_synth.ps1 -Implement
python .\scripts\summarize.py
python .\scripts\report_double_buffer.py
```

- [双缓冲单元日志](../build/sim_pingpong_unit/run.log)。
- [默认仿真日志](../build/sim_4x4_k8_db/run.log)、[默认周期 CSV](../build/sim_4x4_k8_db/results.csv)。
- [2×3 仿真](../build/sim_2x3_k5_db/run.log)、[慢装载](../build/sim_2x3_k5_db_gap3/run.log)、[快装载](../build/sim_2x1_k3_db/run.log)。
- [实际综合命令](../build/synth_db/commands.txt)、[最终完整日志](../build/synth_db/synth.log)。
- [资源报告](../build/synth_db/utilization_synth.rpt)、[时序报告](../build/synth_db/timing_synth.rpt)、[RAM 报告](../build/synth_db/ram_synth.rpt)、[原语与 latch](../build/synth_db/primitive_counts.txt)。
- [机器审计](../build/summary.json)、[单/双缓冲比较 CSV](../build/double_buffer_cycles.csv)。
- [故障注入日志](../build/sim_4x4_k8_db_negative/run.log)、[实测退出码](../build/sim_4x4_k8_db_negative/observed_exit_code.txt)。
- [OOC 资源](../build/synth_db/utilization_ooc.rpt)、[OOC 时序](../build/synth_db/timing_ooc.rpt)、[路由状态](../build/synth_db/route_status_ooc.rpt)、[DRC](../build/synth_db/drc_ooc.rpt)。

## 验证范围与下一步

| 类别 | 状态 |
|---|---|
| 上述八组配置、尾块、并发暂停/复位、银行归属 | 已实现并仿真通过 |
| 默认 4×4 双缓冲、G=0 的器件级综合 | 已执行并审计 |
| 非默认配置的综合资源/时序 | 尚未执行 |
| A 双缓冲、跨输出块预取、B 跨 M 复用 | 尚未实现 |
| DDR/HBM、可变响应延迟 burst adapter、AXI/DMA | 尚未实现 |
| 板级约束、bitstream、板上性能与功耗 | 尚未执行 |

下一步优先将 B 源按列分银行，明确每银行读端口与写入映射，使双缓冲获得足够带宽；随后引入 ready/valid burst adapter，并用随机响应延迟验证实际外部供数。当前固定同步 BRAM 不代表真实 DDR 时序。
