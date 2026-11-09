"""Paired ABI v5 LINEAR/FFN: frozen round4 MAC mapping vs adaptive M/K mapping."""
from pathlib import Path
import csv,hashlib,json,os,re,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
OUT=ROOT/'build/round5_performance';OUT.mkdir(parents=True,exist_ok=True)
result=dict(status='RUNNING',kind='RTL simulation, memory-backed operator latency; no DDR/PCIe or model throughput',variants=[],comparison=[])
def save():(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
def main():
 assert hashlib.sha256((ROOT/'tb/baselines/w4a8_wave_round4.sv').read_bytes()).hexdigest()=='aee2b0bfc901f31974f083c7fe1e40e4e1c5f62c9416002e7be5b32ff3823ec1'
 save();project.run([sys.executable,ROOT/'model/system_vectors.py','--out',OUT/'vectors'],ROOT,OUT/'reference.log')
 src=[ROOT/'rtl'/(n+'.sv') for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]
 bench=[ROOT/'tb/llm_test_shells.sv',ROOT/'tb/system_axi_memory.sv',ROOT/'tb/tb_accelerator.sv']
 all_rows=[]
 for variant in ['before','after']:
  work=OUT/variant;work.mkdir(exist_ok=True)
  for f in (OUT/'vectors').glob('*'):(work/f.name).write_bytes(f.read_bytes())
  selected=[]
  for p in src:
   old=ROOT/'tb/baselines/w4a8_wave_round4.sv'
   selected.append(old if variant=='before' and p.stem=='w4a8_wave' else p)
  inputs=project.identity(selected+bench+[Path(__file__),project.PROFILE]+list((ROOT/'model').rglob('*.py')))
  project.run([TOOLS/'xvlog.bat','--sv',*selected,*bench],work,work/'compile.log')
  rec=dict(name=variant,source_sha256=inputs,simulations=[])
  for top in ['tb_perf_r0','tb_perf_r8','tb_perf_r24','tb_perf_g12']:
   project.run([TOOLS/'xelab.bat',top,'-s',top,'-timescale','1ns/1ps'],work,work/(top+'.elaborate.log'))
   log=project.run([TOOLS/'xsim.bat',top,'-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/(top+'.run.log'))
   assert project.valid_log(log,'PERFORMANCE_TESTS_PASS'),top
   rec['simulations'].append(dict(top=top,result=next(x for x in log.splitlines() if x.startswith('PERFORMANCE_TESTS_PASS'))))
   rows=[dict(re.findall(r'(\w+)=(-?\d+)',s)) for s in re.findall(r'PERF_RECORD ([^\r\n]+)',log)]
   assert len(rows)==6
   all_rows +=[dict(variant=variant,top=top,**{k:int(v) for k,v in row.items()}) for row in rows]
   print(variant,top,'PASS jobs=6',flush=True)
  result['variants'].append(rec);save()
 shapes=json.loads((OUT/'vectors/manifest.json').read_text())
 for old in [x for x in all_rows if x['variant']=='before']:
  new=next(x for x in all_rows if x['variant']=='after' and (x['top'],x['opcode'],x['case'])==(old['top'],old['opcode'],old['case']))
  for key in ['read_payload','writes','acks','bytes','group','read_delay','write_delay']:assert new[key]==old[key],key
  assert new['reads']<=old['reads']  and new['acks']==new['writes']
  shape=next(s for s in shapes if (s['group'],s['case'])==(new['group'],new['case']))
  m,k,h,n=(shape[s] for s in ['m','k','h','n'])
  assert new['cycles']<=old['cycles'] and new['reads']==old['reads']
  macs=m*k*h if new['opcode']==0 else 2*m*k*h+m*h*n
  row=dict(top=new['top'],operator='LINEAR' if new['opcode']==0 else 'FFN',case=new['case'],group=new['group'],M=m,K=k,H=h,N=h if new['opcode']==0 else n,
   read_delay=new['read_delay'],old_cycles=old['cycles'],new_cycles=new['cycles'],speedup=old['cycles']/new['cycles'],
   old_read_transactions=old['reads'],new_read_transactions=new['reads'],read_payload_bytes=new['read_payload'],writes=new['writes'],acks=new['acks'],
   useful_matrix_MACs=macs,old_effective_MAC_per_clock=macs/old['cycles'],new_effective_MAC_per_clock=macs/new['cycles'],memory_bytes_compared=new['bytes'])
  result['comparison'].append(row)
 assert len(result['comparison'])==24
 with (OUT/'comparison.csv').open('w',encoding='utf-8-sig',newline='')as f:
  writer=csv.DictWriter(f,fieldnames=list(result['comparison'][0]));writer.writeheader();writer.writerows(result['comparison'])
 result['status']='PASS';save();print('ROUND5_SYSTEM_PERFORMANCE_PASS pairs=24 full_image_jobs=48',flush=True)
if __name__=='__main__':main()
