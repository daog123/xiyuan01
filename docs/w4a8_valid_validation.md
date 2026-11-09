# W4A8 有效槽：实际验证

由当前源码SHA、独立坐标/流量/周期模型、SV自检及实际Vivado产物生成；原数学golden未改。完整证据 [w4a8_valid_delivery.json](../build/w4a8_valid_delivery.json)。

| 配置 | 任务 | 输出 | psum/scale检查 | 自检项 |
|---|---:|---:|---:|---:|
| v4 | 52 | 1488 | 4122 | 1722989 |
| v8 | 52 | 1488 | 4122 | 4679238 |
| alt | 52 | 1488 | 9486 | 2278416 |
| one | 49 | 1407 | 3879 | 1984029 |
| single | 52 | 1488 | 4122 | 2156775 |
| words8 | 52 | 1488 | 4122 | 4784622 |
| base4 | 52 | 1488 | 4122 | 1955622 |
| base8 | 52 | 1488 | 4122 | 7547667 |

包含逐PE数学历史与冻结、单周期同步psum/Y读写、宽累加RAW、双snapshot所有权、pipeline暂停、输出背压、连续任务、输入饥饿与复位；每任务200000拍、全局20ms超时。
VALID_ONLY=0的base4/base8所有任务CSV字段与原g4/g8逐项一致。有效槽版本数据/scale/packet/MAC/推进/排空不变；只改变slot访问及由此带来的调度等待。

| 探针 | 实际退出码 |
|---|---:|
| negative | 1 |
| timeout | 1 |

| 阵列 | 阶段 | LUT | FF | DSP | RAMB36 | RAMB18 | WNS ns | WHS ns |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 4 | 综合 | 2921 | 2436 | 21 | 5 | 2 | 5.598 | 0.071 |
| 4 | OOC | 2851 | 2436 | 21 | 5 | 2 | 4.482 | 0.015 |
| 8 | 综合 | 4592 | 3906 | 69 | 9 | 2 | 5.376 | 0.071 |
| 8 | OOC | 4461 | 3906 | 69 | 9 | 2 | 3.872 | 0.011 |

4×4：latch/blackbox=0；警告 178 条，代码 DRC 23-814, Route 35-198, Synth 8-3332, Synth 8-3917, Synth 8-6014；RAM/DSP细节见报告。
路由 {"routable": 5853, "fully_routed": 5853, "errors": 0, "gaps": 1}；内部setup/hold失败端点0。

8×8：latch/blackbox=0；警告 116 条，代码 DRC 23-814, Route 35-198, Synth 8-3917, Synth 8-6014；RAM/DSP细节见报告。
路由 {"routable": 10345, "fully_routed": 10345, "errors": 0, "gaps": 1}；内部setup/hold失败端点0。

Vivado2025.2，临时xcvu9p-flga2104-2L-e，10ns内部OOC，无板级pin/IO delay，未证明板上频率。
有效槽只减少访问/后处理次数，RAM容量仍为最大RC；物理地址和原数据宽度保持。未加入输出FIFO、tile双缓冲或改W4 decode。
