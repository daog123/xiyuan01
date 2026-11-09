"""Stage-isolated current-source compute experiment and parameter sweep."""
from pathlib import Path
import argparse,csv,hashlib,json,os,re,sys
ROOT=Path('E:/speed-up');sys.path.insert(0,str(ROOT/'scripts'));import project
def main():
 p=argparse.ArgumentParser();p.add_argument('--names',nargs='*');args=p.parse_args()
 out=ROOT/'build/round2_compute';out.mkdir(exist_ok=True)
 source_names=['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']
 base=json.loads((ROOT/'build/w4a8_systolic_vectors/group32.json').read_text())['cases']
 common=json.loads((ROOT/'build/compute_experiments/common_cases.json').read_text())
 cases=base+common;tokens=[len(cases)]
 for cid,c in enumerate(cases):
  tokens += [cid,c['m'],c['n'],c['k'],c['groups']]+[v for row in c['a'] for v in row]+c['packed']
  tokens += [v for row in c['sx'] for v in row]+[v for row in c['sw'] for v in row]+c['output']+[v for row in c['psum'] for group in row for v in group]
 vector='\n'.join(map(str,tokens))+'\n'
 configs=[('drain8',8,8,1,0,1,1,0,0,1),('post8',8,8,1,0,8,2,0,0,1),
  ('fold8',8,8,1,1,8,2,0,0,1),('tile16',8,16,1,1,8,2,0,0,1),
  ('tile32',8,32,1,1,8,2,0,0,3),('broadcast8',8,32,1,1,8,2,1,0,1),
  ('packed8',8,32,1,1,8,2,1,1,3),('default4',4,32,1,1,4,2,0,0,3)]
 tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
 for name,size,tile,drain,fold,copy,post,broadcast,packed,modes in configs:
  if args.names and name not in args.names:continue
  work=out/name;work.mkdir(exist_ok=True);(work/'result.json').write_text('{"status":"RUNNING"}')
  (work/'vectors.txt').write_text(vector,encoding='ascii')
  wrapper=work/'wrapper.sv';wrapper.write_text(f'module tb_round2;tb_w4a8_wave #(.ROWS({size}),.COLS({size}),.TILE_K({tile}),.COMPACT_SLOTS(1),.MODES({modes}),.MAX_DATA(262144),.EFFECTIVE_DRAIN({drain}),.GEMV_FOLD({fold}),.COPY_LANES({copy}),.POST_LANES({post}),.BROADCAST_MAC({broadcast}),.PACKED_MAC({packed})) test();endmodule\n',encoding='ascii')
  sources=[ROOT/'rtl'/(n+'.sv') for n in source_names]+[ROOT/'tb/w4a8_reuse_memory.sv',ROOT/'tb/tb_w4a8_wave.sv',wrapper]
  hashes=project.identity(sources+[Path(__file__).resolve(),work/'vectors.txt']) if Path(__file__).is_relative_to(ROOT) else project.identity(sources+[work/'vectors.txt'])
  try:
   project.run([tools/'xvlog.bat','--sv',*sources],work,work/'compile.log')
   project.run([tools/'xelab.bat','tb_round2','-s','r2sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
   log=project.run([tools/'xsim.bat','r2sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log')
   assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS'),work
   rows=[{k:int(v) for k,v in row.items()} for row in csv.DictReader((work/'results.csv').open())]
   result=dict(status='PASS',name=name,config=dict(rows=size,cols=size,tile_k=tile,effective_drain=drain,gemv_fold=fold,copy_lanes=copy,post_lanes=post,broadcast=broadcast,packed=packed),
    marker=re.search(r'W4A8_WAVE_TESTS_PASS [^\r\n]+',log)[0],results=rows,source_sha256=hashes)
   (work/'result.json').write_text(json.dumps(result,indent=2)+'\n')
   print(name,result['marker'],flush=True)
   for r in rows:
    if r['case_id'] in [17,23]:print(name,r['M'],r['N'],r['K'],r['total_cycles'],r['valid_macs']/r['total_cycles'],flush=True)
  except Exception as e:(work/'result.json').write_text(json.dumps(dict(status='FAIL',error=str(e))));raise
if __name__=='__main__':main()
