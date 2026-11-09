"""Bounded burst protocol and exact-byte storage regression, isolated evidence."""
from pathlib import Path
import json,os,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
out=ROOT/'build/round7_protocol';out.mkdir(parents=True,exist_ok=True)
result=dict(status='RUNNING',simulations=[])
def save():(out/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
save()
def align_activation_vectors(work):
 # Preserve the independent mathematical vectors; relocate only A and its
 # padding. Start 16 bytes before 4KiB so the exact-address oracle sees a split.
 for p in work.glob('g*_job*.txt'):
  tokens=list(map(int,p.read_text().split()));m,k=tokens[1],tokens[3]
  old_base,old_stride=tokens[6],tokens[11];base=4080;stride=(k+14)//8*8
  hp=p.with_suffix('.hex');image=bytearray(int(v,16) for v in hp.read_text().split())
  rows=[bytes(image[old_base+r*old_stride:old_base+r*old_stride+k]) for r in range(m)]
  for r in range(m):image[old_base+r*old_stride:old_base+r*old_stride+k]=b'\xcd'*k
  for r,row in enumerate(rows):image[base+r*stride:base+r*stride+k]=row
  tokens[6]=base;tokens[11]=stride;tokens[16]=(m-1)*stride+k
  p.write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
  hp.write_text(''.join(f'{b:02x}\n' for b in image),encoding='ascii')

# Additional finite images exercise >16-byte weight windows and sx group 128
# fallback. Only layout changes; the existing independent math oracle is used.
sys.path.insert(0,str(ROOT/'model'))
from w4a8_reference import make_case
import random
def extra_vectors(work,group):
 for job in range(2):
  m,n,k=(3,5,137+12*job) if group==128 else (2+job,5+2*job,1601+12*job)
  c=make_case(random.Random(7200+group+job),'cache',m,n,k,group,'float');ng=c['groups']
  bases=[256,8192,16384,20000,50000]
  strides=[k+7,(k+1)//2+5,2*ng+6,2*n+8,4*n+12]
  sizes=[(m-1)*strides[0]+k,(n-1)*strides[1]+(k+1)//2,(m-1)*strides[2]+2*ng,(ng-1)*strides[3]+2*n,(m-1)*strides[4]+4*n]
  assert all(bases[i]+sizes[i]<bases[i+1] for i in range(4))
  image=bytearray([0xcd]*65536)
  def put(base,stride,rows,width,values,unit=1):
   it=iter(values)
   for r in range(rows):
    for j in range(width):
     a=base+r*stride+j*unit;image[a:a+unit]=(next(it)&((1<<(8*unit))-1)).to_bytes(unit,'little')
  flat=lambda rows:[v for row in rows for v in row]
  put(bases[0],strides[0],m,k,flat(c['a']))
  put(bases[1],strides[1],n,(k+1)//2,c['packed'])
  put(bases[2],strides[2],m,ng,flat(c['sx']),2)
  put(bases[3],strides[3],ng,n,flat(c['sw']),2)
  tokens=[101+job,m,n,k,1,group]+bases+strides+sizes+c['output']
  (work/f'g{group}_job{job}.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
  (work/f'g{group}_job{job}.hex').write_text(''.join(f'{b:02x}\n' for b in image),encoding='ascii')

src=[ROOT/'rtl'/(n+'.sv') for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]
src += [ROOT/'tb/tb_axi_burst_protocol.sv',ROOT/'tb/tb_axi_chunk_protocol.sv',ROOT/'tb/tb_axi_read_protocol.sv',ROOT/'tb/w4a8_axi_memory.sv',ROOT/'tb/tb_w4a8_memory.sv']
project.run([sys.executable,ROOT/'model/w4a8_memory_vectors.py','--out',out/'vectors'],ROOT,out/'reference.log')
tops=[(n,'BURST_PROTOCOL_PASS') for n in ['tb_axi_burst_protocol','tb_axi_burst_protocol32','tb_axi_burst_protocol1','tb_axi_burst_protocol8']]
tops += [(n,'CHUNK_PROTOCOL_PASS') for n in ['tb_axi_chunk_protocol','tb_axi_chunk_protocol32']]
tops += [(n,'W4A8_MEMORY_TESTS_PASS') for n in ['tb_memory_round7_context','tb_memory_round7_off','tb_memory_round7_weight','tb_memory_round7_scale','tb_memory_round7_wide','tb_memory_round7_group_tail','tb_w4a8_memory','tb_w4a8_memory_alt','tb_w4a8_memory_unit','tb_w4a8_memory_burst','tb_w4a8_memory_burst8']]
for top,marker in tops:
 work=out/top;work.mkdir(exist_ok=True)
 for p in (out/'vectors').glob('*'):(work/p.name).write_bytes(p.read_bytes())
 if top=='tb_memory_round7_wide':extra_vectors(work,128)
 if top=='tb_memory_round7_group_tail':extra_vectors(work,12)
 if top in ['tb_w4a8_memory_burst','tb_w4a8_memory_burst8']:align_activation_vectors(work)
 identity=project.identity(src+[Path(__file__),project.PROFILE,ROOT/'model/w4a8_memory_vectors.py',ROOT/'model/w4a8_reference.py',ROOT/'scripts/project.py',ROOT/'scripts/run_xsim.tcl']+list(work.glob('g*_job*.*')))
 project.run([tools/'xvlog.bat','--sv',*src],work,work/'compile.log')
 project.run([tools/'xelab.bat',top,'-s','sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
 log=project.run([tools/'xsim.bat','sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log')
 assert project.valid_log(log,marker),top
 rec=dict(top=top,source_sha256=identity,result=next(x for x in log.splitlines() if x.startswith(marker)))

 if top=='tb_w4a8_memory_burst':
  rec['negative_probes']=[]
  for flag in ['corrupt_weight_cache','corrupt_sx_cache']:
   bad=project.run([tools/'xsim.bat','sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix(),'-testplusarg',flag],work,work/(flag+'.log'),allow_failure=True)
   assert 'W4A8_MEMORY_CHECK_FAILED packet data/keep exact' in bad and not project.valid_log(bad,marker),flag
   rec['negative_probes'].append(dict(probe=flag,expected_failure=True))
 result['simulations'].append(rec);save();print(rec['result'],flush=True)
result['status']='PASS';save();print('ROUND7_PROTOCOL_PASS',flush=True)
