# 当前系统验证 / ABI v4

当前源码：22软件测试；16配置、365条完成记录、8,192,000字节完整比较。包含既有12配置和新增4种Q投影/量化/Attention配置（group32/3/1及32位地址），新链每种26条记录。

另有5种协议配置、4种独立存储配置共118完成记录、28组性能配对/56个完整任务。具体错误/复位/背压/访问范围覆盖和SHA256见[第三轮报告](system_round3.md)。

当前主系统10ns内部OOC：WNS +0.183ns、WHS +0.010ns，68,129条网络完整路由，错误0，无latch/blackbox。实际报告在build/project_v2/implementation。主系统project.py status通过。这不替代板级DDR/PCIe或模型验证，七类legacy严格审计未全量重跑。

历史验证页见history/system_validation_round1.md和history/system_validation_round2.md；当前数值/接口见projected_attention.md。
