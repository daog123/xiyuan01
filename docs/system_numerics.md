# 统一系统数值合同

## 线性与 FFN

W4A8 沿用原项目的 signed INT8 激活、低 nibble 在前的 signed INT4 权重、per-group UQ4.12 sx/sw、INT32 group sum、signed64 合并、Q16.16 舍入及 INT32 饱和。FFN 沿用 `ffn_numerics.md` 的 SiLU LUT 插值、SwiGLU 和动态 absmax requant。

当前W4A8和向量算子的数值合同保持不变；映射、波前、后处理和存储结构已按第二/三轮改进，Q自动量化复用原requant_dynamic/group。系统参考模型独立生成输入、gate、up、qx、sx、down.Y 和完整预期外存镜像，比较包括输入、padding 和保护区。

## Attention

每个 query 的 Q、K、V 为 signed INT8；Q/K/V group scale 均为 UQ4.12。score_scale 为 UQ4.12，调用方通常编码 1/sqrt(dimension)。score_scale=0 拒绝。

对 token t、group g：

```text
dot[t,g] = sum(q[i] * k[t,i])
raw_score[t] = sum(dot[t,g] * sq[g] * sk[t,g])          # Q24
score[t] = round_away(round_away(raw_score[t], 8) * score_scale, 12)
```

分数在 64 位通路保留，避免大幅度 Q/K 下的中间 INT32 截断破坏相对分数。round_away 为最近舍入、恰好半数时远离零；中间两次舍入与参考模型完全一致。支持范围内的数值上界使用 MAX_DIM<=64、MAX_TOKENS<=16 和 16 位 scale 推导，signed64 累加足够。

稳定 Softmax：

```text
delta = max(score) - score[t]
index = min(256, (delta + 2048) >> 12)                 # nearest 1/16
exp_q16[t] = round(exp(-index/16) * 65536)             # unsigned 17-bit
sum_exp = sum(exp_q16)
prob_q16[t] = floor(((exp_q16[t] << 16) + sum_exp//2) / sum_exp)
```

指数 LUT 覆盖 [-16,0]；最大项固定为 65536，sum_exp 不会为零。归一化采用 34 拍逐位无符号除法，不形成单拍宽组合除法器。每项概率独立舍入，所以概率整数和可能与 65536 有少量差异。

AV 输出：

```text
raw_y[i] = sum(prob_q16[t] * v[t,i] * sv[t, i//GROUP_SIZE]) # Q28
y[i] = saturate_int32(round_away(raw_y[i], 12))             # Q16.16
```

V×scale、乘概率和累加分为不同阶段。Y 按 little-endian signed32 写回。硬件对整数参考要求逐位一致；近似 Softmax 与独立浮点参考另外报告误差。该误差证据来自合成测试向量，不代表真实模型精度。

参考入口为 `model/attention_reference.py`。覆盖单 token、逐步扩大的前缀、尾 group、不同 per-token/group scale、零 Q 和大幅度 Q。`build/attention_v2/vectors/reference.json` 保留全部概率误差与输出误差，不仅列出通过标记。

## ABI v4投影Q自动量化

新增Q16.16输入和自动Q投影链复用原requant_dynamic/group，完整group确定scale后再输出；定义、clipping及错误边界见[projected_attention.md](projected_attention.md)。W4A8和Attention的原有整数数值合同不变。

## ABI v5的K/V量化

自动K/V路径复用Q16.16完整group动态量化定义，缓存输出INT8和UQ4.12后按K/V/SK/SV顺序追加。没有增加RoPE或改变矩阵、SwiGLU、Softmax数值合同；恢复语义见qkv_attention.md。
