# K4096完整Q/K/V链验证

从项目根目录运行 `python experiments/round4_qkv_large/run_large.py`。由已验证的小尺寸整数参考和测试台生成可审计的大例：M1、N64、K4096，group32，两步连续token。使用1MiB有界内存、固定种子随机AXI延迟/背压，逐项检查Q/K/V量化和完整外存镜像，确认KV写确认后才执行Q/Attention。它是实际数值验证，不是板级或完整模型性能实验。

结果位于build/round4_qkv_large。原始reads/read_bytes/writes/acks从复位起累计；cycles为每条根任务的独立周期。每个步骤实际392次写入并全部确认。生成器、测试台、输入和当前RTL身份均记录SHA256。
