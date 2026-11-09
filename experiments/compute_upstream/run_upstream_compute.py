"""Reproduce pinned upstream numerical compute microbenchmarks with real RTL."""
import argparse,csv,hashlib,json,os,re,shutil,struct,subprocess,sys,urllib.request
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1] # experiments/compute_upstream/run_upstream_compute.py

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def blob(data):return hashlib.sha1(f'blob {len(data)}\0'.encode()+data).hexdigest()
def run(args,cwd,log,env=None):
    with log.open('w',encoding='utf-8') as f:
        result=subprocess.run(list(map(str,args)),cwd=cwd,stdout=f,stderr=subprocess.STDOUT,env=env)
    text=log.read_text(encoding='utf-8',errors='replace')
    if result.returncode or re.search(r'Fatal:|^ERROR:',text,re.M):
        raise RuntimeError(f'{log}: exit={result.returncode}\n{text[-2500:]}')
    return text

def stage(spec,out,cache):
    out.mkdir(parents=True,exist_ok=True);files=[]
    for entry in spec['files']:
        p=out/entry['local'];p.parent.mkdir(parents=True,exist_ok=True)
        source=cache/spec['name']/entry['local'] if cache else None
        if source and source.is_file() and not p.exists():shutil.copy2(source,p)
        if not p.exists():
            url=f"https://raw.githubusercontent.com/{spec['repository']}/{spec['commit']}/{entry['remote']}"
            request=urllib.request.Request(url,headers={'User-Agent':'compute-microbenchmark'})
            with urllib.request.urlopen(request,timeout=120) as response:data=response.read()
            if blob(data)!=entry['git_blob'] or hashlib.sha256(data).hexdigest()!=entry['sha256']:
                raise ValueError('download identity mismatch: '+entry['remote'])
            p.write_bytes(data)
        if sha(p)!=entry['sha256'] or blob(p.read_bytes())!=entry['git_blob']:
            raise ValueError('cached source identity mismatch: '+str(p))
        files.append(p)
    return files

def vectors(cases,path,half=False):
    tokens=[len(cases)]
    for index,c in enumerate(cases):
        tokens += [15+index,c['m'],c['n'],c['k']]+[v for row in c['a'] for v in row]
        tokens += [c['weights'][q][col] for col in range(c['n']) for q in range(c['k'])]
        # Independent integer dot-product oracle. Do not call upstream arithmetic.
        expected=[sum(c['a'][row][q]*c['weights'][q][col] for q in range(c['k']))
                  for row in range(c['m']) for col in range(c['n'])]
        assert [x*65536 for x in expected]==c['output']
        fmt=('<H','<e') if half else ('<I','<f')
        tokens += [struct.unpack(fmt[0],struct.pack(fmt[1],x))[0] for x in expected]
    path.write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')

def extract(full,out):
    text=full.read_text(encoding='utf-8')
    modules={m[1]:m[0] for m in re.finditer(r'^module\s+(\w+)\b.*?^endmodule[^\r\n]*',text,re.M|re.S)}
    selected=set()
    def visit(name):
        if name in selected:return
        selected.add(name)
        for candidate in modules:
            if candidate!=name and re.search(r'\b'+re.escape(candidate)+r'\s+(?:#\s*\(.*?\)\s*)?\w+\s*\(',modules[name],re.S):visit(candidate)
    visit('MulAddSGNew')
    assert len(selected)==10,selected
    out.write_text('\n\n'.join(modules[name] for name in sorted(selected))+'\n',encoding='utf-8')
    return sorted(selected)

def opentpu(spec,source,work,cases,args):
    work.mkdir(parents=True,exist_ok=True)
    original=source/'rtl/mxu/otpu_mxu.sv';text=original.read_text(encoding='utf-8')
    assert text.count('wire mx_go     = mx_q && !mx_done;')==1
    text=text.replace('  localparam int BW = $clog2(LANES);','  wire mx_go; // XSim declaration-order compatibility only\n  localparam int BW = $clog2(LANES);',1)
    text=text.replace('wire mx_go     = mx_q && !mx_done;','assign mx_go     = mx_q && !mx_done;',1)
    compatible=work/'otpu_mxu_xsim.sv';compatible.write_text(text,encoding='utf-8')
    sources=[source/x for x in ['rtl/top/otpu_pkg.sv','rtl/vpu/otpu_fp.sv','rtl/vpu/otpu_fpipe.sv',
        'rtl/tech/generic/otpu_tech_dsp.sv','rtl/tech/generic/otpu_tech_ram.sv']]+[compatible,HERE/'tb_opentpu_core.sv']
    vectors(cases,work/'common_vectors.txt')
    inputs={str(p):sha(p) for p in sources+[work/'common_vectors.txt',HERE/'run_upstream_compute.py',HERE/'sources.json']}
    result={'status':'PREPARED','commit':spec['commit'],'source_sha256':inputs,'IMPL':args.impl,
        'compatibility_change':'mx_go net declaration moved before first use; continuous driver unchanged',
        'boundary':'native MXU, preloaded ACT, one-cycle weight/scale responses, TMEM always granted; no host/DDR',
        'technology':'upstream generic cycle models; no physical resource/frequency measurement'}
    try:
        if args.prepare_only:return result
        result['status']='RUNNING';save(work,result)
        run([args.vivado_bin/'xvlog.bat','--sv',*sources],work,work/'compile.log')
        top='tb_opentpu_core' if args.impl==2 else 'tb_opentpu_tree'
        run([args.vivado_bin/'xelab.bat',top,'-s','opentpu_sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
        script=work/'run.tcl';script.write_text('run 20 ms\nquit\n',encoding='ascii')
        text=run([args.vivado_bin/'xsim.bat','opentpu_sim','-tclbatch',script.as_posix()],work,work/'run.log')
        assert 'OPENTPU_CORE_PASS' in text
        rows=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((work/'opentpu_results.csv').open())]
        assert len(rows)==27
        result.update(status='PASS',results=rows,D=128,MCOLS=4,ACT_ROWS=8,FIFO_DEPTH=64)
    except Exception as error:result.update(status='FAIL',error=str(error));raise
    finally:save(work,result)
    return result

def llama(spec,source,work,cases,args):
    work.mkdir(parents=True,exist_ok=True)
    extracted=work/'MulAddSGNew_extracted.v';modules=extract(source/'DataPath_xN.v',extracted)
    v=work/'common_vectors_half.txt';vectors(cases,v,True)
    tb=work/'tb_llama_core.sv';tb.write_text((HERE/'tb_llama_core.sv').read_text().replace('"common_vectors_half.txt"','"'+v.as_posix()+'"'),encoding='utf-8')
    tcl=work/'prepare.tcl'
    # Generate batch scripts without starting the GUI simulation kernel.
    tcl.write_text(f'''create_project -force llama_core llama_core -part xcvu9p-flga2104-2L-e
set_property target_language Verilog [current_project]
set_property target_simulator XSim [current_project]
import_ip -files [glob {{{source.as_posix()}/ip/*/*.xci}}]
upgrade_ip [get_ips]
generate_target simulation [get_ips]
report_ip_status -file ip_status.rpt
add_files {{{extracted.as_posix()}}}
add_files -fileset sim_1 {{{tb.as_posix()}}}
set_property top tb_llama_core [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -scripts_only -simset sim_1 -mode behavioral
exit
''',encoding='utf-8')
    files=[extracted,tb,v,tcl,HERE/'run_upstream_compute.py',HERE/'sources.json']+list((source/'ip').rglob('*.xci'))
    result={'status':'PREPARED','commit':spec['commit'],'source_sha256':{str(p):sha(p) for p in files},'modules':modules,
        'boundary':'128-lane native MulAddSGNew after dequantization; FP16 inputs, FP32 reduction/accumulation, postscale=1; M sequential GEMV commands; no host/DDR',
        'vendor_models':'original XCI configs upgraded in a private copy by Vivado; actual floating-point IP simulation models'}
    try:
        if args.prepare_only:return result
        result['status']='RUNNING';save(work,result)
        run([args.vivado_bin/'vivado.bat','-mode','batch','-source',tcl.as_posix()],work,work/'prepare.log')
        sim=work/'llama_core/llama_core.sim/sim_1/behav/xsim'
        env=os.environ.copy();env['PATH']=str(args.vivado_bin)+os.pathsep+env['PATH']
        run([sim/'compile.bat'],sim,work/'compile_batch.log',env)
        run([sim/'elaborate.bat'],sim,work/'elaborate_batch.log',env)
        script=work/'headless.tcl';script.write_text('run 1 ms\nquit\n',encoding='ascii')
        text=run([args.vivado_bin/'xsim.bat','tb_llama_core_behav','-tclbatch',script.as_posix()],sim,work/'headless.log',env)
        assert 'LLAMA_CORE_PASS' in text
        rows=[{k:int(v) for k,v in r.items()} for r in csv.DictReader((sim/'llama_results.csv').open())]
        assert len(rows)==9
        result.update(status='PASS',results=rows,lanes=128)
    except Exception as error:result.update(status='FAIL',error=str(error));raise
    finally:save(work,result)
    return result

def save(work,result):(work/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--engine',choices=['all','openTPU','llama-fpga'],default='all')
    p.add_argument('--impl',type=int,choices=[0,2],default=2)
    p.add_argument('--work-dir',type=Path,default=ROOT/'build/upstream_compute')
    p.add_argument('--source-cache',type=Path,help='Optional verified offline sources, organized by engine name')
    p.add_argument('--cases',type=Path,default=ROOT/'build/compute_experiments/common_cases.json')
    p.add_argument('--vivado-bin',type=Path,default=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin')))
    p.add_argument('--prepare-only',action='store_true',help='Validate sources and generate all inputs without running the simulator')
    args=p.parse_args();args.work_dir=args.work_dir.resolve()
    cases=json.loads(args.cases.read_text());assert len(cases)==9
    manifest=json.loads((HERE/'sources.json').read_text())
    for name in (['openTPU','llama-fpga'] if args.engine=='all' else [args.engine]):
        spec=manifest[name];source=args.work_dir/'sources'/name;stage(spec,source,args.source_cache)
        work=args.work_dir/(f'opentpu_impl{args.impl}' if name=='openTPU' else 'llama_core')
        result=(opentpu if name=='openTPU' else llama)(spec,source,work,cases,args)
        print(name,result['status'],flush=True)

if __name__=='__main__':main()
