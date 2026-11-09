# 激活跨 N tile 复用：内部交流摘要

当前 w4a8_reuse 实现 per-row 同步全K激活缓存、packed INT4双权重Buffer、广播MAC、双组psum、独立定点scale流水与背压输出。新增缓存复用协议 req_activation；已验证 280 任务/4725 输出/13836 组psum与scaled乘积。

代表性4×12×96 Prefill：第一个N tile加载384字节A并写四个行缓存，计算36个tile请求中的首12个；后两个N tile从相同缓存读取A，仅加载W和scale。总A由1152降到384字节，beat 234→138；带宽受限周期 2724→1772，等输入 1949→997。位精确数值不变，RUN仍288拍。

实际默认综合：2535 LUT/2006 FF/22 DSP/2 RAMB18/5 RAMB36；临时VU9P part。

10ns内部OOC：WNS +4.673ns、WHS +0.015ns；路由/DRC边界见验证报告，不宣称板上频率。

瓶颈随供数条件不同：连续供数本来不等输入，A复用主要降低字节量；限带宽仍有权重/scale加载和串行tile边界开销。下一步优先比较输出tile流水/更长K tile，再讨论Decode行利用率与NPU任务描述符；M epoch预取需增加第二套缓存并测收益，不能仅扩大阵列。无真实DDR/完整模型，VCS未运行。
