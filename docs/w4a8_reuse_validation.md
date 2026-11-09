# 激活跨 N tile 复用：验证与性能报告

本轮新增 w4a8_reuse；原 w4a8_post 及 INT8/NPU 实现保留。Windows PowerShell 5.1，Python 3.13.5，Vivado/XSim 2025.2 build6299465；临时评估 part xcvu9p-flga2104-2L-e，板卡/最终封装和速度等级未确认。

## 实际验证

| 配置 | 阵列 | K tile/group | 总线字节 | A复用 | 输入双bank | 任务 | 输出 | psum/scale比较 | 复用读 | 缓存写 | epoch切换 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| reuse | 4×4 | 8/32 | 8 | 1 | 1 | 40 | 675 | 1683 | 7179 | 696 | 11 |
| no_reuse | 4×4 | 8/32 | 8 | 0 | 1 | 40 | 675 | 1683 | 0 | 0 | 0 |
| alt | 2×3 | 5/12 | 8 | 1 | 1 | 40 | 675 | 3738 | 10194 | 1268 | 43 |
| words | 4×4 | 19/32 | 8 | 1 | 1 | 40 | 675 | 1683 | 7179 | 851 | 11 |
| single | 4×4 | 8/32 | 8 | 1 | 0 | 40 | 675 | 1683 | 7179 | 693 | 11 |
| one | 1×1 | 8/32 | 8 | 1 | 1 | 40 | 675 | 1683 | 35787 | 664 | 77 |
| byte | 4×4 | 8/32 | 1 | 1 | 1 | 40 | 675 | 1683 | 7179 | 5129 | 11 |

合计 280 任务、4725 输出、13836 整组 psum 与缩放乘积比较。cache_hits/cache_writes/cache_switches为整个TB过程累计，包含被复位中止的尝试，不能当作单个成功任务统计。输出逐元素完全一致；每 RUN 拍有效行 A 与全局矩阵地址对应；每缓存读检查当前 epoch 已写入，缓存写仅允许首个 N tile，读写同地址禁止。旧基线源码哈希一致；A_REUSE=0 的全部40条 CSV（含周期及恢复任务）与上一阶段默认配置逐字段一致。

保留零/正负/INT4全部编码/边界/不同组scale/固定种子随机/矩形/尾块/跨tile/不完整group/GEMV/GEMM、连续任务、计算中/输出阻塞/scale流水中复位、输入持稳/输出背压、满psum队列恢复。新增2×3/tile5/group12与tile19验证非字对齐缓存地址，1×1验证输出累加依赖，单输入bank、1字节总线均实际仿真。每任务200000周期与全局20ms超时；失败fatal及无PASS由PowerShell转非零。故障探针：{"executed": true, "exit_code": 1}。

## 代表性任务：相同模式的对照

| 任务 | 模式 | 旧A字节 | 新A字节 | 旧beat | 新beat | 旧周期 | 新周期 | 周期减少 | 等输入 | RUN | RUN/post重叠 | 端到端MAC利用率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Decode 1×13×96 | 0 | 384 | 96 | 156 | 120 | 931 | 931 | 0.00% | 0 | 384 | 112 | 8.38% |
| Decode 1×13×96 | 1 | 384 | 96 | 156 | 120 | 1846 | 1559 | 15.55% | 628 | 384 | 76 | 5.00% |
| Decode 1×13×96 | 2 | 384 | 96 | 156 | 120 | 1056 | 1018 | 3.60% | 58 | 384 | 135 | 7.66% |
| Prefill 4×12×96 | 0 | 1152 | 384 | 234 | 138 | 775 | 775 | 0.00% | 0 | 288 | 84 | 37.16% |
| Prefill 4×12×96 | 1 | 1152 | 384 | 234 | 138 | 2724 | 1772 | 34.95% | 997 | 288 | 32 | 16.25% |
| Prefill 4×12×96 | 2 | 1152 | 384 | 234 | 138 | 1029 | 920 | 10.59% | 105 | 288 | 90 | 31.30% |

模式0连续供数；模式1每请求首数据延迟5拍，8物理字节beat后等待7+4拍（每8字节burst gap4），padding计预算；模式2固定种子LFSR及周期输入/输出/post暂停。模式2策略相同，但任务周期改变后绝对ticks相位也改变，单次周期差不是严格逐拍相同的外部阻塞回放。模式0/1使用相同确定性供数规则。结果只代表此TB供数条件。

### 配置消融

| case | 配置 | 模式 | W字节 | A字节 | scale字节 | beat | padding | 周期 | 等输入 | post drain |
|---|---|---|---|---|---|---|---|---|---|---|
| 4 | reuse | 0 | 624 | 96 | 102 | 120 | 138 | 931 | 0 | 80 |
| 4 | reuse | 1 | 624 | 96 | 102 | 120 | 138 | 1559 | 628 | 80 |
| 4 | no_reuse | 0 | 624 | 384 | 102 | 156 | 138 | 931 | 0 | 80 |
| 4 | no_reuse | 1 | 624 | 384 | 102 | 156 | 138 | 1846 | 915 | 80 |
| 4 | words | 0 | 663 | 96 | 102 | 144 | 291 | 883 | 0 | 80 |
| 4 | words | 1 | 663 | 96 | 102 | 144 | 291 | 1721 | 838 | 80 |
| 4 | single | 0 | 624 | 96 | 102 | 120 | 138 | 1087 | 156 | 80 |
| 4 | single | 1 | 624 | 96 | 102 | 120 | 138 | 2070 | 1139 | 80 |
| 4 | one | 0 | 624 | 96 | 156 | 246 | 1092 | 1797 | 2 | 65 |
| 4 | one | 1 | 624 | 96 | 156 | 246 | 1092 | 2733 | 938 | 65 |
| 4 | byte | 0 | 624 | 96 | 102 | 822 | 0 | 1270 | 339 | 80 |
| 4 | byte | 1 | 624 | 96 | 102 | 822 | 0 | 1650 | 719 | 80 |
| 5 | reuse | 0 | 576 | 384 | 144 | 138 | 0 | 775 | 0 | 60 |
| 5 | reuse | 1 | 576 | 384 | 144 | 138 | 0 | 1772 | 997 | 60 |
| 5 | no_reuse | 0 | 576 | 1152 | 144 | 234 | 0 | 775 | 0 | 60 |
| 5 | no_reuse | 1 | 576 | 1152 | 144 | 234 | 0 | 2724 | 1949 | 60 |
| 5 | words | 0 | 612 | 384 | 144 | 168 | 204 | 742 | 3 | 60 |
| 5 | words | 1 | 612 | 384 | 144 | 168 | 204 | 2035 | 1296 | 60 |
| 5 | single | 0 | 576 | 384 | 144 | 138 | 0 | 936 | 161 | 60 |
| 5 | single | 1 | 576 | 384 | 144 | 138 | 0 | 2197 | 1422 | 60 |
| 5 | one | 0 | 2304 | 384 | 576 | 912 | 4032 | 6633 | 8 | 240 |
| 5 | one | 1 | 2304 | 384 | 576 | 912 | 4032 | 10125 | 3500 | 240 |
| 5 | byte | 0 | 576 | 384 | 144 | 1104 | 0 | 1452 | 677 | 60 |
| 5 | byte | 1 | 576 | 384 | 144 | 1104 | 0 | 1968 | 1193 | 60 |

所有任务完整CSV见 build/sim_w4a8_reuse_*/results.csv。缓存不改变 W/scale 传输量、算法有效 MAC 和 RUN 周期；有效 A 字节恒为 M×K，不再乘 N tile 数。sx 暂仍跨 N 重传。计数器、group流水、数值合同与上一阶段一致，定义见 w4a8_post_architecture.md。闭式总周期审计每条记录通过：固定开销=2RC×输出tile数+2×请求tile数+(RC+2)×group数+2MN+1；总周期=固定开销+RUN+等输入+等输出+psum满等待+post drain。加载/post重叠是子集不能重复相加。默认16 MAC/拍，100MHz约束下1.6GMAC/s只是理论峰值。

## 数值三层比较

A：RTL对位精确模型逐输出/组psum/缩放乘积完全一致。B/C使用与上一阶段同一向量，缓存不改变量化算法。以下为合成 Prefill 随机浮点用例，不是模型准确率：

~~~json
[
  {
    "group": 32,
    "B_fixed_vs_float_quant": {
      "max_abs": 0.05109154650252634,
      "rmse": 0.019093045557878913,
      "relative_l2": 0.002615751865476656
    },
    "C_quant_vs_original": {
      "max_abs": 1.090325315290461,
      "rmse": 0.5346870330066962,
      "relative_l2": 0.07526511432999666
    }
  },
  {
    "group": 12,
    "B_fixed_vs_float_quant": {
      "max_abs": 0.06143314903843411,
      "rmse": 0.02226706334432327,
      "relative_l2": 0.0030782678070733443
    },
    "C_quant_vs_original": {
      "max_abs": 1.2255704191344172,
      "rmse": 0.5016227272295044,
      "relative_l2": 0.07061082387419813
    }
  }
]
~~~

## 实际 VU9P 综合及内部 OOC

| 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|
| 综合 | 2535.0 | 2006.0 | 22.0 | 2.0 | 5.0 | 160.0 | 0.0 | 6.217 | 0.071 |
| OOC | 2479.0 | 2006.0 | 22.0 | 2.0 | 5.0 | 160.0 | 0.0 | 4.673 | 0.015 |

默认激活缓存实际为四个512×64bit RAMB36E2，每bank使用32768/36864 bits（88.89%）；Y另占1 RAMB36E2、两组psum各1 RAMB18E2、W共160 LUTRAM。相对上一阶段2591LUT/3029FF，当前2535LUT/2006FF，新增4个RAMB36，DSP仍22（16PE、5个scale、1个统计）。只默认4×4/tile8/group32/A复用/双W bank实际综合。latch/blackbox为0，DSP映射见 dsp_mapping.txt，缓存/psum/Y/W实际存储映射见 ram_synth.rpt（不得将RTL数组直接称为BRAM）。10ns时钟及虚拟OOC时钟源仅作内部评估，未设置板级管脚/I/O delay。

~~~json
{
  "synthesis_timing": {
    "WNS_ns": 6.217,
    "TNS_ns": 0.0,
    "setup_failing_endpoints": 0,
    "WHS_ns": 0.071,
    "THS_ns": 0.0,
    "hold_failing_endpoints": 0,
    "checks": {
      "no_clock": 0,
      "constant_clock": 0,
      "pulse_width_clock": 0,
      "unconstrained_internal_endpoints": 0,
      "no_input_delay": 127,
      "no_output_delay": 743,
      "multiple_clock": 0,
      "generated_clocks": 0,
      "loops": 0,
      "partial_input_delay": 0,
      "partial_output_delay": 0,
      "latch_loops": 0
    },
    "scope": "OOC internal timing; external I/O delays unspecified"
  },
  "ooc": {
    "completed": true,
    "utilization": {
      "LUT": 2479.0,
      "logic_LUT": 2319.0,
      "LUTRAM": 160.0,
      "FF": 2006.0,
      "BRAM_tiles": 6.0,
      "RAMB18": 2.0,
      "RAMB36": 5.0,
      "URAM": 0.0,
      "DSP": 22.0
    },
    "timing": {
      "WNS_ns": 4.673,
      "TNS_ns": 0.0,
      "setup_failing_endpoints": 0,
      "WHS_ns": 0.015,
      "THS_ns": 0.0,
      "hold_failing_endpoints": 0,
      "checks": {
        "no_clock": 0,
        "constant_clock": 0,
        "pulse_width_clock": 0,
        "unconstrained_internal_endpoints": 0,
        "no_input_delay": 127,
        "no_output_delay": 743,
        "multiple_clock": 0,
        "generated_clocks": 0,
        "loops": 0,
        "partial_input_delay": 0,
        "partial_output_delay": 0,
        "latch_loops": 0
      },
      "scope": "OOC internal timing; external I/O delays unspecified"
    },
    "route_status": {
      "routable_nets": 5025,
      "fully_routed_nets": 5025,
      "routing_errors": 0,
      "explicit_gaps": 1
    },
    "design_state": "Partially Routed",
    "drc": [
      {
        "rule": "DPIP-2",
        "severity": "Warning",
        "description": "Input pipelining",
        "checks": 42
      },
      {
        "rule": "DPOP-3",
        "severity": "Warning",
        "description": "PREG Output pipelining",
        "checks": 2
      },
      {
        "rule": "DPOP-4",
        "severity": "Warning",
        "description": "MREG Output pipelining",
        "checks": 6
      },
      {
        "rule": "RTSTAT-10",
        "severity": "Warning",
        "description": "No routable loads",
        "checks": 1
      }
    ],
    "internal_target_met": true
  }
}
~~~

综合日志及其OOC警告完整列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_reuse.sv:236]
WARNING: [Synth 8-3917] design w4a8_reuse has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_reuse has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_reuse has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_reuse has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_reuse has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_reuse.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[34]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[34]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[19]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[19]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[16]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[16]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[18]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[18]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[17]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[17]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[23]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[23]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[36]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[36]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[37]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[37]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[21]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[21]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[20]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[20]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[35]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[35]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[39]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[39]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[32]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[32]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[38]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[38]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[51]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[51]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[52]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[52]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[55]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[55]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[50]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[50]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[48]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[48]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[49]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[49]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[53]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[53]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[54]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[54]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

## 范围与限制

已实现且验证：表中配置和任务，缓存生命周期/初始化/同步读/读写冲突保护；默认综合/OOC见上。已实现但未验证：最大M/N/K尺寸和其他参数组合；MAX_K=4096仅综合容量，并非本轮矩阵规模测试上限；测试向量K最大96。VCS编译/运行未运行，本机未发现安装，新脚本仅Bash语法检查。未来：双M缓存跨epoch预取、sx缓存、输出tile重叠、Decode专用映射、NPU描述符适配、DDR/DMA与完整Transformer。仍是广播外积阵列，没有邻接PE传递的脉动阵列。

单M epoch缓存禁止提前加载下一M tile，可能增加M切换等待；缓存按MAX_K分配，非整齐group/tile会产生padding，默认每行512×64bit，四行16KiB有效数据容量。最后word无效字节虽可存poison，但计算从不读取该范围。输入必须符合协商packet和keep合同；没有恶意输入包长度恢复协议。
