# 第三方来源与研究对照

本仓库基于原团队仓库的开发历史继续同步，原有源码、作者与历史提交保留。本次不为全部自研或团队代码擅自添加新的许可声明。

受控比较固定以下上游版本：

- openTPU：`810632e2e1d4961575a3c6f8f194abc8fc3f8fd3`，https://github.com/FeSens/openTPU/tree/810632e2e1d4961575a3c6f8f194abc8fc3f8fd3
- llama-fpga：`bdd90206675594ab6b710a32d5319c68a58d9c36`，https://github.com/adamgallas/llama-fpga/tree/bdd90206675594ab6b710a32d5319c68a58d9c36

实际文件、适配方法和哈希由 `experiments/compute_upstream/sources.json`、各实验说明和 R8 冻结快照记录。R8 包含其复测所需的少量 openTPU RTL；原许可保存在 `experiments/compute_round8_20261028/reference/OPEN_TPU_LICENSE`。这些上游文件不自动纳入生产系统源列表。

Vivado/XSim、厂商 IP、完整板级参考 shell 和既有参考 bitstream 不由本仓库提供。保存的压缩阵列镜像是本项目最小自检设计的构建产物，不是完整参考平台。

文献和上游作者报告的模型指标只作背景和比较依据，不等于本项目已复现对应算法或模型性能。
