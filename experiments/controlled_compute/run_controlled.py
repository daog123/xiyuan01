"""Controlled 64-product-channel experiments; byte/element supply budgets explicit."""
from pathlib import Path
import argparse,csv,hashlib,json,os,re,shutil,subprocess,sys
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[1]
sys.path.insert(0,str(ROOT/'scripts'));import project
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
OUT=ROOT/'build/controlled_compute';SOURCE=ROOT/'build/upstream_compute/sources'
RUNNER_BYTES=Path(__file__).read_bytes()
PREPARE_BYTES=(HERE/'prepare_controlled.py').read_bytes()
def save(work,data):(work/'result.json').write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
def csv_read(path):return [{k:int(v) for k,v in r.items()} for r in csv.DictReader(path.open(encoding='utf-8-sig'))]
def inputs(files):
 snapshots=OUT/'source_snapshots';snapshots.mkdir(exist_ok=True)
 digest=hashlib.sha256(RUNNER_BYTES).hexdigest();snapshot=snapshots/('runner_'+digest+'.py')
 if not snapshot.exists():snapshot.write_bytes(RUNNER_BYTES)
 prep_digest=hashlib.sha256(PREPARE_BYTES).hexdigest();prep_snapshot=snapshots/('prepare_'+prep_digest+'.py')
 if not prep_snapshot.exists():prep_snapshot.write_bytes(PREPARE_BYTES)
 return project.identity(files+[snapshot,prep_snapshot])
def verify_sources(name):
 manifest=json.loads((ROOT/'experiments/compute_upstream/sources.json').read_text())[name]
 for f in manifest['files']:assert hashlib.sha256((SOURCE/name/f['local']).read_bytes()).hexdigest()==f['sha256'],f
 return manifest
def run_open():
 spec=verify_sources('openTPU');work=OUT/'open64';work.mkdir(exist_ok=True)
 base=SOURCE/'openTPU';compatible=work/'mxu_xsim.sv';text=(base/'rtl/mxu/otpu_mxu.sv').read_text()
 text=text.replace('  localparam int BW = $clog2(LANES);','  wire mx_go;\n  localparam int CW = MCOLS<=1?1:$clog2(MCOLS);\n  localparam int BW = $clog2(LANES);',1).replace('wire mx_go     = mx_q && !mx_done;','assign mx_go     = mx_q && !mx_done;',1)
 text=text.replace('[MW-2:0]','[CW-1:0]').replace("(MW-1)'(j)","CW'(j)");compatible.write_text(text)
 (work/'common_vectors.txt').write_bytes((OUT/'common_vectors.txt').read_bytes())
 sources=[base/p for p in ['rtl/top/otpu_pkg.sv','rtl/vpu/otpu_fp.sv','rtl/vpu/otpu_fpipe.sv','rtl/tech/generic/otpu_tech_dsp.sv','rtl/tech/generic/otpu_tech_ram.sv']]+[compatible,HERE/'tb_opentpu_controlled.sv']
 result=dict(status='RUNNING',commit=spec['commit'],D=64,MCOLS=1,peak_product_channels=64,source_sha256=inputs(sources+[work/'common_vectors.txt']),
  supply='8 useful ingress bytes/clock, shared finite token bucket; actual weight/scale requests; INT8 ACT preload and native ACT scales charged before command',
  numerical='INT4 x INT8, general scale path, scale=1, unit fast path disabled; native scale granularity D64',
  compatibility='mx_go declaration moved; MCOLS1 column-index guard max(1,clog2(MCOLS)) in inactive ASCALE/RMAX selectors; arithmetic/control algorithms unchanged')
 save(work,result)
 try:
  project.run([TOOLS/'xvlog.bat','--sv',*sources],work,work/'compile.log');project.run([TOOLS/'xelab.bat','tb_opentpu_controlled','-s','open64','-timescale','1ns/1ps'],work,work/'elaborate.log')
  log=project.run([TOOLS/'xsim.bat','open64','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log');assert project.valid_log(log,'OPENTPU_CORE_PASS')
  rows=csv_read(work/'opentpu_results.csv');assert len(rows)==8;result.update(status='PASS',results=rows);print('CONTROLLED_OPEN_PASS cases=8',flush=True)
 except Exception as e:result.update(status='FAIL',error=str(e));raise
 finally:save(work,result)
def run_own():
 cases=json.loads((OUT/'cases.json').read_text());base=json.loads((ROOT/'build/w4a8_systolic_vectors/group32.json').read_text())['cases'];tokens=[len(base+cases)]
 for cid,c in enumerate(base+cases):
  tokens +=[cid,c['m'],c['n'],c['k'],c['groups']]+[v for row in c['a'] for v in row]+c['packed']+[v for row in c['sx'] for v in row]+[v for row in c['sw'] for v in row]+c['output']+[v for row in c['psum'] for g in row for v in g]
 for name,baseline,packed,broadcast in [('own_before',True,0,0),('own_after',False,0,0),('own_broadcast',False,0,1),('own_packed',False,1,1)]:
  work=OUT/name;work.mkdir(exist_ok=True);(work/'vectors.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
  wave=ROOT/('build/round2_baseline/rtl/w4a8_wave.sv' if baseline else 'rtl/w4a8_wave.sv');tb=ROOT/('build/round2_baseline/tb/tb_w4a8_wave.sv' if baseline else 'tb/tb_w4a8_wave.sv')
  wrapper=work/'wrapper.sv';params='.ROWS(8),.COLS(8),.COMPACT_SLOTS(1),.MODES(1),.MAX_DATA(262144)'
  if not baseline:params+=f',.TILE_K(32),.EFFECTIVE_DRAIN(1),.GEMV_FOLD(1),.COPY_LANES(8),.POST_LANES(2),.PACKED_MAC({packed}),.BROADCAST_MAC({broadcast})'
  wrapper.write_text('module own_controlled;tb_w4a8_wave #('+params+') test();endmodule\n')
  sources=[ROOT/'rtl'/(p+'.sv') for p in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack']]+[wave,ROOT/'tb/w4a8_reuse_memory.sv',tb,wrapper]
  result=dict(status='RUNNING',source_sha256=inputs(sources+[work/'vectors.txt']),peak_product_channels=64,supply='8 bus bytes/clock shared by W/A/scales; measured from empty native caches')
  save(work,result)
  try:
   project.run([TOOLS/'xvlog.bat','--sv',*sources],work,work/'compile.log');project.run([TOOLS/'xelab.bat','own_controlled','-s','ownsim','-timescale','1ns/1ps'],work,work/'elaborate.log')
   log=project.run([TOOLS/'xsim.bat','ownsim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log');assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS')
   rows=[r for r in csv_read(work/'results.csv') if r['case_id']>=15];assert len(rows)==8
   result.update(status='PASS',results=rows);print(name,'PASS',flush=True)
  except Exception as e:result.update(status='FAIL',error=str(e));raise
  finally:save(work,result)
def run_llama():
 spec=verify_sources('llama-fpga');work=OUT/'llama64';work.mkdir(exist_ok=True)
 source=OUT/'llama_core64.v';tb=HERE/'tb_llama_controlled.sv';ip=SOURCE/'llama-fpga/ip';tcl=work/'prepare.tcl'
 tcl.write_text(f'''create_project -force llama64 llama64 -part xcvu9p-flga2104-2L-e
set_property target_language Verilog [current_project]
set_property target_simulator XSim [current_project]
import_ip -files [glob {{{ip.as_posix()}/*/*.xci}}]
upgrade_ip [get_ips]
generate_target simulation [get_ips]
add_files {{{source.as_posix()}}}
add_files -fileset sim_1 {{{tb.as_posix()}}}
set_property top tb_llama_controlled_bytes [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -scripts_only -simset sim_1 -mode behavioral
exit
''')
 files=[source,tb,tcl,OUT/'common_vectors_half.txt']+list(ip.rglob('*.xci'))
 result=dict(status='RUNNING',commit=spec['commit'],peak_product_channels=64,source_sha256=inputs(files),
  adaptation='two original 32-lane banks; original 32-slot ACT RAM and metadata retained (K<=2048); two unused FP32 reduction inputs exact zero; arithmetic/IP configs unchanged',
  numerical='native FP16 operands after weight dequantization, FP32 accumulation; sequential GEMV rows, fixed postscale=1',profiles={})
 save(work,result)
 try:
  project.run([TOOLS/'vivado.bat','-mode','batch','-source',tcl.as_posix()],work,work/'prepare.log')
  sim=work/'llama64/llama64.sim/sim_1/behav/xsim';os.environ['PATH']=str(TOOLS)+os.pathsep+os.environ['PATH']
  project.run([sim/'compile.bat'],sim,work/'compile.log')
  elaborate=(sim/'elaborate.bat').read_text()
  for profile in ['bytes','elements']:
   batch=sim/('elaborate_'+profile+'.bat');batch.write_text(elaborate.replace('tb_llama_controlled_bytes','tb_llama_controlled_'+profile))
   project.run([batch],sim,work/('elaborate_'+profile+'.log'))
   log=project.run([TOOLS/'xsim.bat','tb_llama_controlled_'+profile+'_behav','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],sim,work/(profile+'.log'))
   assert project.valid_log(log,'LLAMA_CORE_PASS')
   csvpath=work/('results_'+profile+'.csv');shutil.copy2(sim/'llama_results.csv',csvpath);rows=csv_read(csvpath);assert len(rows)==5
   result['profiles'][profile]=dict(status='PASS',results=rows,weight_interval=16 if profile=='bytes' else 4,activation_interval=16 if profile=='bytes' else 8)
   save(work,result);print('CONTROLLED_LLAMA_PASS',profile,'cases=5',flush=True)
  result['status']='PASS'
 except Exception as e:result.update(status='FAIL',error=str(e));raise
 finally:save(work,result)
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--engine',choices=['all','prepare','own','open','llama'],default='all');a=p.parse_args()
 if a.engine in ['all','prepare']:
  subprocess.run([sys.executable,HERE/'prepare_controlled.py'],check=True)
 if a.engine in ['all','own']:run_own()
 if a.engine in ['all','open']:run_open()
 if a.engine in ['all','llama']:run_llama()
if __name__=='__main__':main()
