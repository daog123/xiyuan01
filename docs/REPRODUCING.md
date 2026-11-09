# 环境与复现入口

## 环境

- Python 3.11 或更新版本，当前主机与离线校验代码仅依赖标准库。
- RTL/器件实现：已使用 Windows Vivado/XSim 2025.2。已有 Linux/VCS 入口不代表本次重新验证过。
- 克隆到英文路径，例如 `C:/work/xiyuan01`。历史源码哈希按原始字节保存，`.gitattributes` 关闭行尾转换。
- 大型构建目录、未压缩 bitstream、DCP 和仿真缓存不提交。带日期的必要报告和输入快照位于 `reports/`、`experiments/`。

## 离线检查（不连接板卡）

在仓库根目录：

```text
python scripts/verify_repository_snapshot.py
python scripts/verify_board_evidence.py
python -B -m unittest software.test_w4a8_software software.test_w4a8_memory_task software.test_system software.test_board_mailbox -v
```

快照检查验证当前同步版本的文件指纹；继续修改工程后不再匹配是预期行为。板级检查重新解码原始物理采样，并检查可加载压缩镜像的完整 SHA256；它不是一次新的物理运行。

## 主系统 RTL 与内部实现

PowerShell 示例，在仓库根目录执行：

```powershell
$env:VIVADO_BIN = 'E:/AMDDesignTools/2025.2/Vivado/bin'
python scripts/project.py test --vivado-bin $env:VIVADO_BIN
python scripts/project.py implement --vivado-bin $env:VIVADO_BIN
python scripts/project.py status
```

`test` 会生成输入、执行软件和各子系统仿真；`implement` 执行主系统内部 OOC，**不会生成已集成 DDR/Aurora 的整板镜像**。`status` 只审计本机已经生成的 test/implementation 结果，首次克隆不能直接依靠它通过。历史 `reports/` 不自动填充为新的本机 PASS。

主系统 OOC 目标保持原 `xcvu9p-flga2104-2L-e`。CIV 实体板需要相应 shell、约束及独立配置，不能仅改主系统 part 就视为完成板级集成。

## R7 前后配对

```powershell
$env:VIVADO_BIN = 'E:/AMDDesignTools/2025.2/Vivado/bin'
python scripts/prepare_round7_baseline.py
python scripts/benchmark_round7.py
```

准备脚本将仓库内必要冻结模块恢复到被忽略的 `build/round7_baseline`；不需要原开发机 E 盘快照。输入在本地依据固定种子生成。结果写到 `build/round7_performance`，包含前后、禁用缓存与单项消融，测试时间明显长于软件检查。

保存的历史配对结果位于 `reports/round7_performance`，协议结果位于 `reports/round7_protocol`。完整 `audit_round7.py` 还要求本机已经运行主系统测试/实现、`test_round7.py` 和配对，不是仅有基线即可执行。

## 独立 R8 单行流式核

```powershell
$env:VIVADO_BIN = 'E:/AMDDesignTools/2025.2/Vivado/bin'
Set-Location experiments/compute_round8_20261028
python run.py prepare
python run.py baseline
python run.py open_baseline
python run.py stream
```

`reference/` 含冻结旧核、原有输入和固定 openTPU 核依赖；无需运行时下载。原始记录保留在实验目录和 `reports/compute_round8_20261028`。上述命令会更新该实验工作文件，建议在独立工作副本复现并保留原记录。

实现入口：`python run.py implement`。可设置 `ROUND8_OOC_WORK` 到独立英文路径。R8 核不在生产 `config/system_sources.txt` 中，不因同步自动接入主系统。

## 自研阵列镜像重建

```powershell
$env:VIVADO_BIN = 'E:/AMDDesignTools/2025.2/Vivado/bin'
python experiments/array_bist_20261027/run_local.py
python experiments/array_bist_20261027/run_local.py --variant diag_civ
python experiments/array_bist_20261027/run_local.py --variant positive_civ
```

先仿真，再构建。使用正式 CIV 目标 `xcvu9p_CIV-flgb2104-2-i`；生成目录已存在时脚本拒绝覆盖。历史报告另存 `reports/array_bist_20261027/implementation`，当前实验目录可以从新输出开始。

重建后的镜像不要求与历史镜像具有相同字节哈希（工具日期等会变化），但器件 ID、源文件、时序与验收帧必须核对。历史实际加载镜像已压缩保存在 `artifacts/array_bist_20261027`。

## 物理复现

见 [BOARD_VALIDATION.md](BOARD_VALIDATION.md)。离线校验、软件测试、RTL 仿真和物理加载是不同操作，不会由快速检查自动连接服务器或烧录。
