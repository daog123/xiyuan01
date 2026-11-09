# Performance baseline

`w4a8_axi_read.sv` is the exact byte-for-byte pre-optimization reader from
the `3b0a5d5` working tree, captured on 2026-10-25 before any RTL modification.
SHA256: `a5a6d7d7d523bddd7ae411b2fcc729ca5a243d08cd06b2cc0fe610fe263cf62c`.

It is substituted for the production reader only by
`scripts/benchmark_performance.py` in a separate compilation directory.
Do not add it to the production manifest or compile both reader modules together.

## 第二轮计算优化的冻结基线

`w4a8_wave_round1.sv` 与 `tb_w4a8_wave_round1.sv` 保存第二轮开始前已验证的紧凑槽位计算核/测试台；`implement_compute_round1.tcl` 保存当时实际物理实现脚本。它们仅供独立基准编译，不加入生产清单。`prepare_round2_inputs.py` 将前两份文件验证后放入独立构建目录。当前优化结果见 `docs/compute_round2.md`。

`w4a8_wave_precompact.sv` 为更早的紧凑槽位对照基线；不能与round1/current混称为同一个版本。原始资源21/69个DSP属于历史核心，当前默认26/74，打包广播42。

## 第三轮存储比较

w4a8_memory_packet_round2.sv、w4a8_memory_bridge_round2.sv为第二轮结束时逐字节gather的不可变基线，仅由第三轮独立配对实验编译；不加入主系统清单。当前byte读取器原模块仍保留，新增chunk模块位于同一文件中。

## 第四轮FFN比较

ffn_dma_round3.sv为第三轮逐字节Q16.16向量DMA的冻结原文；benchmark_round4.py只替换此模块，其他计算核、调度、内存服务条件和数据相同。它不加入生产清单。

## 第五轮计算组织比较

w4a8_wave_round4.sv是第四轮结束的冻结核心（SHA256 aee2b0bfc901f31974f083c7fe1e40e4e1c5f62c9416002e7be5b32ff3823ec1），仅用于benchmark_round5.py、benchmark_round5_system.py及implement_round5.py的隔离编译，不加入生产清单。
