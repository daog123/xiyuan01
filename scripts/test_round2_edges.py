"""Additional folded-GEMV aborts, scalar fallback and odd-parameter regression."""
from pathlib import Path
import json,os,re
import project
root=project.ROOT;out=root/'build/round2_edges';out.mkdir(exist_ok=True)
tb=root/'tb/tb_w4a8_wave.sv';text=tb.read_text();text=text[:text.index('module tb_w4a8_wave_directed')]
text=text.replace('module tb_w4a8_wave;','module tb_w4a8_faults;')
text=text.replace('if(MODES>1 && cid==10)', 'if(MODES>1 && (cid==10 || (cid==4 && GEMV_FOLD && dut.FOLD_SUPPORTED)))')
text=text.replace('if(SYSTOLIC && ROWS+COLS>2 && !BROADCAST_MAC && !PACKED_MAC) begin\n                mode=', 'if(SYSTOLIC && ROWS+COLS>2 && !BROADCAST_MAC && !PACKED_MAC && !dut.folded) begin\n                mode=')
text=text.replace('extra_post_resets==1','extra_post_resets==(GEMV_FOLD && dut.FOLD_SUPPORTED?2:1)')
fault_tb=out/'tb_w4a8_faults.sv';fault_tb.write_text(text)
sources=[root/'rtl'/f'{n}.sv' for n in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']]+[root/'tb/w4a8_reuse_memory.sv',fault_tb]
tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
records=[]
for name,rows,cols,tile,group,packed in [('fold4',4,4,32,32,0),('fold8',8,8,32,32,0),('packed8',8,8,32,32,1),('scalar',1,1,32,32,0),('odd',2,3,5,12,0)]:
 work=out/name;work.mkdir(exist_ok=True)
 cases=json.loads((root/f'build/w4a8_systolic_vectors/group{group}.json').read_text())['cases']
 tokens=[len(cases)]
 # A cold first M1/N1 task must not depend on uninitialized adjacent columns.
 for cid in [6]+[i for i in range(len(cases)) if i!=6]:
  c=cases[cid];tokens +=[cid,c['m'],c['n'],c['k'],c['groups']]+[v for row in c['a'] for v in row]+c['packed']+[v for row in c['sx'] for v in row]+[v for row in c['sw'] for v in row]+c['output']+[v for row in c['psum'] for g in row for v in g]
 (work/'vectors.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
 wrapper=work/'wrapper.sv';wrapper.write_text(f'module edge_test;tb_w4a8_faults #(.ROWS({rows}),.COLS({cols}),.TILE_K({tile}),.GROUP_SIZE({group}),.COMPACT_SLOTS(1),.EFFECTIVE_DRAIN(1),.GEMV_FOLD(1),.COPY_LANES({cols}),.POST_LANES({min(2,cols)}),.PACKED_MAC({packed}),.BROADCAST_MAC({packed})) test();endmodule\n')
 hashes=project.identity(sources+[tb,wrapper,Path(__file__).resolve(),work/'vectors.txt'])
 project.run([tools/'xvlog.bat','--sv',*sources,wrapper],work,work/'compile.log');project.run([tools/'xelab.bat','edge_test','-s','edge_sim','-timescale','1ns/1ps'],work,work/'elaborate.log')
 log=project.run([tools/'xsim.bat','edge_sim','-tclbatch',(root/'scripts/run_xsim.tcl').as_posix()],work,work/'run.log');assert project.valid_log(log,'W4A8_WAVE_TESTS_PASS'),work
 marker=re.search(r'W4A8_WAVE_TESTS_PASS [^\r\n]+',log)[0];records.append(dict(name=name,source_sha256=hashes,result=marker));print(name,marker,flush=True)
packed_work=out/'packed_exhaustive';packed_work.mkdir(exist_ok=True)
src=[root/'rtl/w4a8_wave.sv',root/'tb/tb_packed_pair.sv'];hashes=project.identity(src+[Path(__file__).resolve()])
project.run([tools/'xvlog.bat','--sv',*src],packed_work,packed_work/'compile.log');project.run([tools/'xelab.bat','tb_packed_pair','-s','packed_sim','-timescale','1ns/1ps'],packed_work,packed_work/'elaborate.log')
log=project.run([tools/'xsim.bat','packed_sim','-tclbatch',(root/'scripts/run_xsim.tcl').as_posix()],packed_work,packed_work/'run.log');assert project.valid_log(log,'PACKED_PAIR_EXHAUSTIVE_PASS')
records.append(dict(name='packed_exhaustive',source_sha256=hashes,result=re.search(r'PACKED_PAIR_EXHAUSTIVE_PASS [^\r\n]+',log)[0]))
(out/'result.json').write_text(json.dumps(dict(status='PASS',simulations=records),indent=2)+'\n');print('ROUND2_EDGE_TESTS_PASS',flush=True)
