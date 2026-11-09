# 固定版本计算核心微基准

此目录仅提供本工程编写的 harness、下载清单和运行入口。上游源码下载至 build，不进入生产 RTL 清单。

前提：Python 3、Vivado/XSim 2025.2；先执行本工程 `scripts/run_compute_experiments.py` 生成 `build/compute_experiments/common_cases.json`。完整本工程数据的生成顺序见主 README。默认 Vivado 路径可用 `VIVADO_BIN` 或 `--vivado-bin` 覆盖。

```powershell
# 在项目根目录运行；首次联网下载，验证固定提交 Git blob 与 SHA256
python .\experiments\compute_upstream\run_upstream_compute.py

# 仅运行 openTPU systolic（默认）/tree
python .\experiments\compute_upstream\run_upstream_compute.py --engine openTPU --impl 2
python .\experiments\compute_upstream\run_upstream_compute.py --engine openTPU --impl 0

# 仅运行 llama-fpga，首次会生成并编译实际浮点 IP
python .\experiments\compute_upstream\run_upstream_compute.py --engine llama-fpga

# 只核验来源并生成配置；离线缓存须包含 openTPU/ 与 llama-fpga/ 子目录
python .\experiments\compute_upstream\run_upstream_compute.py --prepare-only --source-cache C:\source-cache
```

输出在 `build/upstream_compute/`：来源文件、原始数值期望、生成配置、编译/展开/仿真日志、周期 CSV 与带输入 SHA256 的 result.json。PREPARED 不表示测试通过；只有 PASS 才表示全部数值和任务计数通过。上游副本不得手工改动；来源不匹配会拒绝执行。`--work-dir` 可指定独立构建目录。

数学条件：固定种子，M=1/4/8、N=64、K=128/512/4096，A/W∈{-1,0,1}、数学 scale=1。期望值用独立 Python 整数点积重新核算，不调用上游算术。这个共同可精确表示的数据集用于比较周期结构，不代表任意权重/scale 或真实模型精度的验证。

openTPU 固定提交 `810632e2e1d4961575a3c6f8f194abc8fc3f8fd3`：D128、MCOLS4、ACT_ROWS8、FIFO64、LANES8；在原有 MXU 入口测 INT8、signed INT4 和 E2M1 FP4。M1 的 4 位格式启用原生 PAIR，M8 使用 ACT replay。ACT 预装，权重和 scale 分别 1 拍响应，TMEM 一直授权。上游的 generic DSP/RAM 模型保留周期/数值行为，不用于推导实际 DSP 数或板上频率。XSim 唯一 RTL 兼容修改是把 mx_go 的 net 声明提前，原连续赋值不变。公共 reset 保持100拍，使上游未复位的元数据延迟线排空。

llama-fpga 固定提交 `bdd90206675594ab6b710a32d5319c68a58d9c36`：从 KV260 生成的 DataPath_xN.v 原文提取 MulAddSGNew 及10个递归模块，输入在权重反量化之后，128路FP16；包括原归约、FP32累积和FP16输出。M行顺序执行原生GEMV。原始XCI配置被导入私有项目副本并升级；使用真实浮点IP仿真模型，没有自写运算替代器。运行器使用 scripts_only 生成批处理脚本，随后显式编译、展开和headless运行，避免启动交互仿真界面。

三方输入位宽和预装边界不同：本工程8byte/拍；openTPU权重128byte/拍且scale独立；llama-fpga在反量化之后128×FP16/拍。有效MAC/拍统一为M×N×K/总周期，但这些原生入口结果不能解释成相同带宽、相同精度、相同DSP或同板性能排名。详情与本轮资源数据见 `docs/compute_advance.md`。
