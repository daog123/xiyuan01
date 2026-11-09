"""Additional compact-slot regression for non-power-of-two array and group sizes."""
import hashlib,json,os,sys
from pathlib import Path
import project
ROOT=project.ROOT
out=ROOT/'build/compact_alt';out.mkdir(parents=True,exist_ok=True)
sources=[ROOT/'rtl'/(n+'.sv') for n in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']]
sources += [ROOT/'tb/w4a8_reuse_memory.sv',ROOT/'tb/tb_w4a8_wave.sv']
wrapper=out/'wrapper.sv';wrapper.write_text('module tb_compact_alt;tb_w4a8_wave #(.ROWS(2),.COLS(3),.TILE_K(5),.GROUP_SIZE(12),.COMPACT_SLOTS(1)) test();endmodule\n',encoding='ascii')
(out/'vectors.txt').write_bytes((ROOT/'build/w4a8_systolic_vectors/group12.txt').read_bytes())
hashes=project.identity(sources+[wrapper,Path(__file__),out/'vectors.txt'])
(out/'result.json').write_text('{"status":"RUNNING"}',encoding='utf-8')
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
project.run([tools/'xvlog.bat','--sv',*sources,wrapper],out,out/'compile.log')
project.run([tools/'xelab.bat','tb_compact_alt','-s','compact_alt_sim','-timescale','1ns/1ps'],out,out/'elaborate.log')
log=project.run([tools/'xsim.bat','compact_alt_sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()],out,out/'run.log')
assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS')
import re
record=re.search(r'W4A8_WAVE_TESTS_PASS [^\r\n]+',log)[0]
(out/'result.json').write_text(json.dumps(dict(status='PASS',result=record,source_sha256=hashes),indent=2)+'\n',encoding='utf-8')
print('COMPACT_ALT_PASS',record,flush=True)
