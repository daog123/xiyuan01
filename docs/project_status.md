# 当前项目状态

> 2026-11-09 仓库同步更新：R7 主系统、10 月 27 日自研阵列实体自检、10 月 28 日独立 R8 研究核已一起入库。最新阶段边界见 [当前状态](CURRENT_STATUS_20261109.md)，运行步骤见 [复现说明](REPRODUCING.md)。下文按各历史阶段的写作日期解读，完整自研主机/DDR 闭环仍待完成。

## 第七轮供数优化（2026-10-26，ABI v5，当前）

新增两条16字节权重行窗口及同M块/group的sx缓存（默认1KiB、128组），维持原packet顺序与数值。相对第六轮，8组长LINEAR加速1.90–2.14倍；12组小LINEAR约1.14–1.67倍，12组小FFN约1.09–1.45倍。关闭两项新功能后32组周期和流量逐项复现第六轮。25软件、20主系统配置、17协议/存储配置通过；当前10ns OOC WNS +0.042ns、WHS +0.011ns。详见[第七轮报告](system_round7.md)。

## 第六轮供数优化（2026-10-26，ABI v5，历史）

矩阵激活行新增最多4拍的有界AXI burst与四槽返回缓冲，保持单outstanding，整条burst检查后才供数。对齐长LINEAR的8组配对加速1.00586–1.02044倍；原24组非对齐小LINEAR/FFN周期不变。有效字节、beat及写确认不变。25软件、20主系统配置、11协议/存储配置与32组完整算子配对通过；当前10ns OOC WNS +0.082ns、WHS +0.011ns。详见[第六轮报告](system_round6.md)。

## 第五轮计算映射（2026-10-26，ABI v5，历史）

自适应M/K映射默认开启；8×8 M2/M4长任务分别2.172/1.926倍，默认4×4 M2为1.898倍。12种核心配置、25软件和20主系统配置通过；当前主顶层10ns OOC WNS +0.205ns、WHS +0.011ns，路由错误0。详见[第五轮报告](compute_round5.md)。完整外存算子的本轮收益较小，供数仍是后续重点；结构功能与ABI v5保持一致。

## 第四轮精进（2026-10-26，ABI v5，历史）

当前顶层llm_graph_top：一次提交K/V投影、量化、事务式追加，再执行Q/Attention；保留完成阶段与提交后仅Q恢复。FFN改为对齐word读取，12组实测加速1.125–1.494倍，LINEAR对照不变。N64/K4096两步整链通过。

25软件、20配置/489完成/10,813,440字节比较通过；10ns OOC WNS +0.143ns、WHS +0.011ns、路由错误0。详见[第四轮报告](system_round4.md)和[接口](qkv_attention.md)。O/RoPE、Block、真实模型及板级仍未完成。以下保留历史阶段。

## 第三轮系统精进（ABI v4，历史）

已完成Q投影→写确认→动态量化→Attention的一次提交子链，以及矩阵/Q的有界连续1/2/4/8字节读取。4×4/N64/K4096长单行加速3.811倍，8行3.759倍；均为含存储服务的RTL实测。

22软件、16配置/365完成/8,192,000字节比较通过；10ns OOC WNS +0.183ns、WHS +0.010ns，路由错误0，当前源审计通过。详见[第三轮报告](system_round3.md)。完整K/V/O图、RoPE、Block和板级仍未完成。以下为历史阶段记录。

## 第二轮计算改进（历史，2026-10-25）

当前主系统ABI v3、4×4/TILE_K32。已接入GEMV K维并行、有效排空、并行快照和双路后处理；打包广播作为默认关闭的研究参数。当前独立核心DSP为4×4 26、8×8 74，打包广播42；21/69属于历史实现。

主系统12配置/261完成记录、20软件测试和当前源哈希审计通过；10ns OOC WNS=+0.221ns、WHS=+0.011ns，路由错误0。控制实验和限制见[第二轮报告](compute_round2.md)。下文为历史阶段记录。


## 2026-10-25 计算调度与内存 Q 接入（当前）

当前为 **llm_top / ABI v3**。紧凑有效槽位调度已默认启用；Attention 已新增已量化 Q/scale 的内存预取与 AXI 所有权移交。8×8 的 M1/N64/K4096 从124577降到65889拍；满8行同形状周期不变。没有增加单PE乘积数量或实现K并行GEMV映射。

20项软件、12个主系统配置/261条完成记录、四核配对实验、额外参数与DMA协议回归通过。当前主顶层OOC WNS=+0.159ns、WHS=+0.011ns，路由错误0。四份独立4×4/8×8核均完成布局布线，DSP仍为21/69。

openTPU两种实现共54用例与llama-fpga9用例已实际执行并核对数值。供数带宽、数值格式和计算规模不同，结果用于结构诊断；详见[本轮报告](compute_advance.md)。

内存Q接入尚未包含投影结果自动量化；完整Q/K/V/O任务图、RMSNorm、RoPE、残差、真实模型与板级DDR/PCIe仍待完成。下面为原阶段历史记录，其中旧ABI、资源、时序和测试数量不代表当前版本。


## 2026-10-25 读取通路优化与性能对照

当前读取器增加空闲地址/完整响应直通，保留反压缓存、单 outstanding、错误排空和写确认。原版源码保存在 `tb/baselines/`，新增 `scripts/benchmark_performance.py` 从原版/新版重建并对照完整内存。

24 组配对任务的周期减少 6.14%–28.15%，仅代表本轮小尺寸算子与固定内存延迟条件下的 RTL 仿真。19 项软件、8 组系统/Attention/混合回归通过。当前 `llm_top` 在 10 ns 内部 OOC 目标下完成布局布线，WNS=+0.366 ns、WHS=+0.007 ns，路由错误为 0。

完整方法、原始数据入口与上游固定版本的公开性能对照见[性能对比报告](performance_comparison.md)。当前仍未运行完整模型或完成板级接入，不能将本轮算子收益表述为超过 openTPU / llama-fpga 的模型吞吐。

以下保留原阶段的功能与规划记录。

2026-10-15：当前主系统为 **llm_top / ABI v2**。三方模块已形成统一任务入口、共享 AXI 所有权及完成路由。完整外存 FFN、事务式 KV 和有界 Attention 已形成真实 RTL 闭环，并通过当前源码仿真；汇合顶层 OOC 最终 WNS=+0.321 ns、WHS=+0.010 ns。

## 已实现

- 64 位主地址通路与 32 位兼容模式，65 位范围/回绕检查。
- LINEAR、FFN、ATTENTION、KV_CONFIG、KV_COMMAND 五类任务与统一完成反压。
- gate/up 外存写确认 → FFN DMA → 原 SiLU/dynamic requant → qx/sx 外存写确认 → down。
- KV 分 layer/head 提交长度、append/read/clear；Attention 读取已提交前缀，QK/Softmax/AV 后真实写回 Y。
- 同一顶层跨引擎连续任务与出错恢复，统一软件 API、profile、source manifest、test/implement/status/legacy 入口。

## 当前工程范围

默认 FFN 中间元素上限 512、Attention 维度上限 64、可见前缀上限 16；一个任务顺序执行。Q 通过量化流输入。当前完整的是这些算子事务，不是完整 Transformer/LLM token 生成。

## 2026-10-18 规划更新

完整未来规划见 [README_ROADMAP.md](../README_ROADMAP.md)，包含 M0–M5 阶段任务、验收标准和 A/D、B/F、C/E 分工。下一次联合交付为小尺寸 Q/K/V 投影 → 自动 Q/KV 数据通路 → Attention → O 投影；随后接入 RMSNorm、RoPE、残差和 FFN，形成完整 Block。

本次更新仅增加规划与文档入口，未修改 RTL、软件 API 或系统配置。上述 2026-10-15 验证仍对应实现基线 `af1f0a6`；未来功能需完成实现和回归后才能更新完成状态。

## 后续工作

1. 连接 Q/K/V/O 投影后的量化和 Q 流 DMA，加入 RoPE、RMSNorm、残差及整张 Transformer 任务图。
2. 扩展 Attention 序列/维度容量、GQA、分页/滑窗与 mask，并针对真实模型校准数值和精度。
3. 在当前 fence 合同下增加更高效的 burst、多 outstanding、输出 FIFO 与阶段重叠，保持本版顺序路径作为回归基线。
4. 确定板卡后加入真实 DDR/PCIe、CDC/复位、引脚及 I/O delay 约束，开展板级和真实模型验证。

详见[架构](system_architecture.md)、[数值](system_numerics.md)、[验证](system_validation.md)。原项目状态保留在 [history](history/project_status_pre_system_v2.md)。
