# 小型 FFN：实际结构验证

依据当前源码SHA256、独立整数参考、XSim与Vivado产物生成。完整清单 [ffn_delivery.json](../build/ffn_delivery.json)。
综合顶层ffn_bridge包含坐标组装RAM、SiLU ROM、标量乘法和动态requant；三个W4A8投影及packet供数/回填在TB组合验证。

| 自检 | 完整任务/输出 | 复位中止 | 检查项 |
|---|---:|---:|---:|
| unit | 3787 | 7 | 66328 |
| protocol | 16 | 0 | 865 |
| ffn32 | 18 | 8 | 618653 |
| ffn12 | 18 | 8 | 593317 |

日志gate/up/product/qx/y包含被复位任务的已检查前缀；完整任务总数单列在delivery.completed_totals。
每配置18完整任务、8阶段复位恢复；group32/12，第一层group12/32；尾组/尾tile/M=1/M>1、零矩阵及故意饱和用例。
逐阶段检查gate/up Q16.16、三次投影group psum和scale乘积、SiLU/乘法、qx/sx/absmax/clip/sat、最终down输出。
协议自检覆盖6次非法描述符/坐标拒绝、8元素满容量、分支交错/反序坐标、两row尾组、每任务100拍持续背压。

| 探针 | 实际退出码 |
|---|---:|
| unit/negative | 1 |
| ffn32/negative | 1 |
| ffn32/timeout | 1 |

| group | 阶段 | LUT | FF | DSP | RAMB36 | RAMB18 | WNS ns | WHS ns |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| 32 | 综合 | 2576 | 1765 | 10 | 0 | 4 | 4.467 | 0.083 |
| 32 | OOC | 2530 | 1765 | 10 | 0 | 4 | 3.433 | 0.004 |

group32：latch/blackbox=0，警告105条，代码 DRC 23-814, Route 35-198。实际RAM、层次资源、原文警告和时序见synth_ffn_g*/报告。
路由 {"routable": 3509, "fully_routed": 3509, "errors": 0, "gaps": 1}；setup/hold失败端点0。
| 12 | 综合 | 2631 | 1764 | 10 | 0 | 4 | 4.467 | 0.083 |
| 12 | OOC | 2589 | 1764 | 10 | 0 | 4 | 3.571 | 0.007 |

group12：latch/blackbox=0，警告105条，代码 DRC 23-814, Route 35-198。实际RAM、层次资源、原文警告和时序见synth_ffn_g*/报告。
路由 {"routable": 3600, "fully_routed": 3600, "errors": 0, "gaps": 1}；setup/hold失败端点0。

Vivado2025.2，xcvu9p-flga2104-2L-e临时评估器件，10ns内部OOC，未指定板级pin/IO delay；不能视作板上频率证据。
SiLU网格65537点，最大绝对误差0.00268280104，阈值0.00270，含±8截断边界。

| group | case | 类型 | product最大误差 | product相对L2 | 最终最大误差 | 最终相对L2 |
|---|---:|---|---:|---:|---:|---:|
| 32 | 0 | normal | 0.00565973 | 5.7978e-05 | 0.844444 | 0.0132673 |
| 32 | 1 | normal | 0.00675614 | 4.5369e-05 | 2.2981 | 0.0055293 |
| 32 | 2 | normal | 0.0159491 | 9.09932e-05 | 4.91451 | 0.00817429 |
| 32 | 3 | zero | 0 | 0 | 0 | 0 |
| 32 | 4 | saturated | 4.1951e+12 | 1 | 1.59057e+13 | 1 |
| 12 | 0 | normal | 0.0176191 | 0.000111835 | 3.08216 | 0.0175052 |
| 12 | 1 | normal | 0.0130067 | 6.62894e-05 | 3.38248 | 0.0103122 |
| 12 | 2 | normal | 0.0314205 | 9.38593e-05 | 2.22584 | 0.00645545 |
| 12 | 3 | zero | 0 | 0 | 0 | 0 |
| 12 | 4 | saturated | 4.1951e+12 | 1 | 3.32371e+13 | 1 |

正常、零和故意饱和用例分别报告；RTL对整数golden误差0。浮点链采用已编码的输入/权重scale，不代表真实模型精度。
周期与中间状态计数保存在sim_ffn_ffn*/results.csv，本轮验证顺序执行，不要求重叠或性能收益。
未运行VCS、综合网表、板上与真实模型；统一任务系统、外存写回、Attention/KV、RMSNorm/RoPE/Softmax及输出FIFO仍为后续范围。
