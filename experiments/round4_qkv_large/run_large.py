"""Actual Q/K/V M1 N64 K4096 graph, two committed decode steps."""
from pathlib import Path
import json,os,re,sys
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'scripts'));import project
OUT=ROOT/'build/round4_qkv_large';OUT.mkdir(parents=True,exist_ok=True)
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
def main():
 generator=OUT/'large_reference.py';g=(ROOT/'model/qkv_reference.py').read_text()
 g=g.replace("sys.path.insert(0,str(Path(__file__).resolve().parent/'vector'))",f"sys.path.insert(0,{str(ROOT/'model')!r});sys.path.insert(0,{str(ROOT/'model/vector')!r})")
 for a,b in [('for g in [32,3,1]:','for g in [32]:'),("[(9,13,'random'),(64,5,'clipped'),(1,1,'zero')]","[(64,4096,'random')]"),('65536','1048576'),('[(0,0),(0,1),(1,0)]','[(0,0),(0,1)]'),('4093','1024'),('10001+branch*2000','65536+branch*196608'),('16000+branch*1000','8000+branch*1000'),('19000+branch*2000','700000+branch*20000')]:
  assert a in g,a;g=g.replace(a,b)
 generator.write_text(g,encoding='utf-8')
 project.run([sys.executable,generator,'--out',OUT/'vectors'],ROOT,OUT/'reference.log')
 tb=(ROOT/'tb/tb_qkv_attention.sv').read_text();tb=tb[:tb.index('module tb_qkv_attention3;')]
 tb=tb.replace('module tb_qkv_attention #','module tb_qkv_large #').replace('0:65535','0:1048575').replace('i<65536','i<1048576')
 tb=tb.replace('.ADDR_WIDTH(ADDR_WIDTH),.BASE(BASE)) memory','.ADDR_WIDTH(ADDR_WIDTH),.SIZE(1048576),.BASE(BASE)) memory')
 tb=tb.replace('cid<3','cid<1').replace('step<3','step<2').replace('if(cid==0)begin','if(0)begin').replace('if(cid==0 && step==1)','if(0)').replace('if(cid==0 && step==2)','if(0)').replace('wd<1000000','wd<10000000')
 start=tb.index('        // Reset with a real');end=tb.index('        $display("QKV_TESTS_PASS',start);tb=tb[:start]+tb[end:]
 needle='''finish(0,13);for(integer j=0;j<3;j++)require'''
 replacement='''finish(0,13);$display("QKV_LARGE_RECORD step=%0d dimension=%0d k=%0d cycles=%0d reads=%0d read_bytes=%0d writes=%0d acks=%0d",step,dimension,active_plan.q_task.desc.k,elapsed_cycles,reads,memory.read_payload,writes,b_count);for(integer j=0;j<3;j++)require'''
 assert needle in tb;tb=tb.replace(needle,replacement)
 source=OUT/'tb_qkv_large.sv';source.write_text(tb,encoding='utf-8');work=OUT/'simulation';work.mkdir(exist_ok=True)
 for p in (OUT/'vectors').glob('*'):(work/p.name).write_bytes(p.read_bytes())
 sources=[ROOT/'rtl'/(n+'.sv')for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]+[ROOT/'tb/system_axi_memory.sv',source]
 result=dict(status='RUNNING',kind='actual numeric Q/K/V graph validation, not board or model throughput',M=1,N=64,K=4096,group_size=32,steps=2,
  source_sha256=project.identity(sources+[Path(__file__),generator]+list((ROOT/'model').rglob('*.py'))+list((OUT/'vectors').glob('*'))))
 def save():(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n')
 save()
 try:
  project.run([TOOLS/'xvlog.bat','--sv',*sources],work,work/'compile.log');project.run([TOOLS/'xelab.bat','tb_qkv_large','-s','large','-timescale','1ns/1ps'],work,work/'elaborate.log')
  log=project.run([TOOLS/'xsim.bat','large','-tclbatch',(ROOT/'scripts/run_w4a8_memory_xsim.tcl').as_posix()],work,work/'run.log')
  assert project.valid_log(log,'QKV_TESTS_PASS')
  rows=[{k:int(v)for k,v in re.findall(r'(\w+)=(\d+)',line)}for line in re.findall(r'QKV_LARGE_RECORD ([^\r\n]+)',log)];assert len(rows)==2
  result.update(status='PASS',results=rows,result=next(s for s in log.splitlines()if s.startswith('QKV_TESTS_PASS')));print('QKV_LARGE_PASS steps=2 dimension=64 k=4096',flush=True)
 except Exception as error:result.update(status='FAIL',error=str(error));raise
 finally:save()
if __name__=='__main__':main()
