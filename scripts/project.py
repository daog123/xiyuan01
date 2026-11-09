"""Unified source-based tests, implementation and evidence audit for ABI v5."""
import argparse,hashlib,json,os,re,shutil,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
PROFILE=ROOT/'config/system_profile.json'
MANIFEST=ROOT/'config/system_sources.txt'

def identity(files):
    return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}

def run(args,cwd,log,allow_failure=False):
    env=os.environ.copy()
    if Path(str(args[0])).name.lower() in ('powershell.exe','pwsh.exe'):
        # Do not pass PowerShell 7's module search path through Python to PS5.
        # Each shell must initialize its own built-in modules.
        env={k:v for k,v in env.items() if k.upper()!='PSMODULEPATH'}
    with log.open('w',encoding='utf-8') as out:
        p=subprocess.run([str(a) for a in args],cwd=cwd,stdout=out,stderr=subprocess.STDOUT,env=env)
    log.with_suffix(log.suffix+'.exit').write_text(str(p.returncode),encoding='ascii')
    text=log.read_text(encoding='utf-8',errors='replace')
    if p.returncode and not allow_failure:
        print(text[-7000:]);raise RuntimeError(f'command failed ({p.returncode}): {log}')
    return text

def valid_log(log,marker):
    return marker in log and not re.search(r'Fatal:|^ERROR:|CHECK_FAILED|_TIMEOUT',log,re.M)

def simulate(sources,tops,build,tools,marker):
    records=[]
    extras=[Path(__file__).resolve(),PROFILE,MANIFEST]+list((ROOT/'model').rglob('*.py'))+list((ROOT/'software').rglob('*.py'))
    for top in tops:
        work=build/top;work.mkdir(parents=True,exist_ok=True)
        for p in (build/'vectors').glob('*'):(work/p.name).write_bytes(p.read_bytes())
        hashes=identity(sources+extras)
        (work/'inputs.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
        run([tools/'xvlog.bat','--sv',*sources],work,work/'compile.log')
        run([tools/'xelab.bat',top,'-s','system_sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
        command=[tools/'xsim.bat','system_sim','-tclbatch',(ROOT/'scripts/run_w4a8_memory_xsim.tcl').as_posix()]
        log=run(command,work,work/'run.log');assert valid_log(log,marker),str(work)
        found=re.search(marker+r' [^\r\n]+',log);assert found,str(work)
        print(found[0],flush=True);records.append({'top':top,'result':found[0],'source_sha256':hashes})
        if top==tops[0]:
            for probe,expected in [('corrupt_expected','CHECK_FAILED'),('timeout_probe','FORCED_TIMEOUT')]:
                bad=run(command+['-testplusarg',probe],work,work/(probe+'.log'),allow_failure=True)
                verdict=int(not valid_log(bad,marker))
                assert expected in bad and verdict==1,'failure probe did not fail as expected'
                (work/(probe+'.verdict')).write_text(str(verdict)+'\n',encoding='ascii')
    return records

def test_suite(name,tools):
    build=ROOT/'build'/('system_v2' if name=='system' else 'attention_v2');build.mkdir(parents=True,exist_ok=True)
    verdict=build/'test_result.json';verdict.write_text('{"status":"RUNNING"}',encoding='utf-8')
    vec=build/'vectors'
    run([sys.executable,ROOT/'model'/('system_vectors.py' if name=='system' else 'attention_reference.py'),'--out',vec],ROOT,build/'reference.log')
    names=MANIFEST.read_text(encoding='utf-8-sig').splitlines()
    sources=[ROOT/'rtl'/(n+'.sv') for n in names]+[ROOT/'tb/llm_test_shells.sv',ROOT/'tb/system_axi_memory.sv',ROOT/'tb'/('tb_accelerator.sv' if name=='system' else 'tb_attention.sv')]
    if name=='system':sources.append(ROOT/'tb/tb_system_mixed.sv')
    tops=['tb_accelerator','tb_accelerator12','tb_accelerator32','tb_system_mixed'] if name=='system' else ['tb_attention','tb_attention3','tb_attention32','tb_attention_default','tb_attention_dma','tb_attention_dma3','tb_attention_dma32','tb_attention_dma_default']
    results=simulate(sources,tops,build,tools,'ACCELERATOR_TESTS_PASS' if name=='system' else 'ATTENTION_TESTS_PASS')
    result={'status':'PASS','simulations':results};verdict.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result

def test_projection(tools):
    build=ROOT/'build/projection_v4';build.mkdir(parents=True,exist_ok=True)
    verdict=build/'test_result.json';verdict.write_text('{"status":"RUNNING"}',encoding='utf-8')
    run([sys.executable,ROOT/'model/projection_reference.py','--out',build/'vectors'],ROOT,build/'reference.log')
    names=MANIFEST.read_text(encoding='utf-8-sig').splitlines()
    sources=[ROOT/'rtl'/(n+'.sv') for n in names]+[ROOT/'tb/system_axi_memory.sv',ROOT/'tb/tb_projected_attention.sv']
    simulations=simulate(sources,['tb_projected_attention','tb_projected_attention3','tb_projected_attention32','tb_projected_attention1'],build,tools,'PROJECTION_TESTS_PASS')
    result=dict(status='PASS',simulations=simulations);verdict.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


def test_qkv(tools):
    build=ROOT/'build/qkv_v5';build.mkdir(parents=True,exist_ok=True)
    verdict=build/'test_result.json';verdict.write_text('{"status":"RUNNING"}',encoding='utf-8')
    run([sys.executable,ROOT/'model/qkv_reference.py','--out',build/'vectors'],ROOT,build/'reference.log')
    names=MANIFEST.read_text(encoding='utf-8-sig').splitlines()
    sources=[ROOT/'rtl'/(n+'.sv') for n in names]+[ROOT/'tb/system_axi_memory.sv',ROOT/'tb/tb_qkv_attention.sv']
    simulations=simulate(sources,['tb_qkv_attention','tb_qkv_attention3','tb_qkv_attention32','tb_qkv_attention1'],build,tools,'QKV_TESTS_PASS')
    result=dict(status='PASS',simulations=simulations);verdict.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    return result


def implement(tools,build):
    work=build/'implementation';work.mkdir(parents=True,exist_ok=True)
    reference=work/'reference_routed.dcp'
    if (work/'routed.dcp').exists():shutil.copy2(work/'routed.dcp',reference)
    verdict=build/'implementation_result.json';verdict.write_text('{"status":"RUNNING"}',encoding='utf-8')
    profile=json.loads(PROFILE.read_text(encoding='utf-8'))
    if profile['top'] not in ['llm_top','llm_graph_top'] or profile['part']!='xcvu9p-flga2104-2L-e':
        raise ValueError('This verified implementation flow supports llm_top on xcvu9p-flga2104-2L-e')
    (work/'clock.xdc').write_text(f"create_clock -name core_clk -period {profile['clock_period_ns']} [get_ports clk]\n",encoding='ascii')
    names=MANIFEST.read_text(encoding='utf-8-sig').splitlines()
    files=[ROOT/'rtl'/(n+'.sv') for n in names]+[ROOT/'scripts/implement_system.tcl',PROFILE,MANIFEST,work/'clock.xdc']
    if reference.exists():files.append(reference)
    hashes=identity(files)
    (work/'inputs.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    l=profile['linear'];f=profile['ffn'];a=profile['attention']
    values=dict(ADDR_WIDTH=profile['address_width'],GROUP_SIZE=profile['group_size'],ROWS=l['rows'],COLS=l['cols'],
                TILE_K=l['tile_k'],MAX_M=l['max_m'],MAX_N=l['max_n'],MAX_K=l['max_k'],MAX_H=f['max_h'],CAPACITY=f['bridge_capacity'],
                MAX_DIM=a['max_dimension'],MAX_TOKENS=a['max_tokens'])
    generic_args=[item for k,v in values.items() for item in (k,str(v))]
    log=run([tools/'vivado.bat','-mode','batch','-source',(ROOT/'scripts/implement_system.tcl').as_posix(),'-tclargs','--top',profile['top'],*generic_args],work,work/'console.log')
    assert 'SYSTEM_OOC_IMPLEMENTATION_PASS' in log
    timing=(work/'timing_values.txt').read_text(encoding='ascii')
    m=re.search(r'WNS=([\d.-]+) WHS=([\d.-]+)',timing);assert m
    assert float(m[1])>=0 and float(m[2])>=0
    route=(work/'route_status.rpt').read_text(encoding='utf-8',errors='replace')
    r={k:int(re.search(r'# of '+label+r'\.+\s*:\s*(\d+)',route)[1]) for k,label in
       [('routable','routable nets'),('fully_routed','fully routed nets'),('errors','nets with routing errors')]}
    assert r['errors']==0 and r['routable']==r['fully_routed'],r
    result=dict(status='PASS',top=profile['top'],WNS_ns=float(m[1]),WHS_ns=float(m[2]),route=r,source_sha256=hashes)
    verdict.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print('PROJECT_IMPLEMENTATION_PASS',timing.strip(),flush=True)

def audit(build):
    assert int((build/'software.log.exit').read_text(encoding='ascii'))==0
    assert re.search(r'\bOK\b',(build/'software.log').read_text(encoding='utf-8'))
    paths=[ROOT/'build/system_v2/test_result.json',ROOT/'build/attention_v2/test_result.json',ROOT/'build/projection_v4/test_result.json',ROOT/'build/qkv_v5/test_result.json',build/'implementation_result.json']
    for p in paths:
        data=json.loads(p.read_text(encoding='utf-8'));assert data['status']=='PASS',str(p)
        for group in data.get('simulations',[data]):
            for name,digest in group['source_sha256'].items():assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'stale evidence: '+name
    print('PROJECT_CURRENT_SOURCE_EVIDENCE_PASS')

def main():
    p=argparse.ArgumentParser();p.add_argument('command',choices=['test','implement','status','legacy'])
    p.add_argument('--vivado-bin',type=Path,default=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin')))
    p.add_argument('--suite',choices=['all','system','attention','projection','qkv'],default='all');args=p.parse_args()
    build=ROOT/'build/project_v2';build.mkdir(parents=True,exist_ok=True)
    if args.command=='test':
        result={'status':'RUNNING'};(build/'test_result.json').write_text(json.dumps(result),encoding='utf-8')
        run([sys.executable,'-m','unittest','software.test_w4a8_software','software.test_w4a8_memory_task','software.test_system','-v'],ROOT,build/'software.log')
        for name in (['system','attention','projection','qkv'] if args.suite=='all' else [args.suite]):result[name]=test_qkv(args.vivado_bin) if name=='qkv' else test_projection(args.vivado_bin) if name=='projection' else test_suite(name,args.vivado_bin)
        result['status']='PASS';(build/'test_result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
        print('PROJECT_VALIDATION_PASS',flush=True)
    elif args.command=='implement':implement(args.vivado_bin,build)
    elif args.command=='status':audit(build)
    else:
        shell=shutil.which('pwsh.exe') or shutil.which('powershell.exe')
        if not shell:raise RuntimeError('PowerShell is required for legacy regression')
        run([shell,'-NoProfile','-ExecutionPolicy','Bypass','-File',ROOT/'scripts/run_team_integration.ps1','-VivadoBin',args.vivado_bin],ROOT,build/'legacy.log')
        print('PROJECT_LEGACY_REGRESSION_PASS',flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:print('PROJECT_VALIDATION_FAILED:',error,file=sys.stderr);sys.exit(1)
