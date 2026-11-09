> 本页保留上一轮 DOUBLE_BUFFER=0 的实际结果；当前默认为双缓冲，见 [double_buffer.md](double_buffer.md)。

# 激活复用与同步装载优化：实际结果

本轮在 Windows PowerShell 5.1、Python 3.13.5 / NumPy 2.2.6、Vivado 2025.2 Build 6299465 下执行。评估器件为 **xcvu9p-flga2104-2L-e**，板卡未确认，时钟约束为 10 ns。默认 OPTIMIZED=1；OPTIMIZED=0 保留原始调度。本文由 scripts/report_optimization.py 根据实际 build/summary.json 生成。

## 已实现并验证

- A/B 源 RAM 连续同步读：一个 REQ 启动拍后，每个 WRITE 拍同时提交当前数据并请求下一地址；每个源 RAM 仍只有一个读端口。
- A 银行扩展为 ROWS×MAX_K，装载当前 M 块完整有效 K，跨 N 块复用。B 仍按 K tile 装载，K 尾块仅装载有效长度。
- PE 继续跨 K 累加，只在最后 K tile 写 P。同步接口、INT32 回绕、复位、背压与暂停语义保持原合同。
- 4×4/K8、2×3/K5 两种阵列分别运行优化和原始模式；每组 13 矩阵、480 个输出逐元素比较，共 **52 个完整任务、1920 个结果比较**。每组还有 8 个 PE 边界/溢出用例。
- 覆盖零矩阵、正负数、INT8 边界、固定随机种子、矩形、跨 K、M/N/K 尾块、GEMV、连续任务、复位中止/重启、忙时拒绝命令、暂停/恢复。暂停状态覆盖 A 装载、B 装载、RUN、SAVE。
- 每任务核对活动/暂停周期及 A/B 源读、P 写次数；物理地址与逻辑坐标边界检查通过。
- 错误期望值注入实际触发 CHECK_FAILED，PowerShell 返回 1。

| 阵列 | 模式 | 矩阵数 | 输出比较 | PE 用例 | 检查数 |
|---|---|---:|---:|---:|---:|
| 4×4, K8 | 1 | 13 | 480 | 8 | 47970 |
| 2×3, K5 | 1 | 13 | 480 | 8 | 69381 |
| 4×4, K8 | 0 | 13 | 480 | 8 | 87380 |
| 2×3, K5 | 0 | 13 | 480 | 8 | 133595 |

## 同一向量的实测活动周期

不包括主机输入写、结果读，也不包括 pause 周期。周期加速比为原始活动周期/优化活动周期；不是板上端到端性能或 token/s。

| 用例 | 阵列 | 原始模式 | 优化模式 | 周期比 |
|---|---|---:|---:|---:|
| zero | 4×4 | 155 | 93 | 1.667 |
| signed | 4×4 | 151 | 57 | 2.649 |
| int8_bounds | 4×4 | 155 | 93 | 1.667 |
| random_rect | 4×4 | 306 | 125 | 2.448 |
| cross_k | 4×4 | 458 | 198 | 2.313 |
| all_tails | 4×4 | 1836 | 634 | 2.896 |
| gemv | 4×4 | 1368 | 402 | 3.403 |
| consecutive_nonzero | 4×4 | 608 | 246 | 2.472 |
| consecutive_zero | 4×4 | 608 | 246 | 2.472 |
| minimal | 4×4 | 148 | 30 | 4.933 |
| full_capacity | 4×4 | 9872 | 3540 | 2.789 |
| tall_rect | 4×4 | 1208 | 420 | 2.876 |
| resume_after_reset | 4×4 | 308 | 139 | 2.216 |
| zero | 2×3 | 500 | 214 | 2.336 |
| signed | 2×3 | 252 | 122 | 2.066 |
| int8_bounds | 2×3 | 500 | 214 | 2.336 |
| random_rect | 2×3 | 738 | 248 | 2.976 |
| cross_k | 2×3 | 1008 | 458 | 2.201 |
| all_tails | 2×3 | 2256 | 924 | 2.442 |
| gemv | 2×3 | 750 | 296 | 2.534 |
| consecutive_nonzero | 2×3 | 558 | 249 | 2.241 |
| consecutive_zero | 2×3 | 558 | 249 | 2.241 |
| minimal | 2×3 | 60 | 17 | 3.529 |
| full_capacity | 2×3 | 21072 | 8008 | 2.631 |
| tall_rect | 2×3 | 882 | 476 | 1.853 |
| resume_after_reset | 2×3 | 248 | 97 | 2.557 |

### 默认 16×16×32 任务

| 项目 | 原始模式 | 优化模式 |
|---|---:|---:|
| 活动周期 | 9872 | 3540 |
| A 源 RAM 有效读取 | 2048 | 512 |
| B 源 RAM 有效读取 | 2048 | 2048 |
| P 有效写回 | 1024 | 256 |
| RUN 周期 | 512 | 512 |
| RUN 占活动周期 | 5.19% | 14.46% |

优化周期分解：A 装载 516、B 装载 2112、RUN 512、CLEAR 16、PRIME 64、SAVE 256、ADVANCE 64，总计 3540。活动周期减少 64.14%，周期比 2.789。B 装载仍占 59.66%，是下一步优先优化的部分。

理论峰值仍是 16 MAC/周期，假设 100 MHz 时为 1.6 GMAC/s。8192 个有效 MAC / 3540 活动周期 = 2.314 MAC/周期；假设每周期 10 ns 为 35.40 us 的 busy 时间。这是仿真周期换算，不是实测板上延迟。详见 [architecture.md](architecture.md)。

## 器件级综合：实际资源和时序

优化源文件指纹与 source_inputs.json 一致。core synth_design 实际记录 0 warning、0 critical warning、0 error。以下原始模式列取自第一轮归档综合结果；本轮已重新仿真原始模式，未重新综合该模式。

| 项目 | 第一轮原始模式 | 本轮优化模式 |
|---|---:|---:|
| LUT | 750.0 | 954.0 |
| 逻辑 LUT | 686.0 | 890.0 |
| LUTRAM | 64.0 | 64.0 |
| FF | 225.0 | 225.0 |
| DSP48E2 | 16.0 | 16.0 |
| RAMB18 | 3.0 | 3.0 |
| RAMB36 | 0.0 | 0.0 |
| URAM | 0.0 | 0.0 |
| 综合 WNS (ns) | 7.192 | 5.526 |
| 综合 WHS (ns) | 0.071 | 0.063 |
| TNS (ns) | 0.0 | 0.0 |
| THS (ns) | 0.0 | 0.0 |
| latch | 0 | 0 |

A/B 矩阵 Buffer 和 P 各推断 1 个 RAMB18E2，合计 3。A 的四个 32×8 银行和 B 的四个 8×8 银行各推断一个 RAM32M16，共 8 个、64 LUTRAM；当前深度增加利用了同一原语的剩余容量。16 个 8×8 MAC 均映射 DSP48E2，MREG=0、PREG=1，未出现额外 fabric 乘法器或 black box。扩大 MAX_K 后不能假定 LUTRAM 数量仍不增长。

优化控制/地址逻辑使 LUT 从 750 增加到 954（+204，+27.2%），FF/DSP/BRAM 不变。综合估计内部路径满足 10 ns 目标，不能由综合余量直接宣称实际 Fmax。INFO Synth 8-7052 仍提示 BRAM 没有合并可选输出寄存器；当前装载流水与同步读合同使用一拍延迟，未增加该额外寄存级。

时序检查 no_clock=0、unconstrained_internal_endpoints=0、loops=0、latch_loops=0；126 个输入未定义 input_delay、104 个输出未定义 output_delay。这些接口边界尚未进行时序签核。HD.CLK_SRC=BUFGCE_X0Y0 是 OOC 评估假设。

## 可选 OOC 实现

实际执行 opt_design、place_design、route_design，生成 routed_ooc.dcp；下表采用最终报告而非路由器中间估计。

| 项目 | 第一轮原始模式 | 本轮优化模式 |
|---|---:|---:|
| LUT | 738.0 | 940.0 |
| FF | 225.0 | 225.0 |
| DSP | 16.0 | 16.0 |
| RAMB18 | 3.0 | 3.0 |
| URAM | 0.0 | 0.0 |
| WNS (ns) | 5.272 | 3.989 |
| WHS (ns) | 0.044 | 0.049 |
| TNS (ns) | 0.0 | 0.0 |
| THS (ns) | 0.0 | 0.0 |

route_status：可路由 1407，完全路由 1407，路由错误 0，显式 gap 1。

utilization 报告 Design State=Routed；最终 DRC 报告 Design State=Partially Routed。

保留 Route 35-198（缺少 HD.PARTPIN_LOCS，route_design 实际记录 103 warning、0 critical warning、0 error）、DRC 23-814（OOC connectivity 检查不完整）和 RTSTAT-10（38 个输出 net 没有 OOC 可路由负载）等接口边界警告，未用任意管脚约束或 false path 隐藏。内部时序与可路由 net 完成评估；不能视为完整板级布线、外部接口时序签核或实际工作频率证明。

## 复现及原始证据

```powershell
Set-Location E:\speed-up
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_sim.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_synth.ps1 -Implement
python .\scripts\summarize.py
python .\scripts\report_optimization.py
```

- [优化 4×4 仿真日志](../build/sim_4x4_k8_opt/run.log)、[逐任务 CSV](../build/sim_4x4_k8_opt/results.csv)。
- [优化 2×3 仿真日志](../build/sim_2x3_k5_opt/run.log)、[逐任务 CSV](../build/sim_2x3_k5_opt/results.csv)。
- [本轮原始 4×4](../build/sim_4x4_k8/run.log)、[本轮原始 2×3](../build/sim_2x3_k5/run.log)。
- [实际 Vivado 调用](../build/synth_opt/commands.txt)、[综合/实现完整日志](../build/synth_opt/synth.log)。
- [综合资源](../build/synth_opt/utilization_synth.rpt)、[综合时序](../build/synth_opt/timing_synth.rpt)、[RAM 推断](../build/synth_opt/ram_synth.rpt)、[原语/latch 计数](../build/synth_opt/primitive_counts.txt)。
- [机器可读审计](../build/summary.json)、[周期比较 CSV](../build/optimization_cycles.csv)。
- [错误注入日志](../build/sim_4x4_k8_opt_negative/run.log)、[退出码](../build/sim_4x4_k8_opt_negative/observed_exit_code.txt)。
- [第一轮归档](../build/baseline_v1/summary.json)。
- [OOC 资源](../build/synth_opt/utilization_ooc.rpt)、[OOC 时序](../build/synth_opt/timing_ooc.rpt)、[路由状态](../build/synth_opt/route_status_ooc.rpt)、[最终 DRC](../build/synth_opt/drc_ooc.rpt)。

## 限制与下一步

| 类别 | 状态 |
|---|---|
| 当前默认容量、两种阵列、两种模式 | 已实现并仿真验证 |
| 默认优化 4×4 器件级综合 | 已执行并核对资源、DSP、RAM、latch 和内部约束 |
| 任意其它容量/阵列配置 | 参数化 RTL 支持范围内可配置，尚未验证 |
| 更大 MAX_K cache 的资源和时序 | 未评估 |
| B 跨 M 复用、装载/计算重叠、双缓冲 | 未来计划 |
| DDR/HBM、DMA/PCIe、完整 Transformer、非线性算子 | 未来计划 |
| 板级约束、bitstream、板上性能与功耗 | 未执行 |

下一步优先比较 B 分银行供数与 B 双缓冲，并建立可变延迟 burst adapter 的仿真；之后才接具体板卡的外部内存。大 K 需有界 tile cache 与明确部分和调度，不能依靠无限扩大的 A 行 cache。[next_steps.md](next_steps.md) 保留 FFN、GEMV Decode 和 Attention 的后续路线。
