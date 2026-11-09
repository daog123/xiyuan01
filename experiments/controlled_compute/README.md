# 64乘积通道受控计算实验

本实验比较空缓存开始的核心任务周期，包括各自输入装载和后处理，按数学乘积累加计MAC。它不模拟板级DDR/PCIe，不给出tokens/s，不统一DSP/LUT面积。当前结果与完整限制见 `docs/compute_round2.md`；原始固定版本来源与SHA256见 `experiments/compute_upstream/sources.json`。

从 `E:/speed-up` 执行（Python、Vivado/XSim 2025.2；可用 `VIVADO_BIN` 指定工具目录）：

```powershell
python scripts/prepare_round2_inputs.py
python experiments/controlled_compute/run_controlled.py
```

第一步准备确定性数据、冻结基线及固定版本上游依赖。第二步重新生成适配核/测试台并依次运行三方。可用 `--engine prepare` 仅生成，随后用 `--engine own`、`open`、`llama` 分别运行；分开运行前必须先prepare。生成结果位于 `build/controlled_compute/`，每项有 `result.json`、原始日志和CSV。测试前保存实际runner/prepare脚本的不可变SHA256快照，结果引用实际使用的文件。测试台改变后必须重新运行，不能复用旧结果。

## 用例与计时

- 三方共同基础用例为M1/8、N8、K128/512；本工程与openTPU另测M1/8、N64、K4096，以及M1/8、N64、K2048。llama64另实测M1/N64/K2048。
- A/W均为同一确定性整数序列{-1,0,1}，scale为1；本工程使用INT8×INT4，上游openTPU使用对应INT8×INT4模式，llama输入为FP16。期望值由独立整数参考生成，转换成各自输出格式；浮点正负零等价。该数据集合不代表真实模型精度。
- 所有实例为64个逻辑乘积通道。本工程保留原生8字节/拍接口、量化分组和缓存。对照保留各自的数据布局和复用机制，供数预算相同不表示访问字节总量相同。
- openTPU关闭单位scale快速旁路。INT8 ACT按8字节/拍预装并计时，原生FP32 ACT scale缓存装载成本也计时。权重64字节和scale4字节请求共用每拍补充8字节、上限256字节的有限信用预算，攒够后才授权响应。量化粒度D64与本工程group32的差异仍然保留。
- llama64逐行执行GEMV。先装A再送W，FP16输入位于反量化之后，片上postscale固定为1。字节口径为A/W各64元素每16拍一次（各活动阶段8字节/拍）；元素口径为A每8拍、W每4拍一次（各活动阶段8/16元素，16/32字节/拍）。不能将这两种口径混为同一带宽排名。

## 固定源与适配范围

openTPU提交 `810632e2e1d4961575a3c6f8f194abc8fc3f8fd3`，D64/MCOLS1/ACT_ROWS8/IMPL2，使用其generic周期DSP/RAM模型。为XSim前移mx_go声明；为MCOLS1的ASCALE/RMAX列索引增加最小1位宽保护（受测模式不启用这些选择），算术及调度算法保持原样。未对上游做同器件物理实现，不能推导其DSP数或最高频率。

llama-fpga提交 `bdd90206675594ab6b710a32d5319c68a58d9c36`。由原生四个32路子核保留两个，得到64通道；原四输入FP32归约保留，未用两路输入精确零并镜像有效/末尾信号。保留原算术模块及真实XCI浮点仿真模型，原始32槽ACT缓存和元数据容量均保留，所以本适配核只验证K≤2048。

曾尝试将ACT RAM扩为64槽并放宽地址，但K4096探针未完成，表明仅扩RAM不足以解除元数据限制。失败记录保存在 `build/controlled_compute/llama64_capacity_probe/`，不计入收益或通过结果。原生128路核心的历史K4096记录不能用于宣称64路适配核支持K4096。

## 实测与估计的区分

当前通过记录共50行：本工程旧版/新版/广播/打包各8行，openTPU8行，llama两种供数口径各5行。llama实测点满足 `T=M*((K/64)*A_interval+(N*K/64)*W_interval+98)+(M-1)`，导出汇总表中的M8/N64/K2048两行属于容量内模型估计，`evidence_kind`单独标记；它们不由测试台运行产生，也不计入50行实测。K4096不使用该模型外推。

完整系统验证另用 `python scripts/project.py test`、`implement`、`status`。本目录的适配核与上游依赖不加入主系统RTL清单。
