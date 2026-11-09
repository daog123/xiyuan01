# W4A8 双 psum Buffer 与独立 scale 流水：实际报告

新增w4a8_post；保留原w4a8_packed及其源哈希/报告。输入列对packet和数值合同未变，变化为两组group snapshot与独立后处理。工具为Windows PowerShell5.1/Python3.13.5/Vivado-XSim2025.2 Build6299465；part为xcvu9p-flga2104-2L-e临时评估选择，板卡未确认。

## 已运行验证

| 配置 | overlap | pipeline | 阵列/group | 任务 | 输出 | psum/缩放乘积 | 满队列检查 | 流水持稳检查 |
|---|---|---|---|---|---|---|---|---|
| overlap_pipe | 1 | 1 | 4×4/32 | 40 | 675 | 1683 | 39 | 1602 |
| serial | 0 | 0 | 4×4/32 | 40 | 675 | 1683 | 0 | 2364 |
| pipe_serial | 0 | 1 | 4×4/32 | 40 | 675 | 1683 | 0 | 1752 |
| scalar_overlap | 1 | 0 | 4×4/32 | 40 | 675 | 1683 | 69 | 2006 |
| alt | 1 | 1 | 2×3/12 | 40 | 675 | 3738 | 29 | 2969 |
| single | 1 | 1 | 4×4/32 | 40 | 675 | 1683 | 39 | 2138 |
| one | 1 | 1 | 1×1/32 | 40 | 675 | 1683 | 24 | 5292 |

每配置36正常任务+4附加任务：计算中复位恢复、输出受阻复位恢复、后处理冻结至Buffer满后恢复、流水有数据时复位恢复。全输出和group INT32 psum逐项一致，并逐有效槽比较psum×sx×sw的64bit乘积。覆盖不同scale/group、尾块、GEMV/GEMM、INT4边界/全部编码、正负/随机/零、连续任务、输入暂停、输出背压、metadata、bank所有权、输出RAM读写仲裁、暂停时流水valid/tag/data持稳。1×1阵列专门覆盖单地址组间读写依赖。

超时每任务200000周期，全局20ms；fatal/PASS由PowerShell额外检查，失败非零。故障注入：{"executed": true, "exit_code": 1}。A位精确通过；量化B/C误差沿用同一向量与数值合同，见w4a8_validation.md，不代表真实模型准确率。

## 代表性周期与消融

| 任务 | 模式 | 配置 | 周期 | 旧列对周期 | 相对旧版减少 | RUN | 后处理活动 | 计算/后处理重叠 | drain | psum满等待 | 等输入 | 等输出 | MAC利用率 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Decode 1×13×96 | 0 | serial | 1451 | 1415 | -2.54% | 384 | 576 | 0 | 600 | 0 | 0 | 0 | 5.38% |
| Decode 1×13×96 | 0 | pipe_serial | 1091 | 1415 | 22.90% | 384 | 216 | 0 | 240 | 0 | 0 | 0 | 7.15% |
| Decode 1×13×96 | 0 | scalar_overlap | 1051 | 1415 | 25.72% | 384 | 576 | 256 | 200 | 0 | 0 | 0 | 7.42% |
| Decode 1×13×96 | 0 | overlap_pipe | 931 | 1415 | 34.20% | 384 | 216 | 112 | 80 | 0 | 0 | 0 | 8.38% |
| Decode 1×13×96 | 1 | serial | 2206 | 2306 | 4.34% | 384 | 576 | 0 | 600 | 0 | 755 | 0 | 3.54% |
| Decode 1×13×96 | 1 | pipe_serial | 1870 | 2306 | 18.91% | 384 | 216 | 0 | 240 | 0 | 779 | 0 | 4.17% |
| Decode 1×13×96 | 1 | scalar_overlap | 1966 | 2306 | 14.74% | 384 | 576 | 144 | 200 | 0 | 915 | 0 | 3.97% |
| Decode 1×13×96 | 1 | overlap_pipe | 1846 | 2306 | 19.95% | 384 | 216 | 64 | 80 | 0 | 915 | 0 | 4.23% |
| Decode 1×13×96 | 2 | serial | 1702 | 1505 | -13.09% | 384 | 736 | 0 | 768 | 0 | 78 | 5 | 4.58% |
| Decode 1×13×96 | 2 | pipe_serial | 1235 | 1505 | 17.94% | 384 | 276 | 0 | 311 | 0 | 66 | 7 | 6.32% |
| Decode 1×13×96 | 2 | scalar_overlap | 1205 | 1505 | 19.93% | 384 | 756 | 253 | 270 | 0 | 76 | 8 | 6.47% |
| Decode 1×13×96 | 2 | overlap_pipe | 1056 | 1505 | 29.83% | 384 | 284 | 121 | 108 | 0 | 92 | 5 | 7.39% |
| Prefill 4×12×96 | 0 | serial | 1165 | 1138 | -2.37% | 288 | 432 | 0 | 450 | 0 | 0 | 0 | 24.72% |
| Prefill 4×12×96 | 0 | pipe_serial | 895 | 1138 | 21.35% | 288 | 162 | 0 | 180 | 0 | 0 | 0 | 32.18% |
| Prefill 4×12×96 | 0 | scalar_overlap | 865 | 1138 | 23.99% | 288 | 432 | 192 | 150 | 0 | 0 | 0 | 33.29% |
| Prefill 4×12×96 | 0 | overlap_pipe | 775 | 1138 | 31.90% | 288 | 162 | 84 | 60 | 0 | 0 | 0 | 37.16% |
| Prefill 4×12×96 | 1 | serial | 2790 | 2823 | 1.17% | 288 | 432 | 0 | 450 | 0 | 1625 | 0 | 10.32% |
| Prefill 4×12×96 | 1 | pipe_serial | 2724 | 2823 | 3.51% | 288 | 162 | 0 | 180 | 0 | 1829 | 0 | 10.57% |
| Prefill 4×12×96 | 1 | scalar_overlap | 2790 | 2823 | 1.17% | 288 | 432 | 36 | 150 | 0 | 1925 | 0 | 10.32% |
| Prefill 4×12×96 | 1 | overlap_pipe | 2724 | 2823 | 3.51% | 288 | 162 | 0 | 60 | 0 | 1949 | 0 | 10.57% |
| Prefill 4×12×96 | 2 | serial | 1497 | 1361 | -9.99% | 288 | 556 | 0 | 578 | 0 | 179 | 25 | 19.24% |
| Prefill 4×12×96 | 2 | pipe_serial | 1134 | 1361 | 16.68% | 288 | 210 | 0 | 237 | 0 | 159 | 23 | 25.40% |
| Prefill 4×12×96 | 2 | scalar_overlap | 1132 | 1361 | 16.83% | 288 | 568 | 180 | 198 | 0 | 197 | 22 | 25.44% |
| Prefill 4×12×96 | 2 | overlap_pipe | 1029 | 1361 | 24.39% | 288 | 202 | 73 | 72 | 0 | 215 | 27 | 27.99% |

serial为新controller关闭流水/重叠，包含snapshot交付和独立控制的额外周期，不声称与旧单状态机周期完全一致。mode0连续beat；mode1保持上一轮物理字节预算及首延迟/burst；mode2仍有LFSR/输入/输出暂停，另加入周期post_pause。mode2与旧版暂停条件不同，不能将全部周期差归因于流水。

## 计数定义与端口约束

psum_groups：保存完整snapshot的组数；post_issue/retire：物理RC槽读请求/写回拍，包括尾槽0；预期均为output_tile_count×group_count×RC。compute_post_overlap：RUN且post状态活动，是RUN子集，post活动包括post_pause。post_active：P_STREAM状态周期；post_drain：核心WAIT_POST周期；psum_wait：WAIT_PSUM且目标bank非FREE。compute/input_wait/output_wait/psum_wait/post_drain互斥，不能将重叠指标或post_active重复加总。统计32位，每合法start清零，done后保持。另独立审计总周期闭式分类：固定开销=2RC×输出tile数+2×输入tile数+(RC+2)×group数+2MN+1，总周期=固定开销+RUN+input_wait+output_wait+psum_wait+post_drain。固定项涵盖初始化、同步读/交付、逐槽保存和输出，而不重复加post_active。

两个32bit psum RAM各单同步读/单写，64bit输出RAM单读/单写；后处理issue同步读psum/Y并寄存factor，下一enabled拍寄存scaled/Ybase，再下一拍写Y。流水每enabled拍一个slot，暂停整体冻结并禁止读写。仅一个group进入后处理，上一group最后写回后才取下一group，避免同地址组间RAW hazard；所有组完成才输出。CORE INIT_Y/OUT_REQ与后处理RAM访问互斥。每组仍用RC拍保存PE，未做PE双阵列。

有效MAC不计填零，默认16MAC/拍，100MHz目标的1.6GMAC/s是理论上限；供数/暂停来自TB，不代表DDR、板上频率或token/s。输入字节/beat/padding与旧版匹配，优化没有减少算法MAC或改变量化精度。

## VU9P 综合与内部时序

| 阶段 | LUT | FF | DSP | RAMB18 | RAMB36 | LUTRAM | URAM | WNS ns | WHS ns |
|---|---|---|---|---|---|---|---|---|---|
| 综合 | 2591.0 | 3029.0 | 22.0 | 2.0 | 1.0 | 160.0 | 0.0 | 6.264 | 0.071 |
| OOC | 2547.0 | 3029.0 | 22.0 | 2.0 | 1.0 | 160.0 | 0.0 | 4.401 | 0.01 |

默认4×4/group32/双输入bank/两psum bank/流水重叠已实际综合，latch=0、blackbox=0。其他配置只仿真。实际两组psum各映射RAMB18，输出累加RAMB36，W bank共160 LUTRAM，A bank为FF；相较旧列对综合，新增267 LUT、694 FF与1个RAMB18，DSP数量不变。浅psum RAM被工具建议改LUTRAM，本轮保留BRAM同步行为与对照，未做该额外优化。存储映射见ram_synth.rpt，DSP实际实例见dsp_mapping.txt。10ns约束和虚拟BUFGCE_X0Y0仅用于内部评估，无板级管脚/I/O延迟。

~~~json
{
  "synthesis_timing": {
    "WNS_ns": 6.264,
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
      "no_output_delay": 742,
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
      "LUT": 2547.0,
      "logic_LUT": 2387.0,
      "LUTRAM": 160.0,
      "FF": 3029.0,
      "BRAM_tiles": 2.0,
      "RAMB18": 2.0,
      "RAMB36": 1.0,
      "URAM": 0.0,
      "DSP": 22.0
    },
    "timing": {
      "WNS_ns": 4.401,
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
        "no_input_delay": 127,
        "no_output_delay": 742,
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
      "routable_nets": 5821,
      "fully_routed_nets": 5821,
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
    ]
  }
}
~~~

实际工具警告（完整保留）：

~~~text
WARNING: [Synth 8-4767] Trying to implement RAM 'mem_reg' in registers. Block RAM or DRAM implementation is not possible; see log for reasons. [E:/speed-up/rtl/sync_sdp_ram.sv:17]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[0] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-6014] Unused sequential element psum_m_reg[1] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[0] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-6014] Unused sequential element psum_n_reg[1] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[0] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-6014] Unused sequential element psum_group_reg[1] was removed.  [E:/speed-up/rtl/w4a8_post.sv:208]
WARNING: [Synth 8-3917] design w4a8_post has port req_group[15] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_post has port req_group[14] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_post has port req_group[13] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_post has port req_group[12] driven by constant 0
WARNING: [Synth 8-3917] design w4a8_post has port req_group[11] driven by constant 0
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[47]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[46]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[45]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[44]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[43]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[42]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[41]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[40]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[39]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[38]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[37]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[36]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[35]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[34]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[33]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[32]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[31]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[30]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[29]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[28]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[27]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[26]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[25]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[24]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[23]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[22]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[21]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[20]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[19]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[18]__0) is unused and will be removed from module w4a8_post.
WARNING: [Synth 8-3332] Sequential element (scaled_reg[17]__0) is unused and will be removed from module w4a8_post.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
WARNING: [Route 35-198] Port "cfg_k[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "rst" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "rst". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_k[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_k[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[8]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[8]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[11]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[11]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_n[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_n[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[3]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[3]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[0]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[0]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "cfg_m[2]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "cfg_m[2]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "out_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "out_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "start" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "start". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "req_ready" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "req_ready". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[63]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[63]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[55]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[55]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[39]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[39]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[15]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[15]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[4]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[4]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "load_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "load_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_valid" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_valid". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[54]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[54]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[37]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[37]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[29]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[29]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[21]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[21]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[13]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[13]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[53]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[53]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[47]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[47]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[31]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[31]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[23]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[23]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[7]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[7]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "post_pause" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "post_pause". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[61]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[61]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[45]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[45]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[30]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[30]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[17]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[17]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[6]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[6]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[1]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[1]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[60]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[60]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[44]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[44]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[36]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[36]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[28]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[28]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[20]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[20]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[12]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[12]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[57]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[57]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[49]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[49]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[25]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[25]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[62]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[62]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[46]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[46]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[38]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[38]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[14]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[14]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[52]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[52]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[9]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[9]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[41]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[41]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[33]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[33]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[22]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[22]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[42]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[42]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[50]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[50]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[26]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[26]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_data[10]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_data[10]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [Route 35-198] Port "in_keep[5]" does not have an associated HD.PARTPIN_LOCS, which will prevent the partial routing of the signal "in_keep[5]". Without this partial route, timing analysis to/from this port will not be accurate, and no routing information for this port can be exported.
WARNING: [DRC 23-814] Not all possible (connectivity based) DRCs may have been run because this design is seen as Out of Context.
~~~

## 限制与后续

已实现且验证：表中七组合、位精确/乘积/ownership/压力/复位，默认综合/OOC状态如上。未验证：其他参数、最大逻辑尺寸、VCS编译执行。新VCS入口为run_w4a8_post_vcs.sh，仅Bash -n实际通过；编译执行未运行，未安装工具或申请许可证。两psum bank固定深度2；组间不同时在scale流水中，输出tile间未重叠；metadata与scale为FF，小RAM位利用率低。A跨N复用、专门Decode映射、脉动对照、NPU队列适配、真实DDR/DMA及完整Transformer仍未实现。

原始CSV/命令/source_inputs位于build/sim_w4a8_post_*，EDA在build/synth_w4a8_post，汇总build/w4a8_post_summary.json，接口/lifecycle见w4a8_post_architecture.md。
