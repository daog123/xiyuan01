"""Retain independent byte-address and packet oracle with multi-byte AXI beats."""
from pathlib import Path
import json,os,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
out=ROOT/'build/round3_storage';out.mkdir(parents=True,exist_ok=True)
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
project.run([sys.executable,ROOT/'model/w4a8_memory_vectors.py','--out',out/'vectors'],ROOT,out/'reference.log')
src=[ROOT/'rtl'/(n+'.sv') for n in ['w4a8_memory_pkg','w4a8_memory_validate','w4a8_axi_read','w4a8_axi_write','w4a8_memory_packet','w4a8_memory_bridge','sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']]
src +=[ROOT/'tb/w4a8_axi_memory.sv',ROOT/'tb/tb_w4a8_memory.sv']
result=dict(status='RUNNING',simulations=[]);(out/'result.json').write_text(json.dumps(result))
for top in ['tb_w4a8_memory','tb_w4a8_memory8','tb_w4a8_memory_alt','tb_w4a8_memory_unit']:
 w=out/top;w.mkdir(exist_ok=True)
 for f in (out/'vectors').glob('*'):(w/f.name).write_bytes(f.read_bytes())
 hashes=project.identity(src+[Path(__file__),ROOT/'model/w4a8_memory_vectors.py',ROOT/'model/w4a8_reference.py'])
 project.run([tools/'xvlog.bat','--sv',*src],w,w/'compile.log');project.run([tools/'xelab.bat',top,'-s','sim','-timescale','1ns/1ps'],w,w/'elaborate.log')
 command=[tools/'xsim.bat','sim','-tclbatch',(ROOT/'scripts/run_xsim.tcl').as_posix()]
 log=project.run(command,w,w/'run.log');assert project.valid_log(log,'W4A8_MEMORY_TESTS_PASS'),top
 found=next(s for s in log.splitlines() if s.startswith('W4A8_MEMORY_TESTS_PASS'));print(found,flush=True)
 result['simulations'].append(dict(top=top,source_sha256=hashes,result=found))
 if len(result['simulations'])==1:
  bad=project.run(command+['-testplusarg','corrupt_expected'],w,w/'negative.log',allow_failure=True)
  assert 'W4A8_MEMORY_CHECK_FAILED' in bad and not project.valid_log(bad,'W4A8_MEMORY_TESTS_PASS')
result['status']='PASS';(out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
