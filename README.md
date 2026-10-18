# W4A8 统一算子系统

本项目把团队的 A/D 控制与软件、B/F 存储/KV、C/E 计算与数值模块汇合为一个可仿真、可综合的算子系统。当前主顶层为 **`rtl/llm_top.sv`**，包含统一任务提交、共享 AXI 所有权和完成记录。

| 功能 | 当前实现 |
|---|---|
| LINEAR | signed INT8 × signed INT4，group scale，Q16.16 写回 |
| FFN | gate → up → 真实外存读取 → SiLU×up → dynamic requant → qx/sx 写回确认 → down |
| KV | layer/head 独立长度、事务式 append、已提交前缀读取、clear |
| Attention | 量化 Q/K/V、动态 QK、近似稳定 Softmax、AV、Y 写回确认 |
| 地址 | 主通路 64 位，保留 32 位兼容模式，65 位范围/溢出检查 |

系统以单活动任务顺序执行，优先保证阶段、存储和完成边界正确。默认 FFN 中间桥容量 512 个元素，Attention 最大维度 64、最大前缀 16 个 token。当前尚未包含 RMSNorm、RoPE、完整 Q/K/V/O 自动任务图、残差、真实模型运行时和板级 DDR/PCIe。

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
```

## 一个入口、一份配置、一份源码清单

- `config/system_profile.json`：主顶层、64 位地址、阵列、容量、Attention 范围、器件与时钟。
- `config/system_sources.txt`：综合与新系统仿真共用的有序 RTL 清单。
- `scripts/project.py`：统一运行、日志、退出码、负例/超时探针和证据审计。
- `software/system.py`：与硬件 opcode 对齐的版本化任务、FFN 计划、KV 配置/命令、Attention 描述符及运行时。
- `build/project_v2/`：软件与公共结果、汇合顶层的 OOC 报告。
- `build/system_v2/`、`build/attention_v2/`：逐配置仿真、完整内存镜像与数值参考。

`config/project.json` 中的旧配置保留为兼容与历史描述；新的系统参数以 `system_profile.json` 为准。原 `w4a8_system_top`、`w4a8_team_top` 和独立模块脚本继续保留。

## 接口与完成语义

公共入口接受 LINEAR、FFN、ATTENTION、KV_CONFIG、KV_COMMAND 五类任务。描述符在任务握手时锁存；任何阶段出错都会阻止后续阶段。任务完成后仍需主机接收 completion，才释放任务槽。

FFN 的 gate/up 数值真实写入外存，qx/sx 也真实写入下一层分配区。Attention 只读取 KV 已提交的可见前缀，结果写回后等待全部 B response。内部计算 done 和存储写确认分别处理。

主总线支持 64 位地址，allocation capacity 和 stride 为 uint32。越界、回绕、错误格式以及危险的工作区别名会在访问前拒绝。当前外存接口使用单 outstanding 的窄单拍 AXI，带宽优化属于后续工作。

Attention 接收已经量化的 Q 流；K/V 通过 KV append 提交。调用方可按位置给出可见 tokens 前缀来执行 Prefill/Decode。Q/K/V 投影、RoPE 和跨算子的完整自动任务图仍需进一步连接。

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
