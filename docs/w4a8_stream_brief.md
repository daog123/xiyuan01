# 宽供数 W4A8：内部交流摘要

本轮在原位精确W4A8通路上加入64bit beat/keep和组末一次scale加载，保留原顶层、数值合同及双缓冲所有权协议。原NPU任务队列仍未连接新顶层，真实DDR/DMA仍未实现。

七配置已通过：266任务、4347输出、12540group psum。包括字节/宽口、scale开关、单/双缓冲、group12备用阵列及tile19多word地址。输入padding填0xA5，尾掩码、暂停持稳、复位恢复、输出背压和流量均自检。

| 任务 | 配置 | 连续周期 | 同物理带宽预算周期 | scale字节 | beat | padding字节 |
|---|---|---|---|---|---|---|
| Decode | b1_s0 | 2106 | 2734 | 408 | 1416 | 0 |
| Decode | b1_s1 | 1916 | 2398 | 102 | 1110 | 0 |
| Decode | b8_s0 | 1415 | 3554 | 408 | 300 | 984 |
| Decode | b8_s1 | 1415 | 2938 | 102 | 228 | 714 |
| Prefill | b1_s0 | 2555 | 3651 | 576 | 2304 | 0 |
| Prefill | b1_s1 | 2283 | 3005 | 144 | 1872 | 0 |
| Prefill | b8_s0 | 1156 | 4263 | 576 | 360 | 576 |
| Prefill | b8_s1 | 1147 | 3615 | 144 | 306 | 576 |

代表性Prefill：36个K tile请求，27个非组末请求各8个beat、9个组末各10个beat，共306beat；W576+A1152+scale144有效字节，padding576，物理字节2448。源先装完整bank，再与另bank计算重叠。计算、group保存和scale时序未改变。

VU9P临时评估part综合：2141 LUT、3102 FF、22 DSP、1 RAMB18、1 RAMB36、0 LUTRAM、0URAM、0latch。默认宽RAM深度1，实际映射FF；较原字节口增加了寄存器及选择逻辑。

OOC内部10ns约束 WNS +4.509ns、WHS +0.007ns；路由/DRC限制见验证报告。没有板级管脚/接口延迟，不能承诺板上频率。

结论与讨论：连续供数Prefill等待输入从1417降到9拍，瓶颈转向group保存/scale与控制：1147总周期中，RUN288、WAIT9，其余850。576拍用于9group的保存/scale。等物理带宽预算下，64bit/scale-once的Decode比原byte慢，Prefill仅略有改善；优先解决跨列packing/padding及A复用，再解耦psum/scale流水。Decode空行利用率问题仍需独立映射实验。上述为指定仿真模型结果，不代表DDR/板上性能。
