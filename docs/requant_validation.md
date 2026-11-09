# Requant 最小基线：实际工具验证

本报告由 scripts/summarize_requant.py 根据当前源码身份、参考模型、XSim 和 Vivado 日志生成。
数值与接口见 [数值合同](requant_numerics.md)、[接口](requant_interface.md)。

参考模型已对所有非零 scale 编码完成 458745 次逐位除法/独立整数 oracle 比较。

| GROUP_SIZE | 成功组 | 输出 | 自检项 | 拒绝描述符 | 复位 | 背压持稳检查 | 最小输出接受延迟 | 最小 II |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 32 | 409 | 7161 | 952438 | 9 | 8 | 54709 | 34 | 35 |
| 12 | 389 | 2901 | 418235 | 9 | 8 | 26590 | 34 | 35 |

无阻塞时 input handshake 后第 33 拍产生 out_valid，第 34 拍最早接受输出；同组输入 II=35。
包含整数边界、半值及相邻值、非二次幂 scale、最小 scale、全 scale 范围随机、group32/12 与尾组、最大 K 描述符、输入暂停、长输出背压、连续组、忙时描述符、活动复位。
每元素 100 拍等待检查和全局 20ms watchdog；独立 golden 错误与 watchdog 探针均实际非零退出。

| 探针 | 退出码 |
|---|---:|
| negative | 1 |
| timeout | 1 |

| GROUP_SIZE | 阶段 | LUT | FF | DSP | RAMB36 | RAMB18 | URAM | WNS/ns | WHS/ns |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 32 | 综合 | 258 | 188 | 0 | 0 | 0 | 0 | 7.51 | 0.083 |
| 32 | OOC | 253 | 188 | 0 | 0 | 0 | 0 | 7.047 | 0.043 |
| 12 | 综合 | 282 | 188 | 0 | 0 | 0 | 0 | 7.51 | 0.083 |
| 12 | OOC | 277 | 188 | 0 | 0 | 0 | 0 | 6.97 | 0.01 |

GROUP_SIZE=32：latch/blackbox=0；警告 105 条，代码：DRC 23-814, Route 35-198。
全部原文保存在 build/synth_requant_g32/warnings.txt、drc_*.rpt 和 check_timing_*.rpt。
内部可路由网络 342/342 已完成，routing errors=0，显式 OOC 边界 gap=1；DRC Checks found=0。

GROUP_SIZE=12：latch/blackbox=0；警告 105 条，代码：DRC 23-814, Route 35-198。
全部原文保存在 build/synth_requant_g12/warnings.txt、drc_*.rpt 和 check_timing_*.rpt。
内部可路由网络 371/371 已完成，routing errors=0，显式 OOC 边界 gap=1；DRC Checks found=0。

器件为本机核验可用的 xcvu9p-flga2104-2L-e，Vivado 2025.2，10ns 内部 OOC 时钟；板卡未确认，无 I/O delay/管脚约束。
外部端口无 delay 与 OOC 边界路由警告需要与内部 setup/hold 分开理解，结果不证明板上频率。
新模块不含 group RAM；仅单标量寄存器及逐位除法状态，DSP/RAM 映射以上述实测为准。
源码 SHA256、实际命令、逐组周期 CSV、primitive 数量、完整报告与 DCP 均位于 build；交付清单为 [requant_delivery.json](../build/requant_delivery.json)。
未运行：VCS、综合网表仿真、板上验证。未实现：动态 scale、tile 坐标组装、两层串联、FFN、真实 DMA/写回。
