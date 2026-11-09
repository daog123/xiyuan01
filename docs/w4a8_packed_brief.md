# 列对权重打包：内部交流摘要

新增w4a8_packed，64bit beat将两个输出列各4个packed权重字节写入两个独立32bit bank；每bank仍一写端口。原数值、计算、group scale与双缓冲控制保持。六配置228任务/3726输出/11019group psum全部通过，奇列/奇K/多word、非连续keep、暂停、背压、复位均覆盖。

| 任务 | 模式 | 旧周期 | 新周期 | 周期减少 | 旧物理字节 | 新物理字节 |
|---|---|---|---|---|---|---|
| Decode | 0 | 1415 | 1415 | 0.00% | 1824 | 1248 |
| Decode | 1 | 2938 | 2306 | 21.51% | 1824 | 1248 |
| Decode | 2 | 1601 | 1505 | 6.00% | 1824 | 1248 |
| Prefill | 0 | 1147 | 1138 | 0.78% | 2448 | 1872 |
| Prefill | 1 | 3615 | 2823 | 21.91% | 2448 | 1872 |
| Prefill | 2 | 1443 | 1361 | 5.68% | 2448 | 1872 |

Prefill 4×12×96共36请求：权重72beat、激活144beat、scale18beat，总234beat/1872字节，无padding，达到之前布局推算目标。外存源矩阵仍列优先，列对打包由TB供数模型完成；实际DMA需实现同一packet合同。Decode有奇列及小scale段，仍存在padding。供数模式代表可复现模型，不是DDR/板上性能。

默认综合2324LUT、2335FF、22DSP、1RAMB18、1RAMB36、160LUTRAM、0URAM、0latch。存储映射见实际RAM报告。

OOC内部10ns WNS+4.453ns/WHS+0.002ns；{'routable_nets': 4817, 'fully_routed_nets': 4817, 'routing_errors': 0, 'explicit_gaps': 1}。接口未设板级/父级延迟，边界警告详见报告。

下一步：连续供数仍由group保存/scale及控制主导，应实现两组psum buffer与独立scale流水；带宽进一步优化考虑A跨N tile复用。Decode有效行少，脉动阵列应作为同接口对照实验，不保证自然提高GEMV利用率。NPU队列集成、DDR/DMA与完整模型仍是后续工作。
