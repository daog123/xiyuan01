# W4A8 验证与工具证据

本次环境：Windows PowerShell 5.1、Python 3.13.5、Vivado/XSim 2025.2（Build 6299465）。工具目录 E:\AMDDesignTools\2025.2\Vivado\bin。所有批处理通过 PowerShell & 调用，未修改全局环境或安装依赖。阶段二参考模型仅需 Python 标准库。

## 已复现的既有基线

原矩阵核心八组回归实际重跑通过：13矩阵/480输出每组，共3840输出；双缓冲单元18比较；NPU两组队列回归各36批任务+2恢复任务，共2382输出。原 RTL 未改动，已有综合/实现源哈希审计通过。原报告属于 INT8 matmul_top/npu_top，本阶段资源属于 w4a8_linear，不能混用。

## A：逐项位精确比较

| 配置 | 任务（含复位恢复） | 输出比较 | 分组psum比较 | 协议检查 | held input检查 |
|---|---|---|---|---|---|
| 4x4_k8_g32_db | 38 | 621 | 1521 | 133473 | 3604 |
| 2x3_k5_g12_db | 38 | 621 | 3414 | 228580 | 6466 |
| 4x4_k8_g32_single | 38 | 621 | 1521 | 158120 | 3624 |

先通过单缓冲定向12任务/189输出/453 psum，随后三配置完整回归。每次运行均检查所有有效输出坐标、唯一性、数值及last；所有group psum同样比较。覆盖全部16种INT4编码的高/低nibble、INT8边界、零/正负、固定随机、M/N/K尾块、group跨tile、末组不足、明显不同scale、两种group/阵列、连续任务、忙时start拒绝、非法零尺寸、计算中复位及输出受阻时复位、暂停恢复、输入/request/output持稳、bank所有权、实际重叠、有效MAC及字节流量。

任务超时200000周期、全局20 ms watchdog、XSim Tcl最多20 ms；失败 $fatal，PowerShell另外检查PASS和失败日志，确保非零退出。故障注入状态：{"executed": true, "exit_code": 1}。

## B/C：数值误差（固定随机样本，非模型准确率）

| group | case | 饱和输出 | B最大绝对误差 | B RMSE | B相对L2 | C最大绝对误差 | C RMSE | C相对L2 |
|---|---|---|---|---|---|---|---|---|
| 32 | zero | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 32 | bounds | 0 | 5.960464e-06 | 3.095284e-06 | 4.55654e-08 | 0 | 0 | 0 |
| 32 | different_scales | 0 | 6.556511e-06 | 3.936389e-06 | 1.691347e-10 | 0 | 0 | 0 |
| 32 | all_tails | 0 | 0.05113213 | 0.01421635 | 0.003043371 | 0.9569936 | 0.3882733 | 0.08306564 |
| 32 | decode | 0 | 0.03282417 | 0.01186224 | 0.002167705 | 0.9280055 | 0.5687457 | 0.103681 |
| 32 | prefill | 0 | 0.05109155 | 0.01909305 | 0.002615752 | 1.090325 | 0.534687 | 0.07526511 |
| 32 | tie_positive | 0 | 7.629395e-06 | 7.629395e-06 | 1 | 0 | 0 | 0 |
| 32 | tie_negative | 0 | 7.629395e-06 | 7.629395e-06 | 1 | 0 | 0 | 0 |
| 32 | sat_positive | 1 | 1.045267e+07 | 1.045267e+07 | 0.9968749 | 0 | 0 | 0 |
| 32 | sat_negative | 1 | 1.037075e+07 | 1.037075e+07 | 0.9968503 | 0 | 0 | 0 |
| 32 | random_rect | 0 | 0.03291048 | 0.01250077 | 0.002518562 | 1.004684 | 0.4197828 | 0.08613788 |
| 32 | consecutive_zero | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 12 | zero | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| 12 | bounds | 4 | 14036.76 | 5785.333 | 0.1796681 | 0 | 0 | 0 |
| 12 | different_scales | 1 | 4245.07 | 2122.535 | 0.07648749 | 0 | 0 | 0 |
| 12 | all_tails | 0 | 0.0323456 | 0.01269669 | 0.002725233 | 0.6943741 | 0.3185969 | 0.06815935 |
| 12 | decode | 0 | 0.06947853 | 0.03110165 | 0.005584016 | 0.8073576 | 0.4480541 | 0.0816792 |
| 12 | prefill | 0 | 0.06143315 | 0.02226706 | 0.003078268 | 1.22557 | 0.5016227 | 0.07061082 |
| 12 | tie_positive | 0 | 7.629395e-06 | 7.629395e-06 | 1 | 0 | 0 | 0 |
| 12 | tie_negative | 0 | 7.629395e-06 | 7.629395e-06 | 1 | 0 | 0 | 0 |
| 12 | sat_positive | 1 | 1.045267e+07 | 1.045267e+07 | 0.9968749 | 0 | 0 | 0 |
| 12 | sat_negative | 1 | 1.037075e+07 | 1.037075e+07 | 0.9968503 | 0 | 0 | 0 |
| 12 | random_rect | 0 | 0.02670429 | 0.01432915 | 0.002933433 | 0.9253376 | 0.4486712 | 0.09206568 |
| 12 | consecutive_zero | 0 | 0 | 0 | 0 | 0 | 0 | 0 |

B：Q16.16反编码输出与理想未编码scale浮点量化参考比较，包括scale编码、输出舍入和饱和误差。C：浮点量化参考与原始浮点线性层比较。direct/zero/tie/saturation样例的原始浮点数据由反量化构造，C接近0是人为构造，真正量化误差看 kind=float 的 all_tails/decode/prefill/random_rect。两个group的量化张量不同，不应将数值差异直接归因于硬件。

## 器件级综合 / OOC

默认4×4/Ktile8/group32/双缓冲实际综合完成。Vivado 2025.2，part **xcvu9p-flga2104-2L-e** 为既有临时评估选择，未确认板卡、最终封装和速度等级。Latch=0、blackbox=0。配置见 build/synth_w4a8/configuration.txt。

| 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|
| 综合 | 1671.0 | 1110.0 | 22.0 | 1.0 | 1.0 | 128.0 | 0.0 | 6.549 | 0.071 |
| OOC布局布线 | 1613.0 | 1110.0 | 22.0 | 1.0 | 1.0 | 128.0 | 0.0 | 4.993 | 0.011 |

完整资源/存储映射见 utilization_synth.rpt、utilization_hier_synth.rpt、ram_synth.rpt；乘法器实际DSP实例及 USE_MULT/USE_SIMD 见 dsp_mapping.txt；primitive_counts.txt 列出全部原语。RAM属性不是结果，实际推断以报告为准。默认实际22 DSP：16 PE、factor乘法1、宽psum×factor乘法4、valid_macs计数乘法1。scaled寄存器移除警告对应吸收到DSP的寄存器（dsp_mapping列出scaled_reg/ scaled_reg__0），不能把全部DSP当PE数量。packed W4当前符号扩展后复用8×8 MAC，未做一个DSP多个INT4乘法打包。group scratch及输出累加BRAM位利用率各2.78%，刻意保留同步BRAM行为，后续可比较小容量LUTRAM。

综合时序检查：

~~~json
{
  "WNS_ns": 6.549,
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
    "no_input_delay": 62,
    "no_output_delay": 453,
    "multiple_clock": 0,
    "generated_clocks": 0,
    "loops": 0,
    "partial_input_delay": 0,
    "partial_output_delay": 0,
    "latch_loops": 0
  },
  "scope": "OOC internal timing; external I/O delays unspecified"
}
~~~

OOC实际检查：

~~~json
{
  "completed": true,
  "utilization": {
    "LUT": 1613.0,
    "logic_LUT": 1485.0,
    "LUTRAM": 128.0,
    "FF": 1110.0,
    "BRAM_tiles": 1.5,
    "RAMB18": 1.0,
    "RAMB36": 1.0,
    "URAM": 0.0,
    "DSP": 22.0
  },
  "timing": {
    "WNS_ns": 4.993,
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
      "no_input_delay": 62,
      "no_output_delay": 453,
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
    "routable_nets": 3316,
    "fully_routed_nets": 3316,
    "routing_errors": 0,
    "explicit_gaps": 1
  },
  "drc_design_state": "Partially Routed",
  "drc_checks": [
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
      "checks": 5
    },
    {
      "rule": "RTSTAT-10",
      "severity": "Warning",
      "description": "No routable loads",
      "checks": 1
    }
  ]
}
~~~

综合/实现日志中的关键警告（原文，重复条目保留）：

~~~text
WARNING: [Synth 8-3917] design w4a8_linear has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_linear has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_linear has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_linear has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_linear has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_linear.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_linear.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

100 MHz是10 ns初步目标；综合时序不代表布线后频率。OOC假设虚拟 BUFGCE_X0Y0，未约束板级管脚和接口输入/输出延迟，报告存在无I/O延迟路径，应明确区别于无时钟或内部未约束端点。即使内部时序满足，也不作板级signoff或板上性能承诺。

## VCS与范围

Windows PATH/Get-Command、相关环境变量未发现VCS；WSL Ubuntu command -v vcs 及 /opt、/tools、/usr/local 常见 Synopsys目录探查无输出。未安装、未申请许可证、未运行VCS。提供可配置 Linux/WSL脚本 scripts/run_w4a8_vcs.sh，bash语法检查与VCS执行是两项不同检查，后者未验证。bash -n实际退出0，脚本可用性守卫实际返回 VCS_NOT_FOUND/退出2，未启动编译器；环境原始记录见 build/w4a8_environment.txt。XSim已经实际运行。

已实现并验证：本报告列出的W4A8功能及两组参数组合；默认配置器件综合/OOC状态如上。已实现但未验证：其他合法参数组合、最大64×64×4096实际任务、VCS编译执行。未来计划：DDR/DMA/PCIe、独立张量地址任务队列、INT8 requant、bias/FFN/Attention/完整模型。现有 NPU队列与新W4A8 top 尚未连接；保留两条可独立复现的顶层，避免宣称完整模型调度已实现。
