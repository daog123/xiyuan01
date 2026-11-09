# 当前系统验证（2026-10-25 / ABI v3）

20 项软件测试通过；12 个系统配置共 261 条完成记录，逐字节比较 5,570,560 字节。包含原 4 种线性/FFN/混合配置、4 种流 Q Attention 和 4 种内存 Q Attention。

| 配置 | 完成记录 | 比较字节 |
|---|---:|---:|
| tb_accelerator | 18 | 458752 |
| tb_accelerator12 | 18 | 458752 |
| tb_accelerator32 | 18 | 458752 |
| tb_system_mixed | 11 | 独立数值/路由断言 |
| tb_attention | 19 | 458752 |
| tb_attention3 | 19 | 458752 |
| tb_attention32 | 19 | 458752 |
| tb_attention_default | 19 | 458752 |
| tb_attention_dma | 30 | 589824 |
| tb_attention_dma3 | 30 | 589824 |
| tb_attention_dma32 | 30 | 589824 |
| tb_attention_dma_default | 30 | 589824 |

内存 Q 模式增加容量/区域/回绕/别名/来源标志拒绝、忽略主机流、读写错误、held R/B、未完成 Q 读时的 DUT+fabric 复位和恢复。golden 破坏与强制超时探针仍能失败。

当前默认 llm_top：xcvu9p-flga2104-2L-e、10ns 内部时钟，最终 WNS=+0.159ns、WHS=+0.011ns；完整路由 58238，错误0，无 latch/blackbox。结构变化后完整重做放置布线；旧复用失败日志仍保存在 build/project_v2/implementation/failed_incremental_console.log。

这是 OOC 结果，尚未指定真实板卡引脚、外部 I/O、DDR/PCIe 或 CDC，不代表板级验证。Attention 仍有 dimension64/tokens16 的有界容量；完整 Q/K/V/O 图、RMSNorm、RoPE、残差与模型执行尚未实现。

独立整数/浮点参考、主系统当前源码审计、四份计算核实现和两个上游的实际实验见 [compute_advance.md](compute_advance.md)。本轮没有重新运行原七类 legacy 审计，不能用历史 legacy PASS 代替当前源码结果；本轮新系统、算子核、DMA 的当前证据均单独保存。
