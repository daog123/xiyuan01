# 4×4 / 8×8 脉动阵列：实际验证报告

新增 systolic_pe / systolic_array / w4a8_systolic，保留广播 w4a8_reuse；测试使用相同UQ4.12 scale与Q16.16输出合同。环境Windows PowerShell5.1、Python3.13.5、Vivado/XSim2025.2 Build6299465。VU9P临时评估part xcvu9p-flga2104-2L-e，板卡未确认。

## 已运行自检

| 配置 | 阵列 | K tile/group | 数据流 | 任务 | 输出 | group psum/scale比较 | 暂停检查 | 排空检查 | 排空中复位 |
|---|---|---|---|---|---|---|---|---|---|
| s4 | 4×4 | 8/32 | systolic | 50 | 1434 | 3960 | 1764 | 9099 | 1 |
| s8 | 8×8 | 8/32 | systolic | 50 | 1434 | 3960 | 1434 | 10701 | 1 |
| b4 | 4×4 | 8/32 | broadcast | 49 | 1407 | 3879 | 993 | 0 | 0 |
| b8 | 8×8 | 8/32 | broadcast | 49 | 1407 | 3879 | 525 | 0 | 0 |
| alt | 2×3 | 5/12 | systolic | 50 | 1434 | 9162 | 2879 | 18063 | 1 |
| words8 | 8×8 | 19/32 | systolic | 50 | 1434 | 3960 | 1038 | 5710 | 1 |
| single | 4×4 | 8/32 | systolic | 50 | 1434 | 3960 | 1794 | 9285 | 1 |
| one | 1×1 | 8/32 | systolic | 49 | 1407 | 3879 | 10615 | 0 | 0 |

合计397任务、11391输出、36639组psum及scaled乘积逐项完全一致。4×4/8×8独立单元分别逐PE逐推进拍比较数学历史模型，检查r+c错位、边界INT8/INT4、K1、零、尾块、暂停时PE和入口skew持稳、跨段保留sum与有在途token时复位。

集成覆盖既有12类数值用例，新增8×16×96满8×8 Prefill、1×17×96 Decode与9×11×67尾块。3供数模式、连续任务、busy start拒绝、输入/输出持稳、array/post分别暂停、双psum满队列、计算/输出/post流水/排空复位恢复。单元[{"size": 4, "groups": 5, "checks": 5034, "held": 23, "resets": 1}, {"size": 8, "groups": 5, "checks": 26650, "held": 23, "resets": 1}]。故障探针{"executed": true, "exit_code": 1}。

模式2新增array_pause，与历史模式2阻塞条件不同；b4模式0/1原12正常任务CSV逐字段复现原广播结果。数字正确性三层A/B/C沿用参考规格，额外用例误差见vector JSON；无真实模型质量结论。MAX_M/N64、MAX_K4096未全尺寸测试。单元1ms、集成20ms全局及每任务200000拍超时；fatal/PASS由脚本转非零。

## 数值误差三层

A为所有RTL/位精确输出、group psum和scaled乘积完全一致。B是编码定点scale对理想浮点量化scale，C是量化值对原始合成浮点矩阵；不是LLM准确率。代表性新增满8×8用例：

~~~json
[
  {
    "group": 32,
    "case": "prefill8",
    "saturated_outputs": 0,
    "B": {
      "max_abs": 0.04452783423641904,
      "rmse": 0.017140803655525273,
      "relative_l2": 0.002267804533039034
    },
    "C": {
      "max_abs": 1.2299735814750425,
      "rmse": 0.46316145827198885,
      "relative_l2": 0.06151432889611221
    }
  },
  {
    "group": 12,
    "case": "prefill8",
    "saturated_outputs": 0,
    "B": {
      "max_abs": 0.074878656883687,
      "rmse": 0.024628253102628356,
      "relative_l2": 0.003437000268059194
    },
    "C": {
      "max_abs": 1.1960047557540874,
      "rmse": 0.4451930084042991,
      "relative_l2": 0.06238003932703657
    }
  }
]
~~~

## 数值与阵列时序

每PE仍INT8×符号扩展INT4→signed16→signed32，整数sum按模2^32，group内跨K tile保留；group全部PE完成后交付两组snapshot，再乘sx/sw并累加signed64 Q24，输出shift8 ties-away舍入并饱和signed32 Q16.16。接口支持全阵列advance冻结，A/B/data/valid/skew/acc共同停止；group边界完整排空才clear或scale。每K tile排空D=ROWS+COLS−2，4×4为6拍，8×8为14拍，1×1为0拍。尾块本轮按物理阵列最大D排空，未缩短有效行列波前。

## 器件综合与内部OOC

| 配置 | 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | SRL | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|---|---|
| b4 | 综合 | 2621.0 | 2152.0 | 21.0 | 2.0 | 5.0 | 160 | 0 | 0.0 | 6.249 | 0.071 |
| b8 | 综合 | 3846.0 | 2924.0 | 69.0 | 2.0 | 9.0 | 320 | 0 | 0.0 | 6.3 | 0.071 |
| s4 | 综合 | 2697.0 | 2339.0 | 21.0 | 2.0 | 5.0 | 160 | 0 | 0.0 | 6.08 | 0.071 |
| s4 | OOC | 2636.0 | 2339.0 | 21.0 | 2.0 | 5.0 | 160 | 0.0 | 4.757 | 0.013 |
| s8 | 综合 | 4195.0 | 3813.0 | 69.0 | 2.0 | 9.0 | 320 | 44 | 0.0 | 5.739 | 0.071 |
| s8 | OOC | 4088.0 | 3813.0 | 69.0 | 2.0 | 9.0 | 320 | 0.0 | 4.558 | 0.011 |

本轮b4/b8只执行综合，OOC未运行；s4/s8执行综合及内部OOC，是否完成以上述实际标记为准。全部EDA使用10ns评估约束，虚拟BUFGCE_X0Y0。缓存每行512×64bit实际RAMB36、W为分布式RAM；8×8脉动的364个LUT memory实际拆为320 LUTRAM和44 SRL16E，表中已分列，不能全部称为RAM；两组psum和Y以各报告为准。primitive_counts检查latch/blackbox=0，dsp_mapping逐个实例确认MAC阵列DSP数量=ROWS×COLS。无板级管脚/I/O延迟；OOC边界未partial-route的外部port不作时序结论。只内部register path范围；不能宣称板上频率、DDR吞吐或加速比。

### b4 工具证据

~~~json
{
  "name": "b4",
  "size": 4,
  "systolic": 0,
  "synthesis_completed": true,
  "ooc_completed": false,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 2621.0,
    "logic_LUT": 2461.0,
    "FF": 2152.0,
    "BRAM_tiles": 6.0,
    "RAMB18": 2.0,
    "RAMB36": 5.0,
    "URAM": 0.0,
    "DSP": 21.0,
    "LUT_memory": 160.0,
    "LUTRAM": 160,
    "SRL": 0
  },
  "timing": {
    "WNS_ns": 6.249,
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
      "no_input_delay": 128,
      "no_output_delay": 839,
      "multiple_clock": 0,
      "generated_clocks": 0,
      "loops": 0,
      "partial_input_delay": 0,
      "partial_output_delay": 0,
      "latch_loops": 0
    },
    "scope": "OOC internal timing; external I/O delays unspecified"
  },
  "activation_cache_mapping": [
    [
      "activation_cache.row_bank[0].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[1].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[2].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[3].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ]
  ]
}
~~~

完整日志warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

### b8 工具证据

~~~json
{
  "name": "b8",
  "size": 8,
  "systolic": 0,
  "synthesis_completed": true,
  "ooc_completed": false,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 3846.0,
    "logic_LUT": 3526.0,
    "FF": 2924.0,
    "BRAM_tiles": 10.0,
    "RAMB18": 2.0,
    "RAMB36": 9.0,
    "URAM": 0.0,
    "DSP": 69.0,
    "LUT_memory": 320.0,
    "LUTRAM": 320,
    "SRL": 0
  },
  "timing": {
    "WNS_ns": 6.3,
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
      "no_input_delay": 128,
      "no_output_delay": 837,
      "multiple_clock": 0,
      "generated_clocks": 0,
      "loops": 0,
      "partial_input_delay": 0,
      "partial_output_delay": 0,
      "latch_loops": 0
    },
    "scope": "OOC internal timing; external I/O delays unspecified"
  },
  "activation_cache_mapping": [
    [
      "activation_cache.row_bank[0].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[1].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[2].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[3].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[4].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[5].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[6].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[7].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ]
  ]
}
~~~

完整日志warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[11] driven by constant 0
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

### s4 工具证据

~~~json
{
  "name": "s4",
  "size": 4,
  "systolic": 1,
  "synthesis_completed": true,
  "ooc_completed": true,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 2697.0,
    "logic_LUT": 2537.0,
    "FF": 2339.0,
    "BRAM_tiles": 6.0,
    "RAMB18": 2.0,
    "RAMB36": 5.0,
    "URAM": 0.0,
    "DSP": 21.0,
    "LUT_memory": 160.0,
    "LUTRAM": 160,
    "SRL": 0
  },
  "timing": {
    "WNS_ns": 6.08,
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
      "no_input_delay": 128,
      "no_output_delay": 871,
      "multiple_clock": 0,
      "generated_clocks": 0,
      "loops": 0,
      "partial_input_delay": 0,
      "partial_output_delay": 0,
      "latch_loops": 0
    },
    "scope": "OOC internal timing; external I/O delays unspecified"
  },
  "activation_cache_mapping": [
    [
      "activation_cache.row_bank[0].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[1].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[2].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[3].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ]
  ],
  "ooc_utilization": {
    "LUT": 2636.0,
    "logic_LUT": 2476.0,
    "FF": 2339.0,
    "BRAM_tiles": 6.0,
    "RAMB18": 2.0,
    "RAMB36": 5.0,
    "URAM": 0.0,
    "DSP": 21.0,
    "LUT_memory": 160.0,
    "LUTRAM": 160,
    "SRL": 0
  },
  "ooc_timing": {
    "WNS_ns": 4.757,
    "TNS_ns": 0.0,
    "setup_failing_endpoints": 0,
    "WHS_ns": 0.013,
    "THS_ns": 0.0,
    "hold_failing_endpoints": 0,
    "checks": {
      "no_clock": 0,
      "constant_clock": 0,
      "pulse_width_clock": 0,
      "unconstrained_internal_endpoints": 0,
      "no_input_delay": 128,
      "no_output_delay": 871,
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
    "routable_nets": 5569,
    "fully_routed_nets": 5569,
    "routing_errors": 0,
    "explicit_gaps": 1
  },
  "drc": [
    {
      "rule": "DPIP-2",
      "severity": "Warning",
      "description": "Input pipelining",
      "checks": 10
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
      "checks": 5
    },
    {
      "rule": "RTSTAT-10",
      "severity": "Warning",
      "description": "No routable loads",
      "checks": 1
    }
  ],
  "design_state": "Partially Routed",
  "internal_target_met": true
}
~~~

完整日志warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_systolic.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[21]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[21]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[17]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[17]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[20]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[20]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[18]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[18]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[19]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[19]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

### s8 工具证据

~~~json
{
  "name": "s8",
  "size": 8,
  "systolic": 1,
  "synthesis_completed": true,
  "ooc_completed": true,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 4195.0,
    "logic_LUT": 3831.0,
    "FF": 3813.0,
    "BRAM_tiles": 10.0,
    "RAMB18": 2.0,
    "RAMB36": 9.0,
    "URAM": 0.0,
    "DSP": 69.0,
    "LUT_memory": 364.0,
    "LUTRAM": 320,
    "SRL": 44
  },
  "timing": {
    "WNS_ns": 5.739,
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
      "no_input_delay": 128,
      "no_output_delay": 869,
      "multiple_clock": 0,
      "generated_clocks": 0,
      "loops": 0,
      "partial_input_delay": 0,
      "partial_output_delay": 0,
      "latch_loops": 0
    },
    "scope": "OOC internal timing; external I/O delays unspecified"
  },
  "activation_cache_mapping": [
    [
      "activation_cache.row_bank[0].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[1].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[2].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[3].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[4].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[5].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[6].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ],
    [
      "activation_cache.row_bank[7].ram/mem_reg",
      "RAMB36E2",
      "36864",
      "32768"
    ]
  ],
  "ooc_utilization": {
    "LUT": 4088.0,
    "logic_LUT": 3724.0,
    "FF": 3813.0,
    "BRAM_tiles": 10.0,
    "RAMB18": 2.0,
    "RAMB36": 9.0,
    "URAM": 0.0,
    "DSP": 69.0,
    "LUT_memory": 364.0,
    "LUTRAM": 320,
    "SRL": 44
  },
  "ooc_timing": {
    "WNS_ns": 4.558,
    "TNS_ns": 0.0,
    "setup_failing_endpoints": 0,
    "WHS_ns": 0.011,
    "THS_ns": 0.0,
    "hold_failing_endpoints": 0,
    "checks": {
      "no_clock": 0,
      "constant_clock": 0,
      "pulse_width_clock": 0,
      "unconstrained_internal_endpoints": 0,
      "no_input_delay": 128,
      "no_output_delay": 869,
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
    "routable_nets": 9549,
    "fully_routed_nets": 9549,
    "routing_errors": 0,
    "explicit_gaps": 1
  },
  "drc": [
    {
      "rule": "DPIP-2",
      "severity": "Warning",
      "description": "Input pipelining",
      "checks": 10
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
      "checks": 5
    },
    {
      "rule": "RTSTAT-10",
      "severity": "Warning",
      "description": "No routable loads",
      "checks": 1
    }
  ],
  "design_state": "Partially Routed",
  "internal_target_met": true
}
~~~

完整日志warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_systolic.sv:266]
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_systolic has port req_group[11] driven by constant 0
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "array_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "array_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "post_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "post_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[32]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[32]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

## 状态与限制

已实现且验证：表中配置/工作负载及两尺寸单元；EDA完成情况如上。未验证：未列参数、最大维度、VCS编译运行；新增VCS入口已通过WSL Bash -n语法检查，Windows/WSL未发现VCS，未安装或申请许可证。未来：group连续注入后仅排空一次、输出tile流水、psum并行保存、Decode专用映射、统一NPU描述符/DDR。此次每K tile都排空且保持operand bank，是明确保守原型，不宣称已经优化的高吞吐脉动引擎；未改输出tile顺序。

源/命令/CSV在build/sim_w4a8_systolic_*与build/sim_systolic_unit*，EDA在build/synth_w4a8_systolic_*，完整汇总build/w4a8_systolic_summary.json。
