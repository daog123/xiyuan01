> 第七轮当前验证与物理结果见[system_round7.md](system_round7.md)，汇总入口为scripts/audit_round7.py。以下旧轮次数字保留为历史。

> 第六轮历史验证与物理结果见[system_round6.md](system_round6.md)，汇总入口为scripts/audit_round6.py。以下旧轮次数字保留为历史记录。

# 当前验证 / ABI v5 / llm_graph_top

软件25项；主系统20配置、489完成、10,813,440字节完整比较。新增4种Q/K/V整链配置各31条记录。独立M1/N64/K4096两步图实际通过，另比较2,097,152字节。

12组FFN与12组LINEAR配对、48任务通过；5种协议配置、4种独立存储配置/118完成通过。错误、提交恢复、背压、复位和负例范围见[第四轮报告](system_round4.md)。

当前10ns内部OOC WNS +0.143ns、WHS +0.011ns，84,169条网络全部路由、错误0。无latch/blackbox，当前源码审计通过。原七类legacy严格审计未全量重跑，板级/模型验证仍未完成。
