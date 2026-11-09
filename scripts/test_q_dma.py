"""Check Q prefetch capacity, exact reads, backpressure, read errors and reset."""
import json,os,re
from pathlib import Path
import project
root=project.ROOT;out=root/'build/q_dma_protocol';out.mkdir(parents=True,exist_ok=True)
sources=[root/p for p in ['rtl/attention_pkg.sv','rtl/w4a8_axi_read.sv','rtl/sync_sdp_ram.sv','rtl/vector/requant_group.sv','rtl/vector/requant_dynamic.sv','rtl/attention_q_dma.sv','tb/tb_attention_q_dma.sv']]
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
hashes=project.identity(sources+[Path(__file__)])
(out/'result.json').write_text('{"status":"RUNNING"}',encoding='utf-8')
project.run([tools/'xvlog.bat','--sv',*sources],out,out/'compile.log')
results=[]
for top in ['tb_attention_q_dma','tb_attention_q_dma3','tb_attention_q_dma1']:
    project.run([tools/'xelab.bat',top,'-s',top+'_sim','-timescale','1ns/1ps'],out,out/(top+'.elaborate.log'))
    log=project.run([tools/'xsim.bat',top+'_sim','-tclbatch',(root/'scripts/run_xsim.tcl').as_posix()],out,out/(top+'.run.log'))
    assert project.valid_log(log,'Q_DMA_PROTOCOL_PASS')
    marker=re.search(r'Q_DMA_PROTOCOL_PASS [^\r\n]+',log)[0];results.append(marker);print(marker,flush=True)
(out/'result.json').write_text(json.dumps(dict(status='PASS',simulations=results,source_sha256=hashes),indent=2)+'\n',encoding='utf-8')
