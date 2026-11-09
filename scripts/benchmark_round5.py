"""Paired frozen-core and adaptive M/K mapping experiments, with full math oracle."""
from pathlib import Path
import argparse,csv,hashlib,json,os,random,re,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'model')]
import project
from w4a8_reference import make_case
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
OUT=ROOT/'build/round5_compute'
CONFIGS={
 'before8':(8,8,32,32,0,0,0,1), 'after8':(8,8,32,32,1,0,0,1),
 'ablation8':(8,8,32,32,0,0,0,1),
 'before4':(4,4,32,32,0,0,0,1), 'after4':(4,4,32,32,1,0,0,1),
 'broadcast8':(8,8,32,32,1,1,0,1), 'packed8':(8,8,32,32,1,1,1,1),
 'seam8':(8,8,8,32,1,0,0,1), 'single8':(8,8,32,32,1,0,0,0),
 'group12':(4,4,4,12,1,0,0,1), 'odd':(2,3,5,12,1,0,0,1),
 'scalar':(1,1,32,32,1,0,0,1)}

def case_data(group):
    cases=json.loads((ROOT/f'build/w4a8_systolic_vectors/group{group}.json').read_text())['cases']
    rng=random.Random(20261026+group)
    specs=[('m2_k1',2,17,1,'direct'),('m2_tail',2,17,65,'float'),
      ('m4_tail',4,9,67,'direct'),('m3',3,17,33,'float'),('m5',5,9,31,'direct'),
      ('m7',7,7,63,'float'),('m10',10,9,33,'direct'),('m12',12,17,65,'float'),
      ('m2_zero',2,3,13,'zero'),('m4_k3',4,1,3,'direct'),('m2_k7',2,7,7,'direct'),
      ('m4_k31',4,17,31,'float'),('m2_long',2,64,4096,'float'),('m4_long',4,64,4096,'float')]
    # Group12/odd/scalar regressions keep the boundary vectors but omit long runs.
    cases+= [make_case(rng,*s[:4],group,s[4]) for s in specs if group==32 or s[3]<4096]
    if group==32:cases+=json.loads((ROOT/'build/compute_experiments/common_cases.json').read_text())
    return cases

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--names',nargs='*');args=parser.parse_args()
    OUT.mkdir(parents=True,exist_ok=True)
    old=ROOT/'tb/baselines/w4a8_wave_round4.sv'
    assert hashlib.sha256(old.read_bytes()).hexdigest()=='aee2b0bfc901f31974f083c7fe1e40e4e1c5f62c9416002e7be5b32ff3823ec1'
    for name,(rows,cols,tile,group,multi,broadcast,packed,db) in CONFIGS.items():
        if args.names and name not in args.names:continue
        work=OUT/name;work.mkdir(exist_ok=True)
        result=dict(status='RUNNING',configuration=name);path=work/'result.json';path.write_text(json.dumps(result))
        cases=case_data(group)
        if name in ['seam8','single8','group12','odd','scalar']:
            cases=[c for c in cases if c['k']<=512]
        tokens=[len(cases)]
        for cid,c in enumerate(cases):
            tokens += [cid,c['m'],c['n'],c['k'],c['groups']]+[v for row in c['a'] for v in row]+c['packed']
            tokens += [v for row in c['sx'] for v in row]+[v for row in c['sw'] for v in row]+c['output']+[v for row in c['psum'] for g in row for v in g]
        (work/'vectors.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
        (work/'cases.json').write_text(json.dumps([dict(id=i,name=c['name'],M=c['m'],N=c['n'],K=c['k']) for i,c in enumerate(cases)],indent=2)+'\n')
        text=(ROOT/'tb/tb_w4a8_wave.sv').read_text().split('module tb_w4a8_wave_directed')[0]
        text=text.replace('((cid>=15)?1:MODES)', '((k>512)?1:MODES)')
        text=text.replace('if(MODES>1 && cid==10)', 'if(MODES>1 && (cid==10 || cid==12 || cid==16))')
        text=text.replace('#20000000;', '#100000000;')
        text=text.replace('for(md=0;md<', 'if($test$plusargs("corrupt_expected") && cid==0) golden[0]=golden[0]^1;\n            for(md=0;md<')
        text+='\nmodule round5_probe_watchdog;initial if($test$plusargs("timeout_probe")) begin #1000;$fatal(1,"ROUND5_FORCED_TIMEOUT");end endmodule\n'
        # Instantiate the bounded probe in the selected top, not as an extra root.
        text=text.replace('module tb_w4a8_wave;', 'module tb_w4a8_wave;\n    round5_probe_watchdog probe();')
        if name.startswith('before'):text=text.replace('.MULTIROW_FOLD(MULTIROW_FOLD),','')
        (work/'testbench.sv').write_text(text)
        wrapper=work/'wrapper.sv';wrapper.write_text(f'module tb_round5;tb_w4a8_wave #(.ROWS({rows}),.COLS({cols}),.TILE_K({tile}),.GROUP_SIZE({group}),.MODES(3),.MAX_DATA(262144),.COMPACT_SLOTS(1),.EFFECTIVE_DRAIN(1),.GEMV_FOLD(1),.MULTIROW_FOLD({multi}),.COPY_LANES({cols}),.POST_LANES({min(2,cols)}),.BROADCAST_MAC({broadcast}),.PACKED_MAC({packed}),.DOUBLE_BUFFER({db})) test();endmodule\n')
        sources=[ROOT/'rtl'/f'{n}.sv' for n in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack']]+[old if name.startswith('before') else ROOT/'rtl/w4a8_wave.sv',ROOT/'tb/w4a8_reuse_memory.sv',work/'testbench.sv',wrapper]
        identities=project.identity(sources+[ROOT/'tb/tb_w4a8_wave.sv',Path(__file__),ROOT/'model/w4a8_reference.py',Path(project.__file__),ROOT/'scripts/run_w4a8_memory_xsim.tcl',work/'vectors.txt',work/'cases.json'])
        result['source_sha256']=identities;path.write_text(json.dumps(result,indent=2))
        try:
            project.run([TOOLS/'xvlog.bat','--sv',*sources],work,work/'compile.log')
            project.run([TOOLS/'xelab.bat','tb_round5','-s','round5_sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
            command=[TOOLS/'xsim.bat','round5_sim','-tclbatch',(ROOT/'scripts/run_w4a8_memory_xsim.tcl').as_posix()]
            log=project.run(command,work,work/'run.log');assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS'),work
            data=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((work/'results.csv').open())]
            if name=='after8':
                positive=(work/'results.csv').read_bytes();probes=[]
                try:
                    for flag,expected in [('corrupt_expected','bit-exact Q16.16 output'),('timeout_probe','ROUND5_FORCED_TIMEOUT')]:
                        bad=project.run(command+['-testplusarg',flag],work,work/(flag+'.log'),allow_failure=True)
                        assert expected in bad and not project.valid_log(bad,'W4A8_WAVE_TESTS_PASS')
                        probes.append(dict(probe=flag,expected_failure=True))
                finally:(work/'results.csv').write_bytes(positive)
                result['negative_probes']=probes
            result.update(status='PASS',result=re.search(r'W4A8_WAVE_TESTS_PASS [^\r\n]+',log)[0],results=data)
            print(name,result['result'],flush=True)
        except Exception as exc:result.update(status='FAIL',error=str(exc));raise
        finally:path.write_text(json.dumps(result,indent=2)+'\n')
    comparisons=[]
    invariants=['weight_bytes','activation_bytes','scale_bytes','valid_macs','input_beats','padding_bytes','psum_groups','post_issue_cycles','post_retire_cycles']
    for size in [8,4]:
        files=[OUT/f'{phase}{size}/result.json' for phase in ['before','after']]
        if not all(p.exists() for p in files):continue
        before,after=[json.loads(p.read_text()) for p in files]
        assert before['status']==after['status']=='PASS'
        old_rows={tuple(r[k] for k in ['case_id','recovery','mode']):r for r in before['results'] if not r['recovery']}
        new_rows={tuple(r[k] for k in ['case_id','recovery','mode']):r for r in after['results'] if not r['recovery']}
        assert old_rows.keys()==new_rows.keys()
        for key,a in old_rows.items():
            b=new_rows[key]
            for field in invariants:assert a[field]==b[field],(size,key,field)
            if a['recovery'] or a['mode']:continue
            comparisons.append(dict(rows=size,M=a['M'],N=a['N'],K=a['K'],case_id=a['case_id'],old_cycles=a['total_cycles'],new_cycles=b['total_cycles'],speedup=a['total_cycles']/b['total_cycles'],old_MAC_per_clock=a['valid_macs']/a['total_cycles'],new_MAC_per_clock=b['valid_macs']/b['total_cycles'],old_array_cycles=a['array_cycles'],new_array_cycles=b['array_cycles'],input_beats=b['input_beats']))
    if comparisons:
        with (OUT/'comparison.csv').open('w',encoding='utf-8-sig',newline='') as f:
            w=csv.DictWriter(f,fieldnames=list(comparisons[0]));w.writeheader();w.writerows(comparisons)
        for r in comparisons:
            if r['K']==4096:print('PAIR',r,flush=True)
    print('ROUND5_REQUESTED_CONFIGURATIONS_PASS',flush=True)

if __name__=='__main__':main()
