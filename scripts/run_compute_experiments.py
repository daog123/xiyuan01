"""Controlled dense/compact-slot experiments on the real W4A8 core."""
import argparse,csv,hashlib,json,os,random,sys
from pathlib import Path
import project

ROOT=project.ROOT
sys.path.insert(0,str(ROOT/'model'))
from w4a8_reference import reference

def generate(out):
    base=json.loads((ROOT/'build/w4a8_systolic_vectors/group32.json').read_text(encoding='utf-8'))['cases']
    assert len(base)==15
    cases=list(base)
    for m in [1,4,8]:
        for k in [128,512,4096]:
            n=64;ng=(k+31)//32;rng=random.Random(1025000+m*10000+k)
            a=[[rng.choice([-1,0,1]) for _ in range(k)] for _ in range(m)]
            w=[[rng.choice([-1,0,1]) for _ in range(n)] for _ in range(k)]
            sx=[[4096]*ng for _ in range(m)];sw=[[4096]*n for _ in range(ng)]
            y,psum,_=reference(a,w,sx,sw,32)
            assert max(map(abs,y))<2147483647,'common benchmark must not saturate'
            packed=[(w[q][c]&15)|((w[q+1][c]&15)<<4) for c in range(n) for q in range(0,k,2)]
            cases.append(dict(name=f'common_m{m}_n{n}_k{k}',m=m,n=n,k=k,groups=ng,a=a,packed=packed,sx=sx,sw=sw,output=y,psum=psum,
                              common_math=True,weights=w))
    tokens=[len(cases)]
    for cid,c in enumerate(cases):
        tokens += [cid,c['m'],c['n'],c['k'],c['groups']]
        tokens += [x for row in c['a'] for x in row]+c['packed']
        tokens += [x for row in c['sx'] for x in row]+[x for row in c['sw'] for x in row]
        tokens += c['output']+[x for row in c['psum'] for group in row for x in group]
    (out/'vectors.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
    (out/'common_cases.json').write_text(json.dumps(cases[15:])+'\n',encoding='utf-8')
    return cases

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--vivado-bin',type=Path,default=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin')))
    p.add_argument('--implement',action='store_true')
    args=p.parse_args();out=ROOT/'build/compute_experiments';out.mkdir(parents=True,exist_ok=True)
    (out/'result.json').write_text('{"status":"RUNNING"}\n',encoding='utf-8')
    cases=generate(out)
    sources=[ROOT/'rtl'/(name+'.sv') for name in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']]
    sources += [ROOT/'tb/w4a8_reuse_memory.sv',ROOT/'tb/tb_w4a8_wave.sv']
    wrappers=out/'wrappers.sv';configs=[];text=''
    for size in [4,8]:
        for compact in [0,1]:
            name=f'core_{size}x{size}_compact{compact}';configs.append((name,size,compact))
            text+=f'module {name};tb_w4a8_wave #(.ROWS({size}),.COLS({size}),.COMPACT_SLOTS({compact}),.MAX_DATA(262144)) test();endmodule\n'
    wrappers.write_text(text,encoding='ascii')
    hashes=project.identity(sources+[Path(__file__),ROOT/'model/w4a8_reference.py',out/'vectors.txt',wrappers])
    project.run([args.vivado_bin/'xvlog.bat','--sv',*sources,wrappers],out,out/'compile.log')
    records=[]
    for name,size,compact in configs:
        work=out/name;work.mkdir(exist_ok=True)
        (work/'inputs.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
        project.run([args.vivado_bin/'xelab.bat',name,'-s',name+'_sim','-timescale','1ns/1ps'],out,work/'elaborate.log')
        log=project.run([args.vivado_bin/'xsim.bat',name+'_sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],out,work/'run.log')
        assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS'),name
        import re
        marker=re.search(r'W4A8_WAVE_TESTS_PASS [^\r\n]+',log)[0]
        (work/'results.csv').write_bytes((out/'results.csv').read_bytes())
        values=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((work/'results.csv').open(encoding='utf-8-sig'))]
        assert len([r for r in values if r['case_id']>=15])==9
        records.append(dict(name=name,rows=size,cols=size,compact_slots=compact,result=marker,cycles=values,source_sha256=hashes))
        print(name,marker,flush=True)
    comparison=[]
    for size in [4,8]:
        old=next(r for r in records if r['rows']==size and r['compact_slots']==0)
        new=next(r for r in records if r['rows']==size and r['compact_slots']==1)
        for a,b in zip(old['cycles'],new['cycles']):
            assert (a['case_id'],a['mode'],a['recovery'])==(b['case_id'],b['mode'],b['recovery'])
            for field in ['valid_macs','weight_bytes','activation_bytes','scale_bytes','compute_cycles','input_beats','padding_bytes']:
                assert a[field]==b[field],(field,a,b)
            if a['recovery']:continue
            item={k:a[k] for k in ['case_id','mode','M','N','K','valid_macs']}
            item.update(rows=size,cols=size,baseline_cycles=a['total_cycles'],optimized_cycles=b['total_cycles'],
                        speedup=a['total_cycles']/b['total_cycles'],cycle_reduction_percent=100*(1-b['total_cycles']/a['total_cycles']),
                        baseline_post_issues=a['post_issue_cycles'],optimized_post_issues=b['post_issue_cycles'],
                        optimized_mac_per_clock=b['valid_macs']/b['total_cycles'],
                        optimized_array_mac_per_advance=b['valid_macs']/b['array_cycles'],
                        optimized_array_utilization_percent=100*b['valid_macs']/(size*size*b['array_cycles']),
                        optimized_core_utilization_percent=100*b['valid_macs']/(size*size*b['total_cycles']),
                        optimized_gmac_s_at_100mhz=.1*b['valid_macs']/b['total_cycles'],
                        optimized_array_cycles=b['array_cycles'],optimized_wait_cycles=b['input_wait_cycles'])
            comparison.append(item)
    with (out/'comparison.csv').open('w',encoding='utf-8-sig',newline='') as f:
        writer=csv.DictWriter(f,fieldnames=list(comparison[0]));writer.writeheader();writer.writerows(comparison)
    implementations=[]
    if args.implement:
        for name,size,compact in configs:
            work=out/name/'implementation';work.mkdir(exist_ok=True)
            log=project.run([args.vivado_bin/'vivado.bat','-mode','batch','-source',(ROOT/'scripts/implement_compute.tcl').as_posix(),
                             '-tclargs',size,compact],work,work/'console.log')
            assert 'COMPUTE_IMPLEMENTATION_PASS' in log,name
            timing=(work/'timing_values.txt').read_text(encoding='ascii')
            match=re.search(r'WNS=([\d.-]+) WHS=([\d.-]+)',timing);assert match
            assert min(float(match[1]),float(match[2]))>=0
            util=(work/'utilization.rpt').read_text(encoding='utf-8',errors='replace')
            resources={label:float(re.search(r'^\|\s*'+re.escape(label)+r'\*?\s*\|\s*([\d.]+)',util,re.M)[1]) for label in ['CLB LUTs','CLB Registers','DSPs','Block RAM Tile']}
            route=(work/'route_status.rpt').read_text(encoding='utf-8',errors='replace')
            count={key:int(re.search('# of '+label+r'\.+\s*:\s*(\d+)',route)[1]) for key,label in [('routable','routable nets'),('fully_routed','fully routed nets'),('errors','nets with routing errors')]}
            assert count['errors']==0 and count['routable']==count['fully_routed']
            implementations.append(dict(name=name,WNS_ns=float(match[1]),WHS_ns=float(match[2]),resources=resources,route=count,
                                        source_sha256=project.identity(sources[:7]+[ROOT/'scripts/implement_compute.tcl'])))
            print(name,'OOC_PASS',timing.strip(),resources,flush=True)
    result=dict(status='PASS',scope='isolated W4A8 core; dense vs compact; no DDR/PCIe; same arithmetic and bytes',
                simulations=records,comparison=comparison,implementations=implementations,common_case_count=9,
                common_math='seeded signed {-1,0,1} activations and weights, all group scales 1; same mathematical tensors for upstream tests',
                target_clock_period_ns=10)
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('COMPUTE_EXPERIMENTS_PASS comparisons='+str(len(comparison)),flush=True)

if __name__=='__main__':
    try:main()
    except Exception as e:print('COMPUTE_EXPERIMENTS_FAILED:',e,file=sys.stderr);sys.exit(1)
