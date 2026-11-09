# 独立 group 后处理：内部交流摘要

新增w4a8_post：两组INT32 psum snapshot、独立scale流水、可控post_pause，捕获scale和坐标后释放operand bank。已运行280任务/4725输出/13836group psum及缩放乘积逐项比较；七配置含串行/流水/重叠消融、备用阵列、单输入bank和1×1地址依赖。

| 任务 | 模式 | 旧列对周期 | 新周期 | RUN/post重叠 | drain |
|---|---|---|---|---|---|
| Decode | 0 | 1415 | 931 | 112 | 80 |
| Decode | 1 | 2306 | 1846 | 64 | 80 |
| Decode | 2 | 1505 | 1056 | 121 | 108 |
| Prefill | 0 | 1138 | 775 | 84 | 60 |
| Prefill | 1 | 2823 | 2724 | 0 | 60 |
| Prefill | 2 | 1361 | 1029 | 73 | 72 |

代表性Prefill：36输入请求与234beat保持不变，9group各保存16psum，再交给另一controller缩放合并。每group16个slot流水18enabled拍，累计144次issue/retire。末group写回后才输出当前N tile。总775周期、RUN288、等输入0、末组drain60。冻结后处理使两bank占满，计算保持未保存psum等待；恢复与流水中途复位已验证。

默认VU9P临时part综合：2591 LUT/3029 FF/22 DSP/2 RAMB18/1 RAMB36/160 LUTRAM，0URAM/0latch。

OOC10ns内部WNS+4.401ns/WHS+0.010ns；{'routable_nets': 5821, 'fully_routed_nets': 5821, 'routing_errors': 0, 'explicit_gaps': 1}，DRC/I/O边界见报告，不能宣称板上频率。

下一步应依据剩余周期/带宽对照讨论A复用与更长K tile、输出tile层重叠、Decode N/K映射及NPU描述符适配；脉动阵列需同接口对照测量。当前仍广播阵列，无DDR/DMA/完整模型。模式2新增post暂停，旧版对照条件不同；不宣称DDR或板上性能。
