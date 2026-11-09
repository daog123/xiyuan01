# W4A8 宽供数优化：实际验证与性能

本轮新增 w4a8_stream，阶段二 w4a8_linear 及其报告/源码保持原样。数值合同、量化向量和参考输出未改变，参考模型的A/B/C误差仍见 w4a8_validation.md。工具为Windows PowerShell5.1、Python3.13.5、Vivado/XSim2025.2 Build6299465，评估part仍为xcvu9p-flga2104-2L-e，未确认板卡。

## 实际自检

| 配置 | BUS_BYTES | SCALE_ONCE | 阵列/Ktile/group | 任务 | 输出 | group psum | 检查 |
|---|---|---|---|---|---|---|---|
| b8_s1 | 8 | 1 | 4×4/8/32 | 38 | 621 | 1521 | 111420 |
| b1_s0 | 1 | 0 | 4×4/8/32 | 38 | 621 | 1521 | 158840 |
| b1_s1 | 1 | 1 | 4×4/8/32 | 38 | 621 | 1521 | 138420 |
| b8_s0 | 8 | 0 | 4×4/8/32 | 38 | 621 | 1521 | 124671 |
| alt_b8_s1 | 8 | 1 | 2×3/5/12 | 38 | 621 | 3414 | 257281 |
| single_b8_s1 | 8 | 1 | 4×4/8/32 | 38 | 621 | 1521 | 126799 |
| words_b8_s1 | 8 | 1 | 4×4/19/32 | 38 | 621 | 1521 | 106246 |

每配置36正常任务+2复位恢复任务，全部输出及group psum与原位精确参考一致；覆盖全部INT4编码、M/N/K尾块、不同scale、跨tile group、末组、连续任务、忙start、输入持稳、req_scale/keep持稳、输出背压、运行中/输出阻塞时reset。输入无效字节填0xA5，逐拍检查keep，验证尾部padding不污染结果。tile19配置让A/B RAM超过一个字，验证不同字地址、字内选择及奇K起点。

BUS_BYTES=1/SCALE_ONCE=0与阶段二模式0/1的所有已有CSV计数和周期完全一致，提供供数优化的回归对照。随机模型的握手时间线随配置不同，不作逐拍公平对照。故障注入：{"executed": true, "exit_code": 1}。任务/全局超时仍为200000周期/20ms，脚本检查fatal和PASS，失败非零退出。

## 供数条件与指标

模式0每拍最多一个beat，无额外首延迟；模式1每包首延迟5，每8物理字节额外暂停4拍，并按BUS_BYTES插入BUS_BYTES-1拍间隔，以保持各宽度的名义物理带宽预算相同，padding也占预算；模式2首延迟5、固定LFSR种子随机暂停、DUT load_pause及输出背压。没有真实DDR性能含义。bytes计数只计keep=1的有效字节，input_beats计所有接受beat，padding_bytes=beats×BUS_BYTES−有效字节。compute/input_wait/output_wait互斥，overlap为compute子集，不可重复加总。

| 配置 | 任务 | 模式 | 总周期 | W字节 | A字节 | scale字节 | beat | padding字节 | RUN | 等输入 | 等输出 | 重叠 | 端到端MAC利用率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b8_s1 | Decode | 0 | 1415 | 624 | 384 | 102 | 228 | 714 | 384 | 0 | 0 | 155 | 5.51% |
| b8_s1 | Decode | 1 | 2938 | 624 | 384 | 102 | 228 | 714 | 384 | 1523 | 0 | 44 | 2.65% |
| b8_s1 | Decode | 2 | 1601 | 624 | 384 | 102 | 228 | 714 | 384 | 181 | 5 | 89 | 4.87% |
| b8_s1 | Prefill | 0 | 1147 | 576 | 1152 | 144 | 306 | 576 | 288 | 9 | 0 | 227 | 25.11% |
| b8_s1 | Prefill | 1 | 3615 | 576 | 1152 | 144 | 306 | 576 | 288 | 2477 | 0 | 35 | 7.97% |
| b8_s1 | Prefill | 2 | 1443 | 576 | 1152 | 144 | 306 | 576 | 288 | 282 | 23 | 62 | 19.96% |
| b1_s0 | Decode | 0 | 2106 | 624 | 384 | 408 | 1416 | 0 | 384 | 691 | 0 | 352 | 3.70% |
| b1_s0 | Decode | 1 | 2734 | 624 | 384 | 408 | 1416 | 0 | 384 | 1319 | 0 | 199 | 2.85% |
| b1_s0 | Decode | 2 | 3098 | 624 | 384 | 408 | 1416 | 0 | 384 | 1674 | 9 | 97 | 2.52% |
| b1_s0 | Prefill | 0 | 2555 | 576 | 1152 | 576 | 2304 | 0 | 288 | 1417 | 0 | 264 | 11.27% |
| b1_s0 | Prefill | 1 | 3651 | 576 | 1152 | 576 | 2304 | 0 | 288 | 2513 | 0 | 153 | 7.89% |
| b1_s0 | Prefill | 2 | 4416 | 576 | 1152 | 576 | 2304 | 0 | 288 | 3257 | 21 | 76 | 6.52% |
| b1_s1 | Decode | 0 | 1916 | 624 | 384 | 102 | 1110 | 0 | 384 | 501 | 0 | 352 | 4.07% |
| b1_s1 | Decode | 1 | 2398 | 624 | 384 | 102 | 1110 | 0 | 384 | 983 | 0 | 185 | 3.25% |
| b1_s1 | Decode | 2 | 2753 | 624 | 384 | 102 | 1110 | 0 | 384 | 1333 | 5 | 102 | 2.83% |
| b1_s1 | Prefill | 0 | 2283 | 576 | 1152 | 144 | 1872 | 0 | 288 | 1145 | 0 | 264 | 12.61% |
| b1_s1 | Prefill | 1 | 3005 | 576 | 1152 | 144 | 1872 | 0 | 288 | 1867 | 0 | 153 | 9.58% |
| b1_s1 | Prefill | 2 | 3685 | 576 | 1152 | 144 | 1872 | 0 | 288 | 2523 | 24 | 73 | 7.82% |
| b8_s0 | Decode | 0 | 1415 | 624 | 384 | 408 | 300 | 984 | 384 | 0 | 0 | 217 | 5.51% |
| b8_s0 | Decode | 1 | 3554 | 624 | 384 | 408 | 300 | 984 | 384 | 2139 | 0 | 46 | 2.19% |
| b8_s0 | Decode | 2 | 1691 | 624 | 384 | 408 | 300 | 984 | 384 | 270 | 6 | 88 | 4.61% |
| b8_s0 | Prefill | 0 | 1156 | 576 | 1152 | 576 | 360 | 576 | 288 | 18 | 0 | 259 | 24.91% |
| b8_s0 | Prefill | 1 | 4263 | 576 | 1152 | 576 | 360 | 576 | 288 | 3125 | 0 | 35 | 6.76% |
| b8_s0 | Prefill | 2 | 1511 | 576 | 1152 | 576 | 360 | 576 | 288 | 347 | 26 | 75 | 19.06% |
| alt_b8_s1 | Decode | 0 | 1807 | 728 | 480 | 288 | 512 | 2600 | 480 | 0 | 0 | 311 | 11.51% |
| alt_b8_s1 | Decode | 1 | 5660 | 728 | 480 | 288 | 512 | 2600 | 480 | 3853 | 0 | 79 | 3.67% |
| alt_b8_s1 | Decode | 2 | 2379 | 728 | 480 | 288 | 512 | 2600 | 480 | 567 | 5 | 46 | 8.74% |
| alt_b8_s1 | Prefill | 0 | 3009 | 1344 | 1536 | 640 | 1088 | 5184 | 768 | 64 | 0 | 617 | 25.52% |
| alt_b8_s1 | Prefill | 1 | 12143 | 1344 | 1536 | 640 | 1088 | 5184 | 768 | 9198 | 0 | 128 | 6.32% |
| alt_b8_s1 | Prefill | 2 | 4118 | 1344 | 1536 | 640 | 1088 | 5184 | 768 | 1150 | 23 | 77 | 18.65% |
| single_b8_s1 | Decode | 0 | 1670 | 624 | 384 | 102 | 228 | 714 | 384 | 255 | 0 | 0 | 4.67% |
| single_b8_s1 | Decode | 1 | 3796 | 624 | 384 | 102 | 228 | 714 | 384 | 2381 | 0 | 0 | 2.05% |
| single_b8_s1 | Decode | 2 | 2087 | 624 | 384 | 102 | 228 | 714 | 384 | 665 | 7 | 0 | 3.74% |
| single_b8_s1 | Prefill | 0 | 1453 | 576 | 1152 | 144 | 306 | 576 | 288 | 315 | 0 | 0 | 19.82% |
| single_b8_s1 | Prefill | 1 | 4486 | 576 | 1152 | 144 | 306 | 576 | 288 | 3348 | 0 | 0 | 6.42% |
| single_b8_s1 | Prefill | 2 | 1873 | 576 | 1152 | 144 | 306 | 576 | 288 | 710 | 25 | 0 | 15.38% |
| words_b8_s1 | Decode | 0 | 1367 | 663 | 384 | 102 | 201 | 459 | 384 | 0 | 0 | 136 | 5.71% |
| words_b8_s1 | Decode | 1 | 2469 | 663 | 384 | 102 | 201 | 459 | 384 | 1102 | 0 | 34 | 3.16% |
| words_b8_s1 | Decode | 2 | 1390 | 663 | 384 | 102 | 201 | 459 | 384 | 17 | 6 | 114 | 5.61% |
| words_b8_s1 | Prefill | 0 | 1107 | 612 | 1152 | 144 | 306 | 540 | 288 | 5 | 0 | 188 | 26.02% |
| words_b8_s1 | Prefill | 1 | 3710 | 612 | 1152 | 144 | 306 | 540 | 288 | 2608 | 0 | 26 | 7.76% |
| words_b8_s1 | Prefill | 2 | 1216 | 612 | 1152 | 144 | 306 | 540 | 288 | 88 | 26 | 105 | 23.68% |

Decode=1×13×96、Prefill=4×12×96。利用率分母为硬件ROWS×COLS×总周期；有效MAC排除零填充。理论峰值默认16MAC/拍，100MHz目标下1.6GMAC/s，并非实测板上吞吐。

## 消融对照：连续供数

| 任务 | 配置 | 周期 | 相对字节基线周期减少 | scale有效字节 | padding字节 |
|---|---|---|---|---|---|
| Decode | b1_s0 | 2106 | 0.00% | 408 | 0 |
| Decode | b1_s1 | 1916 | 9.02% | 102 | 0 |
| Decode | b8_s0 | 1415 | 32.81% | 408 | 984 |
| Decode | b8_s1 | 1415 | 32.81% | 102 | 714 |
| Prefill | b1_s0 | 2555 | 0.00% | 576 | 0 |
| Prefill | b1_s1 | 2283 | 10.65% | 144 | 0 |
| Prefill | b8_s0 | 1156 | 54.76% | 576 | 576 |
| Prefill | b8_s1 | 1147 | 55.11% | 144 | 576 |

扩大输入口并不保证在相同物理带宽下改善：每权重列按word对齐，tile8每列4权重字节占8字节beat；模式1如出现退化，应先解决packing/复用，而非将其隐藏。A跨N tile复用尚未实现，仍重复传输；scale仅每M/N输出tile每group一次，尚未跨N/M tile复用。

## 综合/内部时序

| 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|
| 综合 | 2141.0 | 3102.0 | 22.0 | 1.0 | 1.0 | 0.0 | 0.0 | 6.538 | 0.071 |
| OOC | 2083.0 | 3102.0 | 22.0 | 1.0 | 1.0 | 0.0 | 0.0 | 4.509 | 0.007 |

Latch=0、blackbox=0。实际存储映射看build/synth_w4a8_stream/ram_synth.rpt；默认宽字depth1实际映射为FF，LUTRAM=0，group/output仍为RAMB18/RAMB36；对应资源代价应计入评估，不能仅因distributed属性就宣称LUTRAM。完整DSP实例见dsp_mapping.txt。10ns评估约束，虚拟BUFGCE_X0Y0；无板级管脚/I/O延迟，综合估计不代表布线后频率，OOC仅内部时序。

时序检查及OOC边界：

~~~json
{
  "synthesis_timing": {
    "WNS_ns": 6.538,
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
      "LUT": 2083.0,
      "logic_LUT": 2083.0,
      "LUTRAM": 0.0,
      "FF": 3102.0,
      "BRAM_tiles": 1.5,
      "RAMB18": 1.0,
      "RAMB36": 1.0,
      "URAM": 0.0,
      "DSP": 22.0
    },
    "timing": {
      "WNS_ns": 4.509,
      "TNS_ns": 0.0,
      "setup_failing_endpoints": 0,
      "WHS_ns": 0.007,
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
      "routable_nets": 5497,
      "fully_routed_nets": 5497,
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

实际关键警告见synth_w4a8_stream.log（本汇总记录全部WARNING/CRITICAL WARNING）：

~~~text
WARNING: [Synth 8-4767] Trying to implement RAM 'mem_reg' in registers. Block RAM or DRAM implementation is not possible; see log for reasons. [E:/speed-up/rtl/sync_sdp_ram.sv:17]
WARNING: [Synth 8-3917] design w4a8_stream has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_stream has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_stream has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_stream has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_stream has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_stream.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_stream.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[49]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[49]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[37]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[37]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[21]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[21]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[59]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[59]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[43]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[43]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[35]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[35]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[19]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[19]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[52]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[52]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[20]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[20]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[53]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[53]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[17]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[17]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[36]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[36]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[24]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[24]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[51]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[51]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[27]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[27]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[55]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[55]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[39]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[39]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[23]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[23]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[56]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[56]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[48]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[48]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[40]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[40]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[32]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[32]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[16]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[16]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[54]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[54]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[50]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[50]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[34]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[34]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[18]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[18]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[58]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[58]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[38]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[38]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

## 状态与下一步

已实现并验证：报告中七组配置及协议、数值、流量。已实现但未验证：其他BUS_BYTES/尺寸组合、最大64×64×4096任务、VCS编译执行。未来：A/weight跨输出tile复用、更高效跨lane packing、psum/scale流水解耦、新顶层接入NPU任务队列、真实DDR/DMA。未实现zero-point/AWQ/bias/INT8 requant/完整Transformer。

下一步优先依据模式1的padding成本与模式0剩余scale开销，比较跨列packed写入（每bank仍一写）、更长K tile和A复用；随后解耦scale流水；Decode仍只有一个有效行，需要单独评估N/K并行映射。VCS编译执行未运行，新增 scripts/run_w4a8_stream_vcs.sh 可配置入口；bash -n实际退出0，不能代表VCS通过。原始CSV/命令/源哈希在build/sim_w4a8_stream_*，汇总在build/w4a8_stream_summary.json。
