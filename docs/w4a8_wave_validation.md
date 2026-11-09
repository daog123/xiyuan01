# Group 内连续脉动波前：实际验证报告

新增w4a8_wave，保留w4a8_systolic逐tile排空与广播基线；systolic_pe/array及数值向量未改。Windows PowerShell5.1、Python3.13.5、Vivado/XSim2025.2 build6299465。临时评估part xcvu9p-flga2104-2L-e，板卡/最终封装与速度等级未确认。

## 已运行验证

| 配置 | 阵列 | tile/group | group连续 | 任务 | 输出 | psum/scale比较 | 逐PE状态检查 | 接缝保持 | 旧bank重写 | 接缝复位/恢复 |
|---|---|---|---|---|---|---|---|---|---|---|
| g4 | 4×4 | 8/32 | 1 | 52 | 1488 | 4122 | 751024 | 10520 | 379 | 1/1 |
| g8 | 8×8 | 8/32 | 1 | 52 | 1488 | 4122 | 3395392 | 9852 | 195 | 1/1 |
| t4 | 4×4 | 8/32 | 0 | 50 | 1434 | 3960 | 789856 | 0 | 0 | 0/0 |
| t8 | 8×8 | 8/32 | 0 | 50 | 1434 | 3960 | 3558656 | 0 | 0 | 0/0 |
| alt | 2×3 | 5/12 | 1 | 52 | 1488 | 9486 | 677604 | 42542 | 1421 | 1/1 |
| words8 | 8×8 | 19/32 | 1 | 52 | 1488 | 4122 | 3298432 | 6125 | 62 | 1/1 |
| single | 4×4 | 8/32 | 1 | 52 | 1488 | 4122 | 942496 | 19011 | 1896 | 1/1 |
| one | 1×1 | 8/32 | 1 | 49 | 1407 | 3879 | 193700 | 42501 | 3382 | 0/0 |

合计409任务、11715输出、37773组psum和scaled乘积逐项一致。独立历史参考按逻辑advance编号存原始矩阵A/W，PE(r,c)取t−r−c的注入历史，逐PE逐拍比较fire与INT32 sum，包括WAIT_TILE/PRIME冻结。该参考不使用DUT乘积作为golden。

覆盖原15个数值/性能用例：零、边界、全部INT4编码、不同group scale、随机、非整块/不完整group、M=1/M>1、满8×8及尾块。额外强制输入饥饿使波前滞留在接缝20拍后恢复，以及接缝保持时复位恢复；原RUN/输出/post流水/末组排空复位、满psum队列、array/post/input暂停和输出背压均保留。旧bank重新LOADING写入时有在途波前的情况已覆盖。t4/t8所有CSV字段逐项复现上一轮s4/s8，包括暂停和恢复任务；原基线源码哈希一致。

每任务200000拍和全局20ms超时；自检失败fatal与脚本PASS检查转非零。自动错误golden探针：{"executed": true, "exit_code": 1}。只RTL仿真；综合网表仿真未运行。

## 数值三层

A：所有RTL输出/组psum/scaled乘积对位精确模型一致。B/C沿用相同向量，没有改量化算法；为合成浮点线性层，不是模型质量结论。满8×8 Prefill的实际参考误差：

~~~json
[
  {
    "group": 32,
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

## 器件资源与内部时序

| 配置 | 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | SRL | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|---|---|
| g4 | 综合 | 2686.0 | 2437.0 | 21.0 | 2.0 | 5.0 | 160 | 0 | 0.0 | 6.038 | 0.071 |
| g4 | OOC | 2631.0 | 2437.0 | 21.0 | 2.0 | 5.0 | 160 | 0 | 0.0 | 4.128 | 0.012 |
| g8 | 综合 | 4278.0 | 3908.0 | 69.0 | 2.0 | 9.0 | 320 | 44 | 0.0 | 5.446 | 0.071 |
| g8 | OOC | 4181.0 | 3908.0 | 69.0 | 2.0 | 9.0 | 320 | 44 | 0.0 | 4.129 | 0.01 |

默认tile8/group32、4×4/8×8 GROUP_STREAM=1运行器件工具，其他配置只仿真。两类RAM均为真实有限端口同步读，早释放bank没有新增RAM读写端口。每行512×64bit激活缓存实际RAMB36；W为LUTRAM；SRL单列，不能合计成RAM。DSP实例检查PE数量16/64，scale另计；latch/blackbox=0。10ns与虚拟BUFGCE_X0Y0仅内部OOC评估，无管脚/I/O delay；外部port不能据此报告板上频率。

### g4 实际工具证据

~~~json
{
  "name": "g4",
  "size": 4,
  "systolic": 1,
  "synthesis_completed": true,
  "ooc_completed": true,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 2686.0,
    "logic_LUT": 2526.0,
    "FF": 2437.0,
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
    "WNS_ns": 6.038,
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
      "no_output_delay": 967,
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
    "LUT": 2631.0,
    "logic_LUT": 2471.0,
    "FF": 2437.0,
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
    "WNS_ns": 4.128,
    "TNS_ns": 0.0,
    "setup_failing_endpoints": 0,
    "WHS_ns": 0.012,
    "THS_ns": 0.0,
    "hold_failing_endpoints": 0,
    "checks": {
      "no_clock": 0,
      "constant_clock": 0,
      "pulse_width_clock": 0,
      "unconstrained_internal_endpoints": 0,
      "no_input_delay": 128,
      "no_output_delay": 967,
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
    "routable_nets": 5638,
    "fully_routed_nets": 5638,
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

完整warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_wave.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_wave.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "array_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "array_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "post_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "post_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[38]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[38]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[32]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[32]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[39]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[39]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[50]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[50]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[18]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[18]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[52]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[52]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[20]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[20]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[54]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[54]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[48]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[48]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[49]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[49]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[17]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[17]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[55]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[55]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

### g8 实际工具证据

~~~json
{
  "name": "g8",
  "size": 8,
  "systolic": 1,
  "synthesis_completed": true,
  "ooc_completed": true,
  "part": "xcvu9p-flga2104-2L-e",
  "utilization": {
    "LUT": 4278.0,
    "logic_LUT": 3914.0,
    "FF": 3908.0,
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
    "WNS_ns": 5.446,
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
      "no_output_delay": 965,
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
    "LUT": 4181.0,
    "logic_LUT": 3817.0,
    "FF": 3908.0,
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
    "WNS_ns": 4.129,
    "TNS_ns": 0.0,
    "setup_failing_endpoints": 0,
    "WHS_ns": 0.01,
    "THS_ns": 0.0,
    "hold_failing_endpoints": 0,
    "checks": {
      "no_clock": 0,
      "constant_clock": 0,
      "pulse_width_clock": 0,
      "unconstrained_internal_endpoints": 0,
      "no_input_delay": 128,
      "no_output_delay": 965,
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
    "routable_nets": 9850,
    "fully_routed_nets": 9850,
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

完整warning列表：

~~~text
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_wave.sv:269]
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_wave has port req_group[11] driven by constant 0
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "post_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "post_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "array_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "array_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[34]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[34]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[35]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[35]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

## 范围与限制

已实现且验证：表中配置、逐PE对齐/冻结、流量和周期、bank重写/输入饥饿/复位；器件工具状态如上。未验证：最大M/N/K、未列参数、综合网表仿真、VCS编译运行。可配置VCS入口提供且Bash -n检查；本机未发现VCS，不安装或申请许可证。未来：消除READY tile的WAIT/PRIME边界停顿、有效槽psum保存、输出tile流水、Decode专用映射、统一NPU队列、DDR/完整模型。

“group连续”指同group不排空、不清除在途token，当前tile切换仍冻结两个固定控制拍，输入不READY还会增加冻结等待；不是每墙钟拍都注入，也未自动推进bubble以排空。新wave_hold统计是既有固定/输入等待周期的子集，不能重复加到总周期。数值格式与输出次序不变。
