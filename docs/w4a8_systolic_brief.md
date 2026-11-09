# 4×4 / 8×8 脉动原型：内部交流摘要

真正实现相邻PE传递A/B和valid：入口A延迟r、B延迟c，PE(r,c)在注入后r+c推进拍完成对应乘加；全局array_pause冻结skew、链路、acc与读地址。W4A8缓存、group scale与输出合同保留，末token排空后才切bank/保存group。

实际397任务/11391输出/36639组psum与scaled比较通过；4×4/8×8独立数学波前单元通过。

| case | 配置 | 连续周期 | RUN | 排空 | 等输入 |
|---|---|---|---|---|---|
| 4 | b4 | 931 | 384 | 0 | 0 |
| 4 | s4 | 1219 | 384 | 288 | 0 |
| 4 | b8 | 1055 | 192 | 0 | 0 |
| 4 | s8 | 1391 | 192 | 336 | 0 |
| 5 | b4 | 775 | 288 | 0 | 0 |
| 5 | s4 | 991 | 288 | 216 | 0 |
| 5 | b8 | 1131 | 192 | 0 | 6 |
| 5 | s8 | 1461 | 192 | 336 | 0 |
| 12 | b4 | 2065 | 768 | 0 | 0 |
| 12 | s4 | 2641 | 768 | 576 | 0 |
| 12 | b8 | 1319 | 192 | 0 | 34 |
| 12 | s8 | 1621 | 192 | 336 | 0 |

VU9P临时part、10ns内部评估；资源为实际综合，WNS/WHS仅实际OOC：

| 配置 | LUT | FF | DSP | RAMB36 | RAMB18 | OOC WNS ns | OOC WHS ns |
|---|---|---|---|---|---|---|---|
| b4 | 2621 | 2152 | 21 | 5 | 2 | 未运行/完成 | 未运行/完成 |
| b8 | 3846 | 2924 | 69 | 9 | 2 | 未运行/完成 | 未运行/完成 |
| s4 | 2697 | 2339 | 21 | 5 | 2 | 4.757 | 0.013 |
| s8 | 4195 | 3813 | 69 | 9 | 2 | 4.558 | 0.011 |

当前瓶颈证据：每tile排空6/14推进拍，保存psum与输出按RC逐槽；因此脉动功能正确不代表此版本更快。4×4/8×8同尺寸广播对照保留，8×8满阵列/Decode/尾块都有实测。EDA完成状态：[{"name": "b4", "synthesis_completed": true, "ooc_completed": false}, {"name": "b8", "synthesis_completed": true, "ooc_completed": false}, {"name": "s4", "synthesis_completed": true, "ooc_completed": true}, {"name": "s8", "synthesis_completed": true, "ooc_completed": true}]。

下一轮优先group内跨tile连续波前并仅group末排空，然后优化psum/输出tile保存与重叠；Decode仍需N/K专用映射。当前没有真实DDR、完整模型或W4A8 NPU队列适配；VCS未运行。详见架构、验证与性能报告。
