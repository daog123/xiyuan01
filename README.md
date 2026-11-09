# 曦源项目：W4A8 算子系统与 FPGA 验证

本仓库同步自本地 `speed-up` 工程，2026-11-09 更新。包含 R7 生产主线、独立 R8 单行流式研究核、2026-10-27 自研阵列实体验证，以及最新中期汇报材料。**同步日期不代表重新执行了所有历史实验**，各报告保留实际实验日期、源码哈希与验证范围。

## 当前状态

| 范围 | 已完成 | 证据边界 |
| --- | --- | --- |
| 主系统 `llm_graph_top` / ABI v5 | LINEAR、FFN、KV、Attention 和自动 QKV 子链；R7 供数优化 | 有界 RTL 验证与内部 OOC 实现，尚无完整模型 token 生成 |
| R7 完整算子性能 | 相对 R6，8 组长 LINEAR 加速约 1.90–2.14× | 相同输入、配置和 AXI 服务条件的 RTL 仿真，不是板测吞吐 |
| R8 单行研究核 | M1/N64/K2048：10,615 → 9,510 拍；openTPU64 同批复测 9,564 拍 | 独立 64 乘积通道、8 字节入口实验，尚未接入生产主系统或实体板 |
| 自研 4×4 阵列上板 | 8 组固定 ROM 用例，128 项板内检查一致；故障对照检出 1 项错误 | 主机通过 DONE 读取 CRC 帧、校验值和错误数，未接入完整 DDR/Aurora 算子路径 |
| 完整 LINEAR 板级端点 | 寄存器、主机访问层、RTL/IP/BD 验证 | 完整自研端点尚未与实体 DDR/Aurora shell 集成 |

完整主机动态输入、DDR 数据通路、O/RoPE/RMSNorm/残差/完整 Block、真实模型质量和整板性能仍是后续工作。

## 从哪里开始

- [当前状态与阶段边界](docs/CURRENT_STATUS_20261109.md)
- [环境、验证与复现步骤](docs/REPRODUCING.md)
- [阵列上板范围、原始记录与重放方法](docs/BOARD_VALIDATION.md)
- [R7 供数优化报告](docs/system_round7.md) 与 [配对原始数据](reports/round7_performance/comparison.csv)
- [R8 独立单行核报告](reports/compute_round8_20261028/单行计算核优化结果.md)
- [此次同步说明](docs/SYNC_20261109.md)
- [第三方来源与许可](THIRD_PARTY_NOTICES.md)

## 目录

```text
rtl/ software/ model/ tb/     当前主系统、主机代码、参考模型与测试台
config/ constraints/ scripts/ 配置、内部时钟约束和构建/验证入口
experiments/                  受控开源实验、阵列自检、独立 R8 核
baselines/round6_for_round7/   R7 配对需要的冻结 R6 模块
reports/                      有实际日期的验证记录、CSV、报告和板级采样
artifacts/array_bist_20261027/ 已验证自检镜像的压缩文件及哈希
presentations/                中期 V8 PPT 与 11 月 3 日讲稿
docs/history/                 历史说明与交接材料，按写作日期解读
```

## 快速离线检查

建议 Python 3.11 或更新版本。在仓库根目录执行，无需 FPGA 或 Vivado：

```text
python scripts/verify_board_evidence.py
python scripts/verify_repository_snapshot.py
python -B -m unittest software.test_w4a8_software software.test_w4a8_memory_task software.test_system software.test_board_mailbox -v
```

RTL 仿真与实现使用 Vivado/XSim 2025.2；运行前阅读[复现说明](docs/REPRODUCING.md)，建议将仓库放在英文路径。`scripts/project.py status` 检查本机已经生成的证据，**不能在全新克隆、尚未运行 test/implement 时当作首次测试入口**。

> 器件范围：主系统历史 OOC 为 `xcvu9p-flga2104-2L-e`；实体阵列镜像为 `xcvu9p_CIV-flgb2104-2-i`。前者的 10 ns 内部时序不是实际板卡 100 MHz 验收。下文保留 R7 主线原有说明，最新实体状态以上述入口为准。

---

# R7 主线工程说明

本项目把团队的 A/D 控制与软件、B/F 存储/KV、C/E 计算与数值模块汇合为一个可仿真、可综合的算子系统。当前主顶层为 **`rtl/llm_graph_top.sv`**（内部复用`llm_top`引擎），包含统一任务提交、共享 AXI 所有权和完成记录。

| 功能 | 当前实现 |
|---|---|
| LINEAR | signed INT8 × signed INT4，group scale，Q16.16 写回 |
| FFN | gate → up → 真实外存读取 → SiLU×up → dynamic requant → qx/sx 写回确认 → down |
| KV | layer/head 独立长度、事务式 append、已提交前缀读取、clear |
| Attention | 主机INT8、内存INT8/scale或Q16.16自动量化、量化 K/V、动态 QK、近似稳定 Softmax、AV、Y 写回确认 |
| 地址 | 主通路 64 位，保留 32 位兼容模式，65 位范围/溢出检查 |

系统以单活动任务顺序执行，优先保证阶段、存储和完成边界正确。默认 FFN 中间桥容量 512 个元素，Attention 最大维度 64、最大前缀 16 个 token。当前尚未包含 RMSNorm、RoPE、完整 Q/K/V/O 自动任务图（已完成Q/K/V到Attention）、残差、真实模型运行时和板级 DDR/PCIe。

## 第七轮供数优化（2026-10-26，ABI v5，当前）

新增两条16字节权重行窗口及同M块/group的sx缓存（默认1KiB、128组），维持原packet顺序与数值。相对第六轮，8组长LINEAR加速1.90–2.14倍；12组小LINEAR约1.14–1.67倍，12组小FFN约1.09–1.45倍。关闭两项新功能后32组周期和流量逐项复现第六轮。25软件、20主系统配置、17协议/存储配置通过；当前10ns OOC WNS +0.042ns、WHS +0.011ns。详见[第七轮报告](docs/system_round7.md)。

## 第六轮供数优化（2026-10-26，ABI v5，历史）

矩阵激活行新增最多4拍的有界AXI burst与四槽返回缓冲，保持单outstanding，整条burst检查后才供数。对齐长LINEAR的8组配对加速1.00586–1.02044倍；原24组非对齐小LINEAR/FFN周期不变。有效字节、beat及写确认不变。25软件、20主系统配置、11协议/存储配置与32组完整算子配对通过；当前10ns OOC WNS +0.082ns、WHS +0.011ns。详见[第六轮报告](docs/system_round6.md)。

## 第五轮计算映射（ABI v5，历史，2026-10-26）

新增自适应小行数K并行：8×8的M2/N64/K4096从47,627降到21,929拍，M4从52,193降到27,093拍；4×4的M2为1.898倍。输入字节、scale、舍入和乘积通道数不变，MULTIROW_FOLD默认开启。完整外存算子的收益较小，仍受供数限制。资源、时序、当前验证及边界见[第五轮报告](docs/compute_round5.md)。复现入口为benchmark_round5.py、benchmark_round5_system.py、implement_round5.py及project.py。

## 第四轮精进（ABI v5，历史阶段，2026-10-26）

新增 `QKV_ATTENTION=6`：一次提交K/V投影、完整group动态量化、事务式KV追加，然后Q投影和Attention，返回一个根完成。主机无需喂K/V或Q数据流，复用原矩阵核。根完成保留stage以区分KV提交前后失败，支持只恢复Q/Attention；原opcode0..5直接转发。接口与恢复合同见[自动Q/K/V说明](docs/qkv_attention.md)。

FFN gate/up的Q16.16读取由四次字节事务合为一次对齐word事务；每个中间元素减少6次读取，有效字节和写确认相同。当前数字、资源、验证和限制见[第四轮报告](docs/system_round4.md)。复现入口为 `project.py test/implement/status`、`benchmark_round4.py`、`experiments/round4_qkv_large/run_large.py`。

仍缺O投影、RoPE和完整Block/模型/板级运行。第三轮及更早记录以下保留为历史阶段。

## 第三轮系统精进（ABI v4，历史阶段）

新增 `Q_ATTENTION=5`：一次提交自动执行Q投影、确认Q16.16写回、完整group动态量化、Attention和Y写确认。根完成使用Attention任务ID，K/V沿用已有已提交缓存。新增 `q_source=2` 也可让普通Attention直接读取Q16.16。详见[接口、数值与错误边界](docs/projected_attention.md)及[第三轮结果](docs/system_round3.md)。

LINEAR/FFN矩阵读取与Q预取使用有界连续1/2/4/8字节读取，按行尾/scale/打包孔洞拆分，禁止padding或分配区外预读。仍为单拍、单outstanding。本轮改变系统供数，第二轮计算核及其64路微基准边界保持区分。

当前复现：`project.py test`、`round3_checks.py`、`round3_storage_checks.py`、`benchmark_round3.py`、`experiments/round3_memory/run_large.py`、`project.py implement/status`。当前模型执行链仍缺K/V自动投影与append、RoPE、O投影以及完整Block。

## 第二轮计算优化（历史阶段，2026-10-25）

主系统默认4×4/TILE_K32，保持group32与ABI v3。已启用单行GEMV的K维折叠、有效波前排空、按列分bank的并行部分和保存和双路后处理。8×8研究核的长单行从65,889降至21,111拍；满8行从127,007降至61,326拍。打包广播研究核使用42个DSP，默认主系统关闭该研究选项。

统一64乘积通道、8字节/拍和空缓存计时后，本工程新版长单行与openTPU约差1.11倍。FP16按字节/元素两种预算分开比较，完整方法、边界、资源和原始数据入口见[第二轮报告](docs/compute_round2.md)。复现先执行 `python scripts/prepare_round2_inputs.py`，再执行 `run_round2.py`、`test_round2_edges.py`、`implement_round2.py` 和 `experiments/controlled_compute/run_controlled.py`。

## 长期规划与阶段任务

完整计划见 **[项目长期规划与阶段任务 README](README_ROADMAP.md)**，包含三人整合来源、当前能力与限制、M0–M5 任务清单、职责分工、交付物和验收标准。

长期目标是在 FPGA 板卡上运行真实量化模型，完成连续文本生成，并提供可复现的精度与性能结果。下一轮先固定接口和数值合同，再打通一次提交的 **Q/K/V → Attention → O** 自动链路，随后加入 RMSNorm、RoPE、残差与既有 FFN，形成小尺寸完整 Block。容量扩展、真实模型、多层执行、板级接入和性能优化按阶段推进。

本次规划基于三人已整合的 `af1f0a6` 实现；新增文档不代表规划功能已经实现。当前边界以本文、[项目状态](docs/project_status.md)及系统配置为准。

## 从当前源码验证

在项目根目录执行，依赖 Python 和 Vivado 2025.2：

```powershell
Set-Location E:\speed-up

# 软件、FFN/线性、Attention/KV，以及同一顶层跨引擎混合任务
python .\scripts\project.py test

# 按统一配置综合、布局布线、修复 hold，并要求最终 setup/hold 和路由达标
python .\scripts\project.py implement

# 核验测试/实现证据是否与当前源码 SHA256 一致
python .\scripts\project.py status

# 原团队接口与各阶段模块的兼容回归
python .\scripts\project.py legacy
```

默认 Vivado 路径为 `E:\AMDDesignTools\2025.2\Vivado\bin`；可设置 `VIVADO_BIN` 或传入 `--vivado-bin`。软件不依赖第三方 Python 包。`test` 从数学参考重新生成数据，不依赖历史 build 中的 PASS 或综合报告。`legacy` 保留原阶段的严格对照审计，使用当前项目已有的 wave 基线及其独立回归入口。

单独运行 FFN/线性或 Attention：

```powershell
python .\scripts\project.py test --suite system
python .\scripts\project.py test --suite attention
python .\scripts\project.py test --suite projection
```

## 一个入口、一份配置、一份源码清单

- `config/system_profile.json`：主顶层llm_graph_top、64 位地址、阵列、容量、Attention 范围、器件与时钟。
- `config/system_sources.txt`：综合与新系统仿真共用的有序 RTL 清单。
- `scripts/project.py`：统一运行、日志、退出码、负例/超时探针和证据审计。
- `software/system.py`：与硬件 opcode 对齐的版本化任务、FFN 计划、KV 配置/命令、Attention 描述符及运行时。
- `build/project_v2/`：软件与公共结果、汇合顶层的 OOC 报告。
- `build/system_v2/`、`build/attention_v2/`：逐配置仿真、完整内存镜像与数值参考。

`config/project.json` 中的旧配置保留为兼容与历史描述；新的系统参数以 `system_profile.json` 为准。原 `w4a8_system_top`、`w4a8_team_top` 和独立模块脚本继续保留。

## 接口与完成语义

公共入口接受 LINEAR、FFN、ATTENTION、KV_CONFIG、KV_COMMAND、Q_ATTENTION、QKV_ATTENTION 七类任务（ABI v5）。描述符在任务握手时锁存；任何阶段出错都会阻止后续阶段。任务完成后仍需主机接收 completion，才释放任务槽。

FFN 的 gate/up 数值真实写入外存，qx/sx 也真实写入下一层分配区。Attention 只读取 KV 已提交的可见前缀，结果写回后等待全部 B response。内部计算 done 和存储写确认分别处理。

主总线支持 64 位地址，allocation capacity 和 stride 为 uint32。越界、回绕、错误格式以及危险的工作区别名会在访问前拒绝。当前外存接口为单outstanding、单拍AXI；矩阵/Q读取按合法连续片段使用1/2/4/8字节，其余旧通路仍可使用字节事务，burst和多outstanding尚未接入。

ABI v5保留Attention的主机INT8流、内存Q/scale、或Q16.16自动分组量化；Q_ATTENTION自动衔接Q投影。普通Attention使用已提交KV，新增QKV_ATTENTION可自动投影、量化并追加K/V。调用方可按位置给出可见 tokens 前缀来执行 Prefill/Decode。Q/K/V投影及append已由新根图自动衔接；RoPE、O投影和完整层仍需继续连接。

## 初始性能优化与上游对照（历史阶段）

此前已完成 AXI 单字节读取器的地址/响应直通优化，保留反压缓存、单 outstanding 和异常排空。原版源码保存在 `tb/baselines/`。24 组配对算子测试的周期减少 6.14%–28.15%；这是指定小尺寸输入与固定内存延迟下的 RTL 仿真结果。

```powershell
python .\scripts\benchmark_round3.py
python .\scripts\compare_upstream.py
```

详见[优化、验证与 openTPU / llama-fpga 对比](docs/performance_comparison.md)。报告列出上游固定版本公开的板卡数据；当前尚无本工程完整模型 tokens/s 或三方同板同模型的性能排名。源码更新后应重新执行回归和实现，再核对 `project.py status`。

## 第一轮计算核心与结构接入（历史阶段）

`w4a8_wave` 默认开启 `COMPACT_SLOTS=1`：尾块的初始化、部分和保存、scale 后处理和输出只访问有效位置，保留物理 PE/RAM 索引和原数值合同。`COMPACT_SLOTS=0` 是同源码的配对基线；优化前完整源码保存在 `tb/baselines/w4a8_wave_precompact.sv`。

Attention 新增 `attention_q_dma` 和 ABI v3。`q_source=1` 时先从 `q_addr` 读取 signed INT8 Q、从 `qs_addr` 读取 little-endian UQ4.12 scales，全部读响应排空后移交 AXI 给 KV，再执行 Attention。`q_source=0` 保留主机流；已有调用可用默认字段。这段保留第一轮记录；当前Q投影自动量化见第三轮文档，RoPE和完整任务图仍待接入。

```powershell
# 重新生成原始数值用例，再跑原版/新版配对计算实验与四份独立核物理实现
python .\model\w4a8_reference.py
python .\model\w4a8_systolic_vectors.py
python .\scripts\run_compute_experiments.py --implement

# 额外参数/协议边界
python .\scripts\test_compact_slots.py
python .\scripts\test_q_dma.py

# 固定版本上游真实核心；首次联网下载，校验来源哈希，使用 Vivado/XSim
python .\experiments\compute_upstream\run_upstream_compute.py
```

详细数值、原始 CSV、统计边界和后续瓶颈见[本轮计算实验与结构改进](docs/compute_advance.md)。上游只在独立实验目录使用，不进入本工程综合清单。

## 文档

- [系统架构、任务与存储边界](docs/system_architecture.md)
- [统一数值合同](docs/system_numerics.md)
- [当前验证与布局布线结果](docs/system_validation.md)
- [当前项目状态与后续工作](docs/project_status.md)
- [三人整合的第一阶段记录](docs/team_integration.md)
- [原 FFN 数值合同](docs/ffn_numerics.md)、[原 KV 接口](docs/kv_cache_interface.md)
- [整体化之前的 README](docs/history/README_pre_system_v2.md)

## 验证边界

本地仿真使用真实 RTL 与独立数值参考，覆盖高于 4 GiB 的地址、整数数值、padding/保护区、读写错误、延迟写确认、复位恢复和连续任务。OOC 证明的是所配置器件与内部时钟下的实现结果。实际板卡、引脚、外部 I/O delay、DDR/PCIe、CDC 与真实模型精度仍需板级平台补齐后验证。

复位必须覆盖系统和外部 fabric。没有收到响应的 AXI 事务不能通过伪造 completion 来释放内存；外部接口失去响应时需要平台级恢复策略。
