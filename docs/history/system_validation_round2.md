# 当前系统验证（2026-10-25 / ABI v3 / 第二轮）

主系统默认4×4/TILE_K32/GROUP_SIZE32；GEMV K并行、有效排空、并行快照与双路后处理已接入。

软件20项通过。主系统12配置共261条完成记录、5,570,560字节比较通过；包括原流Q、内存Q、32/64位地址、group32/12/4/3、FFN/线性、混合引擎、故障注入与恢复。golden破坏和超时探针仍能失败。

当前llm_top在xcvu9p-flga2104-2L-e、10ns内部OOC约束下完成综合和布局布线，WNS=+0.221ns、WHS=+0.011ns，61010条网络完整路由、错误0，无latch/blackbox。来源哈希由project.py status核对。

独立计算核8配置/296任务、额外边界5配置/266任务及65,536种打包乘积组合通过；四种核物理实现均通过。50行受控数值实测和2行明确模型估计见[compute_round2.md](compute_round2.md)。K4096的缩小浮点核心容量探针未通过，不作为性能结果。

当前仍未完成真实模型和板级DDR/PCIe/CDC。历史验证见history/system_validation_round1.md；历史legacy严格审计未在本轮重跑。
