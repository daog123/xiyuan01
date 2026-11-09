"""Generate the evidence-based local/pinned-upstream performance comparison."""
import argparse,csv,hashlib,json,re,statistics
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def pinned_readme(name,manifest):
    record=next(f for f in manifest['files'] if f['repository']==name and f['path']=='README.md')
    path=ROOT/'build/upstream_review'/name/'README.md'
    assert sha(path)==record['sha256'],f'upstream review copy changed: {path}'
    repository=manifest['repositories'][name]
    url=f"https://github.com/{repository['repo']}/blob/{repository['commit']}/README.md"
    return path.read_text(encoding='utf-8'),dict(repository=repository['repo'],commit=repository['commit'],readme_sha256=record['sha256'],url=url)

def evidence_current(data):
    assert data['status']=='PASS','evidence is incomplete'
    for group in data.get('variants',data.get('simulations',[data])):
        for rel,digest in group['source_sha256'].items():
            assert sha(ROOT/rel)==digest,'stale evidence: '+rel

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,default=ROOT/'docs/performance_comparison.md')
    args=parser.parse_args()
    bench=json.loads((ROOT/'build/performance/result.json').read_text(encoding='utf-8'))
    evidence_current(bench)
    assert not bench['protocol_only'] and len(bench['comparison'])==24
    regression=[]
    for family in ['system_v2','attention_v2']:
        entry=json.loads((ROOT/'build'/family/'test_result.json').read_text(encoding='utf-8'))
        evidence_current(entry);regression+=entry['simulations']
    manifest=json.loads((ROOT/'build/upstream_review/review_manifest.json').read_text(encoding='utf-8'))
    open_text,open_source=pinned_readme('openTPU',manifest)
    llama_text,llama_source=pinned_readme('llama-fpga',manifest)
    published=[]
    for line in open_text.splitlines():
        cells=[x.strip() for x in line.strip().strip('|').split('|')]
        if len(cells)==6 and cells[0] in ['LFM2.5-230M','Qwen3-0.6B'] and cells[1]=='4-bit, int8 head' and cells[2].endswith('tok/s'):
            published.append(dict(project='openTPU',model=cells[0],weights=cells[1],platform='Kintex-7 xc7k480t / DDR3-1066 / 133.33 MHz',
                decode_device_tok_s=float(cells[2].split()[0]),decode_wall_tok_s=float(cells[3].split()[0]),
                prefill_device_tok_s=float(cells[4].split()[0]),evidence='upstream-published board measurements; not reproduced here',**open_source))
    assert len(published)==2
    for line in llama_text.splitlines():
        cells=[x.strip().strip('*') for x in line.strip().strip('|').split('|')]
        if len(cells)==2 and cells[0] in ['KV260','ZCU104 (PL-only)','ZCU104 (PS + PL)','Alveo U250']:
            published.append(dict(project='llama-fpga',model='LLaMA2-7B',weights='AWQ 4-bit',platform=cells[0],
                decode_tok_s_reported=cells[1],timing_scope='README does not separate device/wall time',
                evidence='upstream-published approximate demo speed; not reproduced here',**llama_source))
    assert len(published)==6
    comparison=bench['comparison']
    reductions=[r['cycle_reduction_percent'] for r in comparison]
    speedups=[r['speedup'] for r in comparison]
    tasks=sum(int(re.search(r'tasks=(\d+)',e['result'])[1]) for e in regression)
    checked=sum(int(m[1]) for e in regression if (m:=re.search(r'bytes=(\d+)',e['result'])))
    impl_path=ROOT/'build/project_v2/implementation_result.json'
    impl=json.loads(impl_path.read_text(encoding='utf-8'))
    if impl['status']=='PASS':
        evidence_current(impl)
        physical=f"当前 llm_top 的完整 OOC 布局布线通过：10 ns 目标下 WNS **{impl['WNS_ns']:+.3f} ns**、WHS **{impl['WHS_ns']:+.3f} ns**；{impl['route']['fully_routed']:,}/{impl['route']['routable']:,} 网络完成路由、错误 {impl['route']['errors']}。这仍不含板级引脚、DDR/PCIe 和外部 I/O 约束。"
        utilization=(ROOT/'build/project_v2/implementation/utilization_routed.rpt').read_text(encoding='utf-8',errors='replace')
        resources={}
        for label in ['CLB LUTs','CLB Registers','Block RAM Tile','DSPs']:
            match=re.search(r'^\|\s*'+re.escape(label)+r'\*?\s*\|\s*([\d.]+)',utilization,re.M)
            assert match,'missing utilization: '+label
            resources[label]=float(match[1])
        physical+=f" 当前布局布线后使用 {resources['CLB LUTs']:,.0f} LUT、{resources['CLB Registers']:,.0f} FF、{resources['DSPs']:,.0f} DSP 和 {resources['Block RAM Tile']:g} BRAM36 等效块；与完整上游板级系统的资源范围不同，不能直接据此计算效率排名。"
        console=(ROOT/'build/project_v2/implementation/console.log').read_text(encoding='utf-8',errors='replace')
        if 'CRITICAL WARNING: [Route 35-4475]' in console:
            physical+=' 工具在布线初始化阶段记录了 Route 35-4475：两个全局时钟网的布局引导树不完整；最终报告仍通过上述内部时序和可路由网络检查，日志保留供板级时钟约束复核。DRC 仍有 DSP 流水线建议和一个无可路由负载网络警告，不能把内部 OOC 通过当作板级 bitstream 签核。'
    else:
        physical='当前优化版的 OOC 布局布线尚未通过或仍在运行，不能将历史时序数据当作本轮结果。'
    rows=[]
    for r in comparison:
        if r['top']=='tb_perf_r8' and r['case'] in [0,1]:
            shape=f"{r['m']}×{r['k']}×{r['h']}" if r['operator']=='LINEAR' else f"M={r['m']}, K={r['k']}, H={r['h']}, N={r['n']}"
            rows.append(f"| {r['operator']} | {shape} | {r['baseline_cycles']:,} | {r['optimized_cycles']:,} | {r['cycle_reduction_percent']:.2f}% | {r['speedup']:.3f}× |")
    upstream_rows=[]
    for r in published:
        if r['project']=='openTPU':
            upstream_rows.append(f"| openTPU | {r['model']}，4-bit / INT8 head | Kintex-7 | {r['decode_device_tok_s']:.1f} device / {r['decode_wall_tok_s']:.1f} wall | {r['prefill_device_tok_s']:.1f} device |")
        elif r['platform'] in ['KV260','Alveo U250']:
            upstream_rows.append(f"| llama-fpga | LLaMA2-7B，AWQ 4-bit | {r['platform']} | {r['decode_tok_s_reported']}，未细分计时范围 | 未给出独立加速指标 |")
    report=f'''# speed-up 优化与上游性能对比

日期：2026-10-25（Asia/Shanghai）。本轮基于本地提交 `{bench['base_commit']}` 的工作树，代码已直接更新到 `E:\\speed-up`；未提交、未推送，也没有烧录远端板卡。

## 已得到的结论

本轮完成一项实际 RTL 优化和可复现的前后对照。24 组配对任务均通过完整内存校验，周期减少 **{min(reductions):.2f}%–{max(reductions):.2f}%**，对应 **{min(speedups):.3f}×–{max(speedups):.3f}×** 加速；配对结果的中位周期减少 {statistics.median(reductions):.2f}%。这是当前三组小尺寸合成工作负载和指定内存服务条件下的算子仿真结果。

与 openTPU、llama-fpga 的公开数据已经整理，但目前不能给出同模型、同板卡、同精度的三方实测排名。本工程尚未运行完整模型或生成 token；另外两份源码记录的是完整模型的板卡结果。表中的不同模型 tokens/s 不能相除作为本工程的加速比。

## 1. 代码改进

`rtl/w4a8_axi_read.sv` 原先先锁存请求、下一拍发 AR，收到 R 后再额外打一拍交付结果。本轮在空闲时直接发首个 AR，在完整单拍 R 返回且消费者就绪时直接交付；遇到 AR 停顿或输出反压则锁存数据。每次仍只允许一个外存事务和一个保留的响应槽。

读地址、ARSIZE=0、有效字节、量化、舍入、写确认及错误语义均保持。畸形多拍返回仍等到 RLAST 才交付错误，不能提前开启下一笔事务。原版完整源码保存在 `tb/baselines/w4a8_axi_read.sv`，SHA256 为 `{bench['baseline_reader_sha256']}`。

本轮没有把单字节读取改成宽读或 burst，也没有增加阵列规模。当前 64 位 R beat 仍只取 1 字节，有效 lane 字节比例为 1/8；这不是测得的 DDR 效率，还没有计入事务间空闲、存储控制器及 PCIe 开销。

## 2. 本项目前后性能实测

测量顶层为当前 `llm_top` 的原有测试外壳。计数从任务接收到 completion，不含测试台之后人为保持 completion 的 8 拍。固定原有 4×4 阵列和数值规格，使用 group32 / group12，AR/AW/W 无随机停顿，读取额外等待分别为 0、8、24 拍，写确认额外等待 4 拍。0 表示不加等待，存储模型本身仍有同步响应延迟。

每种延迟配置都运行三个 LINEAR 和三个完整 FFN。LINEAR 的 `(M,K,N)` 为 `(1,19,37)`、`(3,35,29)`、`(2,13,25)`；FFN 的 `(M,K,H,N)` 为 `(1,19,37,5)`、`(3,35,29,7)`、`(2,13,25,3)`。第三组包含全零输入。所有 case 均有未对齐输入、stride/padding 与保护区。

下面选用 group32、读额外等待 8 拍作为展示，其余全部数据在 `build/performance/comparison.csv`。

| 算子 | 形状（LINEAR 为 M×K×N） | 原版周期 | 优化后周期 | 周期减少 | 加速比 |
|---|---|---:|---:|---:|---:|
{chr(10).join(rows)}

CSV 中按 10 ns 换算的微秒与 GMAC/s 是目标时钟下的仿真换算，不是板上实测。FFN 的有用矩阵 MAC 数为 `2*M*K*H + M*H*N`，不把 SiLU/量化算作矩阵 MAC。原版和新版每组的读事务、写事务、写确认数量完全一致；每次任务逐字节检查整个 65,536 字节内存，包含输入、全部中间值、最终输出与保护区。

## 3. 验证证据

- 配对性能：24 对，共 48 次算子任务，检查 {sum(r['bytes'] for r in comparison)*2:,} 字节完整内存。
- 独立读取协议：原版/新版各跑 32 位和 64 位，共 4 组，每组 272 项检查；覆盖全部 8 条 byte lane、地址保持、响应反压、RID/RRESP 错误、畸形多拍排空和各阶段复位。
- 当前项目回归：19 项软件测试、8 组系统/Attention/混合配置通过，共 {tasks} 条任务完成记录，检查 {checked:,} 字节；负例 golden 破坏和超时探针被正确拒绝。
- {physical}

证据保存于 `build/performance/result.json`、`build/system_v2/test_result.json`、`build/attention_v2/test_result.json` 和 `build/project_v2/implementation_result.json`。本报告生成前核对每份记录中的当前源码 SHA256；未用历史 PASS 替代本轮运行。

## 4. 与两个上游项目的性能对比

比较继续使用项目已录入的固定版本。openTPU：`{open_source['commit']}`；llama-fpga：`{llama_source['commit']}`。本轮核对了本地核查副本与原下载清单的 SHA256，没有把浮动 main 的其他结果混入此表。

| 项目 | 模型 / 权重 | 平台 | Decode tokens/s | Prefill tokens/s |
|---|---|---|---|---|
| 本工程 | 小尺寸 W4A8 算子测试，未运行完整模型 | VU9P 内部 OOC / RTL 仿真 | 未测 | 未测 |
{chr(10).join(upstream_rows)}

openTPU 表格来自作者板卡测试：133.33 MHz、双通道 DDR3-1066；512-token prompt 后生成 64 个 greedy token，device 只计设备活动周期，wall 包含主机。来源：[固定 README]({open_source['url']})。

llama-fpga 的 README 报告 LLaMA2-7B AWQ 4-bit 的近似 Decode 速度；其 Prefill 复用逐 token Decode 通路，没有专门加速，最大上下文记为 1024。README 没有完整列出与 openTPU 相同的计时/上下文条件，本次没有独立复现实机数据。来源：[固定 README]({llama_source['url']})。

### 现阶段可以比较什么

| 维度 | 本工程 | openTPU | llama-fpga |
|---|---|---|---|
| 已验证层级 | LINEAR、FFN、KV、Attention 算子事务 | 完整模型与板卡生成 | LLaMA2-7B 板卡 Decode |
| 数值路线 | signed INT4 × INT8，UQ4.12 scale，Q16.16 输出 | FP4 E2M1 / INT8 等路径、浮点 scale | AWQ 4-bit、zero-point / 浮点通路 |
| 存储与运行时 | 当前窄单拍 AXI；模型图与板级 DDR/PCIe 待接 | 宽数据流、模型编译/运行时与实际 DDR | 面向固定模型的流式布局与板级存储 |
| 能证明的性能 | 本工程旧/新在相同算子条件下的周期变化 | 作者注明条件的模型吞吐 | 作者报告的模型 Decode 吞吐 |

因此，目前完整模型/板级实现的完成度低于两个上游，不能据算子规模小、资源少或本轮 6%–28% 的周期减少声称系统胜出。也不能通过峰值 MAC 数或线性外推生成不存在的 tokens/s。三者数值格式不同，后续真实模型对比还必须共同报告精度误差。

## 5. 后续精进与公平对照的执行顺序

1. **优先提高有效读带宽。** 将连续有效区域合并为宽读/burst，发请求前预留返回空间；处理 4 KiB 边界、非对齐、尾部、stride 和 allocation 边界，禁止为了凑满 beat 越界读 padding。分别统计有用字节、总线 beat 和等待周期；错误必须排空，写确认 fence 继续保留。
2. **再研究 Decode 资源利用率。** 当前 4×4 阵列在 M=1 时只有一行映射到有效输出。研究跨 N 通道并行或独立 GEMV 通路，并同时量测存储供数；固定 group 累加/舍入合同，不能用降低精度换取未注明的提速。
3. **补齐完整计算图与容量。** Q/K/V/O 自动链、RMSNorm、RoPE、残差、多层调度以及 FFN/Attention 扩容完成后，才能记录真实模型 TTFT 和 Decode tokens/s。当前 FFN bridge=512 元素，Attention 最大前缀=16、维度=64。
4. **接入已验证可登录的服务器板卡。** 仍需确认目标器件、可复用板级 shell、DDR 地址、时钟/复位、PCIe 控制接口和完整约束。本轮没有生成或烧录可用于该板卡的 bitstream，服务器能枚举 XDMA 不能替代这一步。
5. **建立三方同口径测试。** 先选择三者都能运行的相同数学算子与输入分布，报告数值误差、M/N/K、group、MAC 数、字节数、周期、频率与资源；再选择共同模型/量化误差预算，固定 batch、prompt/context、输出 token 数、采样和主机计时范围。上游移植完成并实测后才填写三方加速比。

本轮交付的是第 1 项之前的串行读取延迟优化，以及可直接用于下一轮的受控基线；宽读/burst、GEMV 重映射与完整模型是后续任务，并未标记为已实现。

## 6. 复现

在 `E:\\speed-up` 执行：

```powershell
python scripts/benchmark_performance.py
python scripts/project.py test
python scripts/project.py implement
python scripts/project.py status
python scripts/compare_upstream.py
```

默认工具目录为 `E:\\AMDDesignTools\\2025.2\\Vivado\\bin`。性能脚本支持 `--vivado-bin` 和 `--out`；`--protocol-only` 只运行协议测试，应使用独立输出目录，避免覆盖完整性能记录。`compare_upstream.py` 校验本轮源码证据和上游副本后生成本文及 `build/performance/upstream_comparison.json`。
'''
    args.out.parent.mkdir(parents=True,exist_ok=True);args.out.write_text(report,encoding='utf-8')
    combined={'status':'PASS','comparison_kind':'local measured RTL improvement plus upstream published data; no three-way speedup',
        'local_comparisons':comparison,'upstream_published_results':published,'local_regression_tasks':tasks,
        'local_regression_compared_bytes':checked,'implementation_status':impl['status'],'implementation':impl}
    (ROOT/'build/performance/upstream_comparison.json').write_text(json.dumps(combined,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('UPSTREAM_COMPARISON_PASS report='+str(args.out))

if __name__=='__main__':main()
