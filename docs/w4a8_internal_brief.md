# W4A8 内部交流摘要

## 当前硬件

独立 w4a8_linear 已打通 packed INT4加载、A/B双缓冲、同步bank读与解包、4×4 MAC、group INT32 scratch、定点scale/64位合并及Q16.16输出背压；复用原mac_array/mac_pe，保留INT8/NPU基线。外存供数仅为TB模型，尚未连接旧NPU任务队列或真实DDR。

## 代表性任务如何流过硬件

Prefill M=4、N=12、K=96、group32：3个N tile，每tile有3个group、每group有4个K tile，共36个请求。每个完整请求传16权重字节+32激活字节+16scale字节。首次包READY后consumer计算，另bank加载下一包；每group跨4tile保留INT32 psum，组完成存16个psum并逐槽缩放到64位输出累加器。三组完成后输出16元素，接受后继续下个N tile，最后done。整个任务48输出、4608有效MAC，不需驻留完整矩阵。

## 正确性与周期

原INT8和NPU回归已复现；W4A8 114任务、1863输出、6456组psum逐项通过，两种阵列/group以及单缓冲对照。故障注入非零退出、计算中复位/输出背压复位恢复通过。B/C误差表在 w4a8_validation.md，包含非饱和与饱和用例，随机浮点样本不代表真实模型准确率。

| 4×4/group32任务 | 连续供数双缓冲 | 首延迟/带宽受限 | 随机暂停+背压 | 连续供数单缓冲 |
|---|---|---|---|---|
| Decode 1×13×96 | 2106 | 2734 | 3098 | 2776 |
| Prefill 4×12×96 | 2555 | 3651 | 4416 | 3334 |

实际Vivado 2025.2 / xcvu9p-flga2104-2L-e 临时评估part：综合 1671 LUT、1110 FF、22 DSP、1 RAMB18、1 RAMB36、128 LUTRAM、0 URAM、0 latch。16 DSP在PE，5在scale，1在有效MAC计数。A/B分布式RAM，psum/output BRAM。

OOC内部10ns约束 WNS +4.993 ns、WHS +0.011 ns，路由状态 {"routable_nets": 3316, "fully_routed_nets": 3316, "routing_errors": 0, "explicit_gaps": 1}；DRC边界及无I/O延迟限制详见验证报告。未做板级管脚/接口延迟约束或板上测量。

## 当前瓶颈与下一阶段

默认Prefill连续供数，RUN288/2555拍，等输入1417拍；1byte输入带宽、重复A/scale传输是首要限制。每group保存/scale共64拍，当前compute与scale串行。Decode空PE行导致低利用率。优先讨论：(1)宽burst接口与A/scale复用；(2)专门GEMV的N/K并行映射；(3)psum/scale解耦及W4A8任务地址队列。理由及候选实验见 w4a8_next_steps.md。

理论16 MAC/拍、100MHz下1.6GMAC/s只是阵列上限；上表来自确定性供数模型，未测真实DDR/板上性能。VCS未发现且未运行，提供可配置脚本。AWQ/zero-point/完整LLM均不在当前交付范围。
