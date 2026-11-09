# 自研 LINEAR 板级接入端点

本端点把当前 `w4a8_team_top`、最新 `w4a8_wave` 及实际 AXI 存储通路封装为可供板级 shell 连接的 IP：主机用寄存器提交任务，核心从 DDR 读取 A/W/sx/sw，在 FPGA 内完成全部 W4A8 数值运算，再写回最终 Q16.16。它是后续自研 RTL 上板的集成模块，尚未连接真实板级 shell 或加载到 FPGA。

## 与现有系统的关系

- 新顶层：`rtl/w4a8_board_top.sv`；寄存器端点：`rtl/w4a8_board_control.sv`。
- IP 封装使用纯 Verilog 边界 `rtl/w4a8_board_ip.v`，显式映射全部端口，并用 `s_axi_*` / `m_axi_*` 区分控制和内存总线；计算实现仍为原 SystemVerilog RTL。
- 本轮没有改动原计算核、主系统任务图或全局 ABI v5；新增的是独立 LINEAR 控制入口，mailbox ABI=1。
- 默认 4×4、TILE_K=32、GROUP_SIZE=32，M/N≤64、K≤4096，64 位 DDR 地址。分组尺度、舍入、饱和均由原自研 RTL 完成。
- 原参考矩阵 bitstream 不含该寄存器接口。主机程序先检查 magic/ABI，不能把参考核的通过结果当成这个端点的实体板验证。
- 器件综合目标为参考 bitstream 头中已加载成功的 `xcvu9p-flgb2104-2-i`。这与原主系统 OOC 配置的 `xcvu9p-flga2104-2L-e` 不同，因此另存 `config/board_endpoint_profile.json`，不覆盖原全局配置。

## 需要 shell 提供的接口

| 端点 | 接入要求 |
| --- | --- |
| clk | 本轮仅验证 100 MHz 综合目标；实际源时钟未确认。shell 若使用 250 MHz，需提供合适时钟或通过 AXI Clock Converter 跨域 |
| rst | 同步高有效，和下游总线协调复位；不能只清计算端点却保留旧 AXI 事务 |
| ddr_ready | 已同步到 clk 的 DDR/fabric 就绪信号；未就绪时拒绝 START。运行期间不得依赖该输入取消已发出的事务 |
| s_axi_* | 32 位 AXI4-Lite、12 位局部地址、4 KiB 窗口；独立 AW/W，支持 WSTRB、B/R 反压。外部必须完整译码高位地址，不能只截低 12 位 |
| ar/r/aw/w/b | 64 位数据、64 位地址、4 位 ID 的 AXI4 master。允许窄读、对齐 lane/写 strobe 和读 burst；DDR 数据宽度不同需标准 AXI Data Width Converter |
| 其他 AXI 属性 | 本端点未暴露 PROT/CACHE/LOCK/QOS；shell 封装按其总线要求连接常量。转换器必须保留 AXI ID/RESP/LAST 语义，不能忽略错误响应 |

候选映射沿用已验证参考路径：控制局部地址 `0xD0000000`，主机访问 `0x20D0000000`；DDR 局部地址 `0x800000000`，主机加 Aurora 前缀 `0x2000000000`。它们是集成约定，仍须由 shell 实际译码保证；当前模块本身不产生 DDR/PCIe/Aurora 控制器，不包含管脚约束。

## 寄存器协议

所有字段 little-endian、32 位字，地址必须 4 字节对齐。未知或只读地址写入、非法命令、忙时修改描述符返回 SLVERR，读未知/未对齐地址也返回 SLVERR。没有中断接口，使用轮询。

| 偏移 | 字段 | 说明 |
| --- | --- | --- |
| 0x000 | MAGIC | 只读 `0x58495738` |
| 0x004 | ABI | 只读 1，独立于主系统 graph ABI |
| 0x008 | COMMAND | 写 1=START，写 2=ACK；其他非零组合拒绝；零或被 WSTRB 全屏蔽为无操作 |
| 0x00C | STATE | bit0 READY，bit1 BUSY，bit2 DONE，bit3 DDR_READY，bit4 RESULT_OK |
| 0x010 | COMPLETION_ID | 完成记录 task_id |
| 0x014 | COMPLETION_STATUS | 原 task_desc_pkg 状态码，0=成功 |
| 0x018 | COMPLETION_CYCLES | 完成时锁存的核心执行周期，不包括主机/DMA 端到端时间 |
| 0x01C | GROUP_SIZE | 编译期分组大小 |
| 0x020 | TASK_ID | uint32 |
| 0x024 / 0x028 / 0x02C | M / N / K | 每项低 16 位有效；写入非零高 16 位被拒绝，避免静默截断 |
| 0x030 / 0x034 | A_LO / A_HI | A 的 64 位 DDR 局部地址 |
| 0x038 / 0x03C | W_LO / W_HI | W 的 64 位 DDR 局部地址 |
| 0x040 / 0x044 | SX_LO / SX_HI | sx 的 64 位 DDR 局部地址 |
| 0x048 / 0x04C | SW_LO / SW_HI | sw 的 64 位 DDR 局部地址 |
| 0x050 / 0x054 | Y_LO / Y_HI | Y 的 64 位 DDR 局部地址 |
| 0x058 / 0x05C / 0x060 / 0x064 / 0x068 | A/W/SX/SW/Y_STRIDE | uint32，单位为字节 |
| 0x06C | FORMATS | 从低字节到高字节：activation/weight/scale/output，当前 `0x01010101` |
| 0x070 | GROUP_FLAGS | 低 16 位 group_size，高 16 位 flags，当前 flags=0 |
| 0x074 / 0x078 / 0x07C / 0x080 / 0x084 | A/W/SX/SW/Y_BYTES | 真实分配容量，不从形状猜测 |
| 0x088 | ARRAY | 高 16 位 ROWS，低 16 位 COLS |
| 0x08C | TILE_K | 编译期 TILE_K |
| 0x090 / 0x094 / 0x098 | MAX_M / MAX_N / MAX_K | 编译期容量 |
| 0x09C | ADDR_WIDTH | AXI 逻辑地址位宽，当前 64；不表示 DDR 物理容量 |

写描述符只在非 BUSY、非 DONE 时允许；START 还要求 DDR_READY。START 之后保持描述符，直至任务完成且主机 ACK。不会自动清完成记录，也不会因轮询而重新发起任务。成功完成必须等待原存储通路的全部输出 B 响应；错误先排空已发出的事务。

主机应按以下顺序工作：确认 magic/ABI/容量 → 初始化 DDR 输入 → 写描述符 → START → 轮询 DONE → 读取 ID/status/cycles → 成功时读 Y → ACK。错误或超时不能直接重发任务；超时不会取消硬件。该端点没有可能打断外部事务的软件复位或 abort 寄存器。

## 主机代码

`software/board_mailbox.py` 提供：

- `descriptor_words()`：在原有容量与别名验证后生成 26 个描述符寄存器字，保留地址高位。
- `BoardMailbox`：校验镜像身份、提交、轮询、读取结果、显式 ACK。保留错误完成记录和超时后的任务所有权。
- `XDMARegisterIO`：Linux channel-0 访问，核对固定 PCI 与实际字符设备主次设备号，每个 DMA 分段显式 seek，持有单卡锁。它不执行加载、复位、PCI 重绑或 Flash 写入。

基础访问层已单独放入 `software/board_xdma_io.py`，只依赖标准库，可由 Python 3.6 导入；完整任务对象与上层运行时仍使用项目所需的新版本 Python。服务器还可直接使用 `/home/test/miniconda3/bin/python3.13`。本轮已用这个实际访问层在选定物理卡只读回读两次 1 KiB，均与上轮参考任务输出一致；已验证错误镜像识别拒绝继续写入。该结果只验证访问与身份保护，不表示自研 RTL 已加载。

示意调用（仅在该端点确实集成并加载后使用）：

```python
from software.board_mailbox import XDMARegisterIO, BoardMailbox

with XDMARegisterIO(verified_h2c_node, verified_c2h_node) as io:
    board = BoardMailbox(io)
    # 使用 io.write_memory() 初始化已分配的 A/W/sx/sw 缓冲区。
    board.submit(bounded_task)  # 原 W4A8MemoryTask，地址使用 DDR 局部地址
    event = board.wait()
    output = board.read_result()
    board.acknowledge()
```

初次上板前仍须由 shell 确认控制地址、DDR 窗口及容量。`XDMARegisterIO` 尚未在自研 bitstream 上执行；本轮不把软件单元测试当作实体板结果。

## 验证与构建

在工程根目录执行：

```powershell
python scripts/validate_board_endpoint.py --synthesize
```

仅仿真可省略 `--synthesize`。使用本机 Vivado 2025.2，默认构建目录 `build/board_endpoint`。Windows 工具链要求构建路径不含中文，脚本传给 Tcl 的路径使用 `/`。

端到端验证以 Python 项目参考模型生成 DDR 字节镜像和 golden，并让实际主机序列化函数生成寄存器序列，再经 AXI4-Lite 驱动真实计算 RTL 与 AXI 存储仿真。8 项完成、326 个输出逐项核对；使用 `0x800000000` 以上地址，检查读写高位不被截断。覆盖 AW/W 分离、WSTRB、B/R 反压、部分写入后共享复位、DDR 未就绪拒绝启动、忙时修改拒绝、DONE 保持与 ACK、延迟输出 B、读写错误、错误后继续任务、非法容量/分组不访问 DDR、输入和保护区不变。

故意破坏 golden 和强制超时均须被判失败；不单独相信 XSim 进程退出码。另有 11 项主机软件测试。`result.json`、日志和源码 SHA256 保存本次证据；综合时额外生成 DCP、资源及综合时序报告。

综合仅说明该端点能针对目标器件建立网表。尚无板级时钟约束、输入输出时序、DDR/PCIe IP 连接和布局布线结果，因此不能宣称板级 100 MHz 收敛或生成可烧录镜像。

## Vivado IP 封装与 Block Design 接入

`scripts/package_board_endpoint.tcl` 将已验证的端点封装为 `xiyuan.local:accelerator:w4a8_board_endpoint:1.0`，明确声明 S_AXI、M_AXI、时钟、同步高有效复位和 4 KiB 控制窗口。它在独立的新目录创建包，不覆盖已有包。

```powershell
& E:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/package_board_endpoint.tcl
```

日志中的 `W4A8_ENDPOINT_IP_PACKAGE_PASS ... output=...` 给出目录，`ip/component.xml` 为可加入 IP Repository 的组件入口。再运行：

```powershell
& E:/AMDDesignTools/2025.2/Vivado/bin/vivado.bat -mode batch -source scripts/validate_board_ip_bd.tcl -tclargs <包目录>/ip
```

此脚本在独立 BD 中实例化 IP、导出控制/内存接口及时钟复位/ready，验证地址分配并生成目标及包装层。测试控制窗口从局部 0 开始，内存测试窗口位于 `0x800000000`、范围 4 MiB。这只是接口与地址元数据的独立验证，不证明板卡物理 DDR 容量，也未实例化实际 DDR/Aurora/时钟或管脚。

实际 shell 中仍须把控制窗口挂到约定的完整地址，连接时钟与协调复位，并按真实 DDR 位宽加入必要的 AXI 转换器。IP 版本由本机 Vivado 2025.2 打包；旧版本 shell 应使用随包 RTL 和脚本重建，不能直接假设新 IP/DCP 的版本兼容性。

## 交付给板级 shell 维护者的最小资料需求

1. 与已验证 9P bitstream 对应的可修改工程：`.xpr` 或完整重建 Tcl，加 RTL、BD/IP 配置、依赖、约束及目标器件信息。
2. 计算 FPGA 上可供用户逻辑接入的控制 slave 与 DDR master 连接位置、地址译码、数据/地址/ID 宽度及支持的窄访问/burst。
3. 可用用户时钟、复位与 DDR calibration/ready 信号，以及跨时钟方案。
4. 生成完整 9P 应用 bitstream 的流程和加载格式；应保持 C6 管理及现有驱动加载路径兼容。
5. 确认工程 Vivado 版本。参考镜像头为 2021.1，本轮 DCP 为 2025.2；优先交付 RTL 在 shell 对应工具版本下重建，不能假定新版本 DCP 可被旧版直接读取。

无需再索取一份相同驱动包或单独 bitstream；真正缺少的是上述可修改的计算侧封装与构建资料。拿到后将本端点接入、完成板级实现与时序检查，再沿已验证的驱动加载路径执行自研 W4A8 最小任务。
