from pathlib import Path
import argparse,csv,hashlib,json,os,random,shutil,subprocess,sys,time
sys.stdout.reconfigure(encoding='utf-8')

HERE=Path(__file__).resolve().parent
ROOT=Path('E:/speed-up')
TOOLS=Path('E:/AMDDesignTools/2025.2/Vivado/bin')
PY=Path(sys.executable)

def run(command,work,log,timeout=300,allow_failure=False):
    started=time.monotonic()
    result=subprocess.run([x.as_posix() if isinstance(x,Path) else str(x) for x in command],cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
    output=result.stdout.decode('utf-8',errors='replace')
    (work/log).write_text(output,encoding='utf-8')
    if result.returncode and not allow_failure:
        print(output[-6000:],flush=True)
        raise RuntimeError(f'{command[0]} failed: {result.returncode}')
    return output

def rounding(value):
    rounded=(abs(value)+128)>>8
    return min(2147483647,rounded) if value>=0 else -min(2147483648,rounded)

def prepare():
    target=HERE/'stream';target.mkdir(exist_ok=True)
    common=json.loads((ROOT/'build/controlled_compute/cases.json').read_text())
    cases=[dict(c,name='controlled_'+str(c['k'])) for c in common if c['m']==1]
    rng=random.Random(20261028)
    for i,(n,k) in enumerate([(1,1),(3,3),(7,7),(8,8),(9,31),(17,32),(63,33),(64,63),(17,65),(8,128),(64,512),(64,2048),(64,4096)]):
        ng=(k+31)//32
        a=[[rng.randrange(-128,128) for q in range(k)]]
        w=[[rng.randrange(-8,8) for c in range(n)] for q in range(k)]
        sx=[[rng.randrange(1,4097) for g in range(ng)]]
        sw=[[rng.randrange(1,4097) for c in range(n)] for g in range(ng)]
        cases.append(dict(name='random_'+str(i),m=1,n=n,k=k,a=a,weights=w,sx=sx,sw=sw))
    for sign in (-1,1):
        n,k=9,37;ng=(k+31)//32
        cases.append(dict(name='saturate_'+str(sign),m=1,n=n,k=k,a=[[127*sign]*k],weights=[[7]*n for _ in range(k)],sx=[[65535]*ng],sw=[[65535]*n for _ in range(ng)]))
    cases.append(dict(name='zero',m=1,n=17,k=65,a=[[0]*65],weights=[[7]*17 for _ in range(65)],sx=[[65535]*3],sw=[[65535]*17 for _ in range(3)]))
    lines=[str(len(cases))];manifest=[]
    for cid,c in enumerate(cases):
        n,k=c['n'],c['k'];ng=(k+31)//32
        beats=[];plane_bytes=dict(W=0,A=0,SX=0,SW=0)
        def section(values,plane):
            plane_bytes[plane]+=len(values)
            for j in range(0,len(values),8):
                part=values[j:j+8];word=sum((v&255)<<(8*q) for q,v in enumerate(part))
                beats.append(f'{word:016x} {(1<<len(part))-1:02x}')
        section(c['a'][0],'A')
        section([b for s in c['sx'][0] for b in (s&255,s>>8)],'SX')
        for nt in range(0,n,8):
            nl=min(8,n-nt)
            for g in range(ng):
                start=g*32;kl=min(32,k-start)
                weights=[]
                for col in range(nt,nt+nl):
                    for q in range(0,kl,2):
                        lo=c['weights'][start+q][col]&15
                        hi=(c['weights'][start+q+1][col]&15) if q+1<kl else 0
                        weights.append(lo|(hi<<4))
                section(weights,'W')
                section([b for s in c['sw'][g][nt:nt+nl] for b in (s&255,s>>8)],'SW')
        golden=[]
        for col in range(n):
            total=0
            for g in range(ng):
                start=g*32;kl=min(32,k-start)
                partial=sum(c['a'][0][start+q]*c['weights'][start+q][col] for q in range(kl))
                total+=partial*c['sx'][0][g]*c['sw'][g][col]
            golden.append(rounding(total))
        if 'output' in c: assert golden==c['output']
        lines.append(f"{cid} {n} {k} {len(beats)} {plane_bytes['W']} {plane_bytes['A']} {plane_bytes['SX']} {plane_bytes['SW']}")
        lines.extend(beats);lines.extend(str(v) for v in golden)
        for g in range(ng):
            for col in range(n):
                lines.append(str(sum(c['a'][0][q]*c['weights'][q][col] for q in range(g*32,min(k,g*32+32)))))
        manifest.append(dict(id=cid,name=c['name'],N=n,K=k,beats=len(beats),bytes=plane_bytes))
    (target/'vectors.txt').write_text('\n'.join(lines)+'\n',encoding='ascii')
    (target/'cases.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (target/'cases_full.json').write_text(json.dumps(cases)+'\n')

def baseline():
    for name,wave in [('frozen',ROOT/'tb/baselines/w4a8_wave_round4.sv'),('current',ROOT/'rtl/w4a8_wave.sv')]:
        work=HERE/name;work.mkdir(exist_ok=True)
        shutil.copyfile(ROOT/'build/controlled_compute/own_after/vectors.txt',work/'vectors.txt')
        shutil.copyfile(wave,work/'wave.sv')
        shutil.copyfile(ROOT/'tb/tb_w4a8_wave.sv',work/'testbench.sv')
        if name=='frozen':
            text=(work/'testbench.sv').read_text().replace('.MULTIROW_FOLD(MULTIROW_FOLD),','')
            (work/'testbench.sv').write_text(text)
        wrapper='module own_controlled;tb_w4a8_wave #(.ROWS(8),.COLS(8),.COMPACT_SLOTS(1),.MODES(1),.MAX_DATA(262144),.TILE_K(32),.EFFECTIVE_DRAIN(1),.GEMV_FOLD(1),.COPY_LANES(8),.POST_LANES(2)) test();endmodule\n'
        if name=='frozen': wrapper=wrapper.replace('.TILE_K(32)', '.MULTIROW_FOLD(0),.TILE_K(32)')
        (work/'wrapper.sv').write_text(wrapper)
        sources=[ROOT/'rtl'/f'{p}.sv' for p in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack']]+[work/'wave.sv',ROOT/'tb/w4a8_reuse_memory.sv',work/'testbench.sv',work/'wrapper.sv']
        run([TOOLS/'xvlog.bat','--sv',*sources],work,'compile.log')
        run([TOOLS/'xelab.bat','own_controlled','-s','ownsim','-timescale','1ns/1ps'],work,'elaborate.log')
        out=run([TOOLS/'xsim.bat','ownsim','-tclbatch',ROOT/'scripts/run_xsim.tcl'],work,'run.log')
        assert 'W4A8_WAVE_TESTS_PASS' in out and 'W4A8_WAVE_CHECK_FAILED' not in out
        with (work/'results.csv').open() as f: data=list(csv.DictReader(f))
        r=next(r for r in data if (r['M'],r['N'],r['K'])==('1','64','2048'))
        assert r['total_cycles']=='10615',r
        print(name,'PASS cycles='+r['total_cycles'],flush=True)

def stream():
    work=HERE/'stream';work.mkdir(exist_ok=True)
    sources=[HERE/'rtl/w4a8_gemv_stream.sv',HERE/'tb_stream.sv']
    run([TOOLS/'xvlog.bat','--sv',*sources],work,'compile.log')
    run([TOOLS/'xelab.bat','tb_stream','-s','streamsim','-timescale','1ns/1ps'],work,'elaborate.log')
    out=run([TOOLS/'xsim.bat','streamsim','-tclbatch',ROOT/'scripts/run_xsim.tcl'],work,'run.log')
    print(out[-4500:],flush=True)
    assert 'STREAM_TESTS_PASS' in out and 'STREAM_FAILED' not in out
    original=(work/'results.csv').read_bytes()
    try:
        bad=run([TOOLS/'xsim.bat','streamsim','-tclbatch',ROOT/'scripts/run_xsim.tcl','-testplusarg','corrupt_expected'],work,'negative.log',allow_failure=True)
        assert 'STREAM_FAILED numeric output' in bad and 'STREAM_TESTS_PASS' not in bad
    finally: (work/'results.csv').write_bytes(original)
    with (work/'results.csv').open() as f: data=list(csv.DictReader(f))
    r=next(r for r in data if r['case_id']=='1' and r['mode']=='0')
    # Identify by case manifest rather than relying on generated ordering.
    manifest=json.loads((work/'cases.json').read_text())
    target=next(c for c in manifest if c['name']=='controlled_2048')
    r=next(r for r in data if int(r['case_id'])==target['id'] and r['mode']=='0')
    result=dict(status='PASS',selected=r,simulation_cases=len(data),negative_probe=True,
        source_sha256={str(p.relative_to(HERE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[HERE/'run.py',work/'vectors.txt']})
    (work/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print('SELECTED',json.dumps(r),flush=True)

def implement():
    work=Path(os.environ.get('ROUND8_OOC_WORK',HERE/'implementation'));work.mkdir(parents=True,exist_ok=True)
    sources=[HERE/'rtl/w4a8_gemv_stream.sv',HERE/'implement.tcl']
    identity={str(p.relative_to(HERE)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (work/'source_sha256.json').write_text(json.dumps(identity,indent=2)+'\n')
    script=HERE/'implement.tcl'
    if work!=HERE/'implementation':
        (work/'rtl').mkdir(exist_ok=True)
        shutil.copyfile(sources[0],work/'rtl/w4a8_gemv_stream.sv')
        shutil.copyfile(script,work/'implement.tcl');script=work/'implement.tcl'
    try:
        out=run([TOOLS/'vivado.bat','-mode','batch','-source',script],work,'run.log',timeout=1800)
    finally:
        if work!=HERE/'implementation':
            target=HERE/'implementation_ascii';target.mkdir(exist_ok=True)
            for p in work.iterdir():
                if p.suffix in ('.rpt','.log','.txt','.json'): shutil.copyfile(p,target/p.name)
    assert 'ROUND8_OOC_PASS' in out
    print(out[-2500:],flush=True)

def open_baseline():
    work=HERE/'open64';work.mkdir(exist_ok=True)
    base=ROOT/'build/upstream_compute/sources/openTPU'
    shutil.copyfile(ROOT/'build/controlled_compute/common_vectors.txt',work/'common_vectors.txt')
    shutil.copyfile(ROOT/'build/controlled_compute/open64/mxu_xsim.sv',work/'mxu_xsim.sv')
    shutil.copyfile(ROOT/'experiments/controlled_compute/tb_opentpu_controlled.sv',work/'testbench.sv')
    sources=[base/p for p in ['rtl/top/otpu_pkg.sv','rtl/vpu/otpu_fp.sv','rtl/vpu/otpu_fpipe.sv','rtl/tech/generic/otpu_tech_dsp.sv','rtl/tech/generic/otpu_tech_ram.sv']]+[work/'mxu_xsim.sv',work/'testbench.sv']
    identity={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[work/'common_vectors.txt']}
    run([TOOLS/'xvlog.bat','--sv',*sources],work,'compile.log')
    run([TOOLS/'xelab.bat','tb_opentpu_controlled','-s','open64','-timescale','1ns/1ps'],work,'elaborate.log')
    out=run([TOOLS/'xsim.bat','open64','-tclbatch',ROOT/'scripts/run_xsim.tcl'],work,'run.log')
    assert 'OPENTPU_CORE_PASS' in out and 'OPENTPU_CORE_FAILED' not in out
    with (work/'opentpu_results.csv').open() as f: data=list(csv.DictReader(f))
    r=next(r for r in data if (r['M'],r['N'],r['K'])==('1','64','2048'))
    assert r['cycles']=='9564',r
    (work/'result.json').write_text(json.dumps(dict(status='PASS',selected=r,source_sha256=identity),indent=2)+'\n')
    print('OPEN_BASELINE_PASS cycles=9564 cases='+str(len(data)),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['prepare','baseline','stream','implement','open_baseline']);args=parser.parse_args()
    globals()[args.action]()
