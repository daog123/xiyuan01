# 主系统长K存储微基准

在项目根目录运行 `python experiments/round3_memory/run_large.py`。需要Python及Vivado/XSim 2025.2，可通过VIVADO_BIN指定工具路径。生成M1/8、N64、K512/4096确定性INT8×INT4数据和独立整数期望值；使用主系统4×4/TILE_K32，空缓存开始计时。旧/新仅替换memory_packet/bridge，计算核、当前调度及AXI内存服务条件相同。8字节总线单outstanding，固定读延迟8、写延迟4；逐字节检查每个262,144字节外存镜像，核对有用读取字节、写入和确认数相同。结果在build/round3_large，原始CSV/JSON区分内核接口微基准和存储路径；不提供板级、完整模型或tokens/s排名。
