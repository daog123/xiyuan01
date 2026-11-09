"""Memory-backed long-K LINEAR comparison, current 4x4/TILE_K32 main profile."""
from pathlib import Path
import csv,json,os,random,re,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'));sys.path.insert(0,str(ROOT/'model'))
import project
from w4a8_reference import reference
OUT=ROOT/'build/round3_large';OUT.mkdir(parents=True,exist_ok=True)
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
def generate():
 out=OUT/'vectors';out.mkdir(exist_ok=True)
 for cid,(m,k) in enumerate([(1,512),(8,512),(1,4096),(8,4096)]):
  n=64;g=k//32;rng=random.Random(3300+cid);a=[[rng.randint(-16,16) for _ in range(k)] for _ in range(m)]
  w=[[rng.randint(-8,7) for _ in range(n)] for _ in range(k)];sx=[[4096]*g for _ in range(m)];sw=[[rng.choice([1200,4096,6800]) for _ in range(n)] for _ in range(g)]
  y,_,_=reference(a,w,sx,sw,32);image=bytearray([0xcd]*262144);rd=bytearray(262144);wr=bytearray(262144)
  def put(addr,data):image[addr:addr+len(data)]=bytes(data);rd[addr:addr+len(data)]=b'\x01'*len(data)
  def word(x,n):return (x&((1<<(8*n))-1)).to_bytes(n,'little')
  for row in range(m):
   put(4096+row*k,bytes(x&255 for x in a[row]));put(40000+row*2*g,b''.join(word(x,2) for x in sx[row]))
  for col in range(n):put(65536+col*k//2,bytes((w[q][col]&15)|((w[q+1][col]&15)<<4) for q in range(0,k,2)))
  for group in range(g):put(200000+group*2*n,b''.join(word(x,2) for x in sw[group]))
  expected=bytearray(image);expected[240000:240000+4*m*n]=b''.join(word(x,4) for x in y);wr[240000:240000+4*m*n]=b'\x01'*(4*m*n)
  task=[4400+cid,m,n,k,4096,65536,40000,200000,240000,k,k//2,2*g,2*n,4*n,m*k,n*k//2,2*g*m,2*n*g,4*n*m]
  (out/f'case{cid}.txt').write_text('\n'.join(map(str,task))+'\n')
  for name,data in [('input',image),('expected',expected),('read',rd),('write',wr)]:
   (out/f'case{cid}.{name}.hex').write_text(''.join(f'{x:02x}\n' for x in data),encoding='ascii')
 return out
def main():
 vectors=generate();src=[ROOT/'rtl'/(x+'.sv') for x in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]
 src +=[ROOT/'tb/llm_test_shells.sv',ROOT/'tb/system_axi_memory.sv',Path(__file__).with_name('tb_large_memory.sv')]
 result=dict(status='RUNNING',measurement='memory-backed LINEAR 4x4 TILE_K32; READ_DELAY8 WRITE_DELAY4, 64-bit bus, one outstanding; not board/model',variants=[],comparison=[])
 def save():(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 save();rows=[]
 for name in ['byte_gather','bounded_chunks']:
  work=OUT/name;work.mkdir(exist_ok=True)
  for p in vectors.glob('*'):(work/p.name).write_bytes(p.read_bytes())
  selected=[ROOT/'tb/baselines'/(p.stem+'_round2.sv') if name=='byte_gather' and p.stem in ['w4a8_memory_packet','w4a8_memory_bridge'] else p for p in src]
  identity=project.identity(selected+[Path(__file__)]+list(vectors.glob('*'))+[ROOT/'model/w4a8_reference.py'])
  project.run([TOOLS/'xvlog.bat','--sv',*selected],work,work/'compile.log');project.run([TOOLS/'xelab.bat','tb_large_memory','-s','large','-timescale','1ns/1ps'],work,work/'elaborate.log')
  command=[TOOLS/'xsim.bat','large','-tclbatch',(ROOT/'scripts/run_w4a8_memory_xsim.tcl').as_posix()]
  log=project.run(command,work,work/'run.log');assert project.valid_log(log,'LARGE_MEMORY_PASS'),name
  measurements=[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',x)} for x in re.findall(r'LARGE_RECORD ([^\r\n]+)',log)];assert len(measurements)==4
  rec=dict(name=name,source_sha256=identity,results=measurements);result['variants'].append(rec);save();print(name,'LARGE_MEMORY_PASS cases=4',flush=True)
 for old,new in zip(*[r['results'] for r in result['variants']]):
  for key in ['case','M','N','K','payload','writes','acks']:assert old[key]==new[key],key
  assert new['cycles']<old['cycles'] and new['writes']==new['acks'];macs=new['M']*new['N']*new['K']
  result['comparison'].append(dict(M=new['M'],N=new['N'],K=new['K'],old_cycles=old['cycles'],new_cycles=new['cycles'],speedup=old['cycles']/new['cycles'],old_read_transactions=old['reads'],new_read_transactions=new['reads'],read_payload_bytes=new['payload'],writes=new['writes'],acks=new['acks'],valid_MACs=macs,old_MAC_per_clock=macs/old['cycles'],new_MAC_per_clock=macs/new['cycles']))
 result['status']='PASS';save()
 with (OUT/'comparison.csv').open('w',encoding='utf-8-sig',newline='')as f:
  writer=csv.DictWriter(f,fieldnames=list(result['comparison'][0]));writer.writeheader();writer.writerows(result['comparison'])
 print('ROUND3_LARGE_PASS paired_cases=4 full_image_jobs=8',flush=True)
if __name__=='__main__':main()
