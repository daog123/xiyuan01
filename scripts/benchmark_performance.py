"""Rebuild baseline/current RTL, check complete memory images and compare cycles.

Published upstream token/s values are deliberately not mixed into this operator
benchmark. The baseline reader is the exact pre-optimization source snapshot.
"""
import argparse,csv,datetime,hashlib,json,os,re,subprocess,sys
from pathlib import Path
import project

ROOT=project.ROOT
BASELINE_SHA='a5a6d7d7d523bddd7ae411b2fcc729ca5a243d08cd06b2cc0fe610fe263cf62c'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vivado-bin',type=Path,default=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin')))
    parser.add_argument('--out',type=Path,default=ROOT/'build/performance')
    parser.add_argument('--protocol-only',action='store_true')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    result_file=out/'result.json'
    result_file.write_text('{"status":"RUNNING"}\n',encoding='utf-8')
    baseline=ROOT/'tb/baselines/w4a8_axi_read.sv'
    assert digest(baseline)==BASELINE_SHA,'baseline was modified'
    tools=args.vivado_bin
    sources=[ROOT/'rtl'/(n+'.sv') for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines() if n.strip()]
    bench=[ROOT/'tb/llm_test_shells.sv',ROOT/'tb/system_axi_memory.sv',ROOT/'tb/tb_accelerator.sv',ROOT/'tb/tb_axi_read_protocol.sv']
    extras=[Path(__file__),ROOT/'scripts/project.py',project.PROFILE,project.MANIFEST]+list((ROOT/'model').rglob('*.py'))
    if not args.protocol_only:
        project.run([sys.executable,ROOT/'model/system_vectors.py','--out',out/'vectors'],ROOT,out/'reference.log')
    all_rows=[];variants=[]
    for name in ['baseline','optimized']:
        work=out/name;work.mkdir(parents=True,exist_ok=True)
        selected=[baseline if name=='baseline' and p.name=='w4a8_axi_read.sv' else p for p in sources]
        if args.protocol_only:
            selected=[baseline if name=='baseline' else ROOT/'rtl/w4a8_axi_read.sv']
            selected_bench=[ROOT/'tb/tb_axi_read_protocol.sv']
        else:
            selected_bench=bench
            for p in (out/'vectors').glob('*'):(work/p.name).write_bytes(p.read_bytes())
        hashes=project.identity(selected+selected_bench+extras)
        (work/'inputs.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
        project.run([tools/'xvlog.bat','--sv',*selected,*selected_bench],work,work/'compile.log')
        tops=['tb_axi_read_protocol','tb_axi_read_protocol32']
        if not args.protocol_only:tops+=['tb_perf_r0','tb_perf_r8','tb_perf_r24','tb_perf_g12']
        records=[]
        for top in tops:
            project.run([tools/'xelab.bat',top,'-s',top+'_sim','-timescale','1ns/1ps'],work,work/(top+'.elaborate.log'))
            log=project.run([tools/'xsim.bat',top+'_sim','-tclbatch',(ROOT/'scripts/run_w4a8_memory_xsim.tcl').as_posix()],work,work/(top+'.run.log'))
            marker='READ_PROTOCOL_PASS' if top.startswith('tb_axi') else 'PERFORMANCE_TESTS_PASS'
            assert project.valid_log(log,marker),work/top
            match=re.search(marker+r' [^\r\n]+',log);assert match
            print(name,top,match[0],flush=True);records.append({'top':top,'result':match[0]})
            for record in re.findall(r'PERF_RECORD ([^\r\n]+)',log):
                row={k:int(v) for k,v in re.findall(r'(\w+)=(-?\d+)',record)}
                row['variant']=name;row['top']=top;all_rows.append(row)
            if not top.startswith('tb_axi'):
                assert sum(r['variant']==name and r['top']==top for r in all_rows)==6,'missing jobs'
        variants.append({'name':name,'source_sha256':hashes,'simulations':records})
    comparison=[]
    profile=json.loads(project.PROFILE.read_text(encoding='utf-8'))
    if not args.protocol_only:
        shapes=json.loads((out/'vectors/manifest.json').read_text(encoding='utf-8'))
        for old in [r for r in all_rows if r['variant']=='baseline']:
            new=next(r for r in all_rows if r['variant']=='optimized' and (r['top'],r['opcode'],r['case'])==(old['top'],old['opcode'],old['case']))
            for field in ['reads','writes','acks','bytes','group','read_delay','write_delay']:
                assert old[field]==new[field],f'work changed: {field}'
            assert old['writes']==old['acks'],'completion before write acknowledgments'
            assert 0<new['cycles']<old['cycles'],'no improvement or invalid counter'
            shape=next(s for s in shapes if (s['group'],s['case'])==(old['group'],old['case']))
            m,k,h,n=(shape[s] for s in ['m','k','h','n'])
            macs=m*k*h if old['opcode']==0 else 2*m*k*h+m*h*n
            item={k:v for k,v in old.items() if k not in ['variant','cycles']}
            item.update(operator='LINEAR' if old['opcode']==0 else 'FFN',m=m,k=k,h=h,n=h if old['opcode']==0 else n,
                baseline_cycles=old['cycles'],optimized_cycles=new['cycles'],cycles_saved=old['cycles']-new['cycles'],
                speedup=old['cycles']/new['cycles'],cycle_reduction_percent=100*(1-new['cycles']/old['cycles']),
                baseline_us_at_target=old['cycles']*profile['clock_period_ns']/1000,
                optimized_us_at_target=new['cycles']*profile['clock_period_ns']/1000,
                useful_matrix_macs=macs,optimized_gmac_s_at_target=macs/(new['cycles']*profile['clock_period_ns']),
                clock_period_ns=profile['clock_period_ns'])
            comparison.append(item)
        assert len(comparison)==24
        with (out/'comparison.csv').open('w',encoding='utf-8-sig',newline='') as stream:
            writer=csv.DictWriter(stream,fieldnames=list(comparison[0]));writer.writeheader();writer.writerows(comparison)
    try:commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    except (subprocess.SubprocessError,OSError):commit=None
    result={'status':'PASS','kind':'RTL simulation; not board measurements','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'base_commit':commit,'baseline_reader_sha256':BASELINE_SHA,'protocol_only':args.protocol_only,
        'measurement':'elapsed_cycles from task acceptance to completion; complete 65536-byte memory image per job',
        'memory_model':'single-beat byte reads, fixed AR/AW/W acceptance and fixed per-transaction read/write delay; no DDR/PCIe',
        'target_clock_period_ns':profile['clock_period_ns'],'profile':profile,'variants':variants,'comparison':comparison}
    result_file.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('PERFORMANCE_BENCHMARK_PASS comparisons='+str(len(comparison)),flush=True)

if __name__=='__main__':
    try:main()
    except Exception as error:
        print('PERFORMANCE_BENCHMARK_FAILED:',error,file=sys.stderr);sys.exit(1)
