"""Bounded chunk protocol and Q loader backpressure/error/reset checks."""
from pathlib import Path
import json,os,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
out=ROOT/'build/round3_protocol';out.mkdir(parents=True,exist_ok=True)
result=dict(status='RUNNING',simulations=[]);(out/'result.json').write_text(json.dumps(result))
src=[ROOT/'rtl'/(n+'.sv') for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]
src += [ROOT/'tb/tb_axi_chunk_protocol.sv',ROOT/'tb/tb_attention_q_dma.sv']
for top,marker in [('tb_axi_chunk_protocol','CHUNK_PROTOCOL_PASS'),('tb_axi_chunk_protocol32','CHUNK_PROTOCOL_PASS'),('tb_attention_q_dma','Q_DMA_PROTOCOL_PASS'),('tb_attention_q_dma3','Q_DMA_PROTOCOL_PASS'),('tb_attention_q_dma1','Q_DMA_PROTOCOL_PASS')]:
 work=out/top;work.mkdir(exist_ok=True);identity=project.identity(src+[Path(__file__)])
 project.run([tools/'xvlog.bat','--sv',*src],work,work/'compile.log')
 project.run([tools/'xelab.bat',top,'-s','sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
 log=project.run([tools/'xsim.bat','sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log')
 assert project.valid_log(log,marker),top
 result['simulations'].append(dict(top=top,source_sha256=identity,result=next(x for x in log.splitlines() if x.startswith(marker))))
 print(result['simulations'][-1]['result'],flush=True)
result['status']='PASS';(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
