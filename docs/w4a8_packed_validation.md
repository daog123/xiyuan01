# W4A8 跨列权重打包：实际验证与性能

本轮新增w4a8_packed，保留w4a8_stream和w4a8_linear及其回归/报告。数值、INT4 nibble次序和外部权重列优先存储不变，只改变tile数据包与权重bank字宽。工具：Windows PowerShell5.1、Python3.13.5、Vivado/XSim2025.2 Build6299465；VU9P part仍为xcvu9p-flga2104-2L-e临时评估选择，未确认板卡。模型仅需Python标准库。

## 已运行自检

| 配置 | PACK_COLS | 阵列/tile/group | 任务 | 输出 | group psum | 双bank写拍 | 非连续keep拍 | 奇K请求 |
|---|---|---|---|---|---|---|---|---|
| paired | 1 | 4×4/8/32 | 38 | 621 | 1521 | 906 | 74 | 0 |
| unpacked | 0 | 4×4/8/32 | 38 | 621 | 1521 | 0 | 0 | 0 |
| alt | 1 | 2×3/5/12 | 38 | 621 | 3414 | 1851 | 1851 | 720 |
| words | 1 | 4×4/19/32 | 38 | 621 | 1521 | 1108 | 478 | 132 |
| single | 1 | 4×4/8/32 | 38 | 621 | 1521 | 906 | 74 | 0 |
| scales | 1 | 4×4/8/32 | 38 | 621 | 1521 | 906 | 74 | 0 |

每配置36正常任务+2复位恢复，所有有效输出和group psum完全等于原位精确参考。覆盖全部INT4编码、零/边界/正负/固定随机、M/N/K尾块、末group、跨tile累加、不同scale、暂停/背压、连续任务及计算中/输出受阻复位。keep逐字节独立检查，无效槽填0xA5；检查每拍有效bank写数与所有权。tile5/group12覆盖奇列数和奇K起点；tile19覆盖权重多32-bit字及A多64-bit字地址。超时200000周期/全局20ms，脚本检查fatal/PASS，失败非零退出。

PACK_COLS=0对照配置的所有模式、任务CSV周期和原有计数与上一轮w4a8_stream完全一致；新源与产物SHA256审计通过。故障注入：{"executed": true, "exit_code": 1}。量化三层A/B/C数值合同和误差未改变，见w4a8_numerics.md和w4a8_validation.md；没有真实模型准确率测量。

## 供数及计数口径

mode0：最多每拍一个64bit beat、无额外首延迟；mode1：每包首延迟5，每beat按8物理字节占用预算，beat之间7拍基础间隔+每8物理字节4拍burst间隔，padding也计预算；mode2：固定0x20261012 LFSR暂停、请求周期、首延迟及TB输入暂停/输出背压。各配置相同名义物理字节预算，但packet长度改变，随机握手时间线不同。只代表指定仿真模型，不代表DDR/板上性能。

valid_bytes=weight_bytes+activation_bytes+scale_bytes；physical_bytes=input_beats×BUS_BYTES；padding_bytes=physical_bytes−valid_bytes。compute/input_wait/output_wait互斥，overlap是compute子集，不可重复加总；计数32-bit无符号，每合法start清零，done后保持。有效MAC=m×n×k，尾填零不计入。峰值默认16MAC/拍、100MHz下理论1.6GMAC/s，未测板上吞吐。

## 代表性对照

| 布局 | 任务 | 模式 | 总周期 | beat | padding | W字节 | A字节 | scale字节 | RUN | 等输入 | 等输出 | 重叠 | MAC利用率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| unpacked | Decode 1×13×96 | 0 | 1415 | 228 | 714 | 624 | 384 | 102 | 384 | 0 | 0 | 155 | 5.51% |
| unpacked | Decode 1×13×96 | 1 | 2938 | 228 | 714 | 624 | 384 | 102 | 384 | 1523 | 0 | 44 | 2.65% |
| unpacked | Decode 1×13×96 | 2 | 1601 | 228 | 714 | 624 | 384 | 102 | 384 | 181 | 5 | 89 | 4.87% |
| unpacked | Prefill 4×12×96 | 0 | 1147 | 306 | 576 | 576 | 1152 | 144 | 288 | 9 | 0 | 227 | 25.11% |
| unpacked | Prefill 4×12×96 | 1 | 3615 | 306 | 576 | 576 | 1152 | 144 | 288 | 2477 | 0 | 35 | 7.97% |
| unpacked | Prefill 4×12×96 | 2 | 1443 | 306 | 576 | 576 | 1152 | 144 | 288 | 282 | 23 | 62 | 19.96% |
| paired | Decode 1×13×96 | 0 | 1415 | 156 | 138 | 624 | 384 | 102 | 384 | 0 | 0 | 91 | 5.51% |
| paired | Decode 1×13×96 | 1 | 2306 | 156 | 138 | 624 | 384 | 102 | 384 | 891 | 0 | 44 | 3.38% |
| paired | Decode 1×13×96 | 2 | 1505 | 156 | 138 | 624 | 384 | 102 | 384 | 84 | 6 | 89 | 5.18% |
| paired | Prefill 4×12×96 | 0 | 1138 | 234 | 0 | 576 | 1152 | 144 | 288 | 0 | 0 | 172 | 25.31% |
| paired | Prefill 4×12×96 | 1 | 2823 | 234 | 0 | 576 | 1152 | 144 | 288 | 1685 | 0 | 33 | 10.20% |
| paired | Prefill 4×12×96 | 2 | 1361 | 234 | 0 | 576 | 1152 | 144 | 288 | 199 | 24 | 68 | 21.16% |
| words | Decode 1×13×96 | 0 | 1367 | 189 | 363 | 663 | 384 | 102 | 384 | 0 | 0 | 123 | 5.71% |
| words | Decode 1×13×96 | 1 | 2282 | 189 | 363 | 663 | 384 | 102 | 384 | 915 | 0 | 32 | 3.42% |
| words | Decode 1×13×96 | 2 | 1378 | 189 | 363 | 663 | 384 | 102 | 384 | 6 | 5 | 126 | 5.66% |
| words | Prefill 4×12×96 | 0 | 1105 | 288 | 396 | 612 | 1152 | 144 | 288 | 3 | 0 | 188 | 26.06% |
| words | Prefill 4×12×96 | 1 | 3494 | 288 | 396 | 612 | 1152 | 144 | 288 | 2392 | 0 | 26 | 8.24% |
| words | Prefill 4×12×96 | 2 | 1227 | 288 | 396 | 612 | 1152 | 144 | 288 | 101 | 24 | 97 | 23.47% |

利用率分母为实际硬件ROWS×COLS×总周期，不把padding作为MAC。words配置tile19，不应仅归因于列打包，应与其旧tile19报告同时比较。

| 任务 | 模式 | 旧周期 | 新周期 | 周期减少 | 旧物理字节 | 新物理字节 |
|---|---|---|---|---|---|---|
| Decode | 0 | 1415 | 1415 | 0.00% | 1824 | 1248 |
| Decode | 1 | 2938 | 2306 | 21.51% | 1824 | 1248 |
| Decode | 2 | 1601 | 1505 | 6.00% | 1824 | 1248 |
| Prefill | 0 | 1147 | 1138 | 0.78% | 2448 | 1872 |
| Prefill | 1 | 3615 | 2823 | 21.91% | 2448 | 1872 |
| Prefill | 2 | 1443 | 1361 | 5.68% | 2448 | 1872 |

## 综合与内部时序

| 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|
| 综合 | 2324.0 | 2335.0 | 22.0 | 1.0 | 1.0 | 160.0 | 0.0 | 6.297 | 0.071 |
| OOC | 2281.0 | 2335.0 | 22.0 | 1.0 | 1.0 | 160.0 | 0.0 | 4.453 | 0.002 |

默认4×4/tile8/group32/64bit/SCALE_ONCE1/PACK_COLS1已实际综合。Latch=0、blackbox=0；其余配置仅仿真。实际A/W存储映射见ram_synth.rpt，不能由RTL数组或RAM_STYLE直接命名。权重bank宽32bit、深度2，实际为160 LUTRAM；A仍64bit、深度1并映射FF。较上一版宽口综合3102FF/2141LUT，本版2335FF/2324LUT，减少767FF、增加183LUT。RAM/FF实现结果以报告为准。16个DSP用于PE，其余用于scale及MAC统计；没有改成脉动阵列，也没有打包多个乘法进一个DSP。

~~~json
{
  "synthesis_timing": {
    "WNS_ns": 6.297,
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
      "no_input_delay": 126,
      "no_output_delay": 518,
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
      "LUT": 2281.0,
      "logic_LUT": 2121.0,
      "LUTRAM": 160.0,
      "FF": 2335.0,
      "BRAM_tiles": 1.5,
      "RAMB18": 1.0,
      "RAMB36": 1.0,
      "URAM": 0.0,
      "DSP": 22.0
    },
    "timing": {
      "WNS_ns": 4.453,
      "TNS_ns": 0.0,
      "setup_failing_endpoints": 0,
      "WHS_ns": 0.002,
      "THS_ns": 0.0,
      "hold_failing_endpoints": 0,
      "checks": {
        "no_clock": 0,
        "constant_clock": 0,
        "pulse_width_clock": 0,
        "unconstrained_internal_endpoints": 0,
        "no_input_delay": 126,
        "no_output_delay": 518,
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
      "routable_nets": 4817,
      "fully_routed_nets": 4817,
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
}
~~~

工具警告原文（完整日志/计数见build/synth_w4a8_packed）：

~~~text
WARNING: [Synth 8-4767] Trying to implement RAM 'mem_reg' in registers. Block RAM or DRAM implementation is not possible; see log for reasons. [E:/speed-up/rtl/sync_sdp_ram.sv:17]
WARNING: [Synth 8-3917] design w4a8_packed has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_packed has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_packed has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_packed has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_packed has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_packed.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_packed.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
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
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[37]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[37]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[21]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[21]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[53]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[53]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[38]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[38]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[39]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[39]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[36]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[36]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[34]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[34]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[35]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[35]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

10ns是初步内部约束，虚拟BUFGCE_X0Y0，无板级管脚/I/O延迟；综合估计不是布局布线频率，OOC仍有边界限制，不作板级signoff或token/s承诺。

## 当前边界

已实现且验证：表中六配置，传输/数值/背压/复位及默认综合/OOC状态如上。未验证：其他合法参数组合、最大64×64×4096实际任务、VCS编译执行。本机先前未发现VCS，本轮编译执行未运行，提供run_w4a8_packed_vcs.sh，Bash -n已实际退出0，不等于VCS验证。模型MAX_DATA8192用于小型样本。

未来：A跨N tile复用、group psum双缓冲及scale流水解耦、新顶层接NPU队列、真实DDR/DMA、专门Decode映射、脉动阵列对照。当前组末scale仍每个M/N tile传一次，未做跨输出tile scale cache；完整Transformer/zero-point/AWQ/bias/INT8 requant均未实现。

原始CSV/命令/源哈希位于build/sim_w4a8_packed_*，EDA位于build/synth_w4a8_packed，汇总build/w4a8_packed_summary.json。layout、keep、bank地址与端口合同见w4a8_packed_architecture.md。
