"""Validate the shell-facing LINEAR endpoint; does not create a board bitstream."""
import argparse,hashlib,json,os,re,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
NAMES=['task_desc_pkg','w4a8_memory_pkg','w4a8_memory_validate','w4a8_axi_read',
       'w4a8_axi_write','w4a8_memory_packet','w4a8_memory_bridge','sync_sdp_ram',
       'mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave',
       'w4a8_task_adapter','w4a8_team_top']

def run(args,cwd,log,allow_failure=False):
    env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
    with log.open('w',encoding='utf-8') as out:
        process=subprocess.run(list(map(str,args)),cwd=cwd,stdout=out,stderr=subprocess.STDOUT,env=env)
    log.with_suffix(log.suffix+'.exit').write_text(str(process.returncode)+'\n',encoding='ascii')
    content=log.read_text(encoding='utf-8',errors='replace')
    if process.returncode and not allow_failure:
        raise RuntimeError(str(log)+'\n'+content[-5000:])
    return content

def clean_pass(content):
    return 'W4A8_BOARD_TESTS_PASS' in content and not re.search(r'Fatal:|^ERROR:|CHECK_FAILED|_TIMEOUT',content,re.M)

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--project',type=Path,default=ROOT)
    parser.add_argument('--tools',type=Path,default=Path('E:/AMDDesignTools/2025.2/Vivado/bin'))
    parser.add_argument('--synthesize',action='store_true')
    parser.add_argument('--build',type=Path,default=ROOT/'build/board_endpoint')
    args=parser.parse_args();project=args.project.resolve();build=args.build.resolve();build.mkdir(parents=True,exist_ok=True)
    (build/'result.json').write_text('{"status":"RUNNING"}\n',encoding='utf-8')
    sources=[project/'rtl'/(n+'.sv') for n in NAMES]+[ROOT/'rtl/w4a8_board_control.sv',ROOT/'rtl/w4a8_board_top.sv',ROOT/'rtl/w4a8_board_ip.v']
    simulation_sources=sources+[project/'tb/w4a8_axi_memory.sv',ROOT/'tb/tb_w4a8_board.sv']
    inputs=simulation_sources+[Path(__file__).resolve(),project/'model/w4a8_memory_vectors.py',project/'model/w4a8_reference.py',
        project/'software/board_mailbox.py',project/'software/board_xdma_io.py',project/'software/test_board_mailbox.py',project/'software/w4a8_memory_task.py',
        project/'software/w4a8_task.py',project/'software/w4a8_runtime.py']
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (build/'source_sha256.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    run([sys.executable,project/'model/w4a8_memory_vectors.py','--out',build],project,build/'vectors.log')
    run([sys.executable,'-m','unittest','software.test_board_mailbox','-v'],project,build/'host_tests.log')
    sys.path.insert(0,str(project));sys.dont_write_bytecode=True
    from software.board_mailbox import descriptor_words
    from software.w4a8_task import W4A8Task
    from software.w4a8_memory_task import W4A8MemoryTask
    # Exercise host descriptor serialization through the real AXI-Lite RTL.
    for job in range(2):
        tokens=list(map(int,(build/f'g32_job{job}.txt').read_text().split()))
        tid,m,n,k,fmt,group=tokens[:6]
        bases=[0x800000000+b for b in tokens[6:11]];strides=tokens[11:16];sizes=tokens[16:21]
        task=W4A8MemoryTask(W4A8Task(tid,m,n,k,*bases,*strides,group_size=group),*sizes)
        words=descriptor_words(task)
        (build/f'g32_job{job}_mailbox.hex').write_text(''.join(f'{w:08x}\n' for w in words),encoding='ascii')
    run([args.tools/'xvlog.bat','--sv',*simulation_sources],build,build/'compile.log')
    run([args.tools/'xelab.bat','tb_w4a8_board','-s','board_sim','-timescale','1ns/1ps'],build,build/'elaborate.log')
    (build/'run.tcl').write_text('run all\nquit\n',encoding='ascii')
    command=[args.tools/'xsim.bat','board_sim','-tclbatch',(build/'run.tcl').as_posix()]
    log=run(command,build,build/'run.log');assert clean_pass(log),log[-5000:]
    marker=re.search(r'W4A8_BOARD_TESTS_PASS [^\r\n]+',log)[0]
    assert 'completions=8 outputs=326' in marker,marker
    print(marker,flush=True)
    negative={}
    for probe,expected in [('corrupt_expected','BOARD_CHECK_FAILED external Y bit exact'),('timeout_probe','BOARD_FORCED_TIMEOUT')]:
        bad=run(command+['-testplusarg',probe],build,build/(probe+'.log'),allow_failure=True)
        assert expected in bad and not clean_pass(bad),'failure probe did not fail for expected reason'
        negative[probe]='REJECTED'
    result=dict(status='PASS',scope='simulation',self_rtl_on_fpga=False,board_bitstream_generated=False,
                completions=8,outputs=326,address_width=64,test_address_base='0x800000000',
                marker=marker,negative_probes=negative,host_tests=11,host_serialization_in_rtl=True,source_sha256=hashes)
    if args.synthesize:
        synth=build/'synthesis';synth.mkdir(exist_ok=True)
        # This part is pinned to the successfully loaded reference image header.
        # Clock is an integration target, not an established shell clock.
        (synth/'clock.xdc').write_text('create_clock -name kernel_clk -period 10.000 [get_ports clk]\n',encoding='ascii')
        tcl='set wanted xcvu9p_CIV-flgb2104-2-i\nif {[llength [get_parts -quiet $wanted]] != 1} {error "REFERENCE_PART_UNAVAILABLE"}\n'
        tcl+='read_verilog -sv [list '+ ' '.join('{'+p.as_posix()+'}' for p in sources)+']\n'
        tcl+='read_xdc {'+(synth/'clock.xdc').as_posix()+'}\n'
        tcl+='synth_design -top w4a8_board_ip -part $wanted -mode out_of_context -flatten_hierarchy rebuilt\n'
        tcl+='write_checkpoint -force {'+(synth/'post_synth.dcp').as_posix()+'}\n'
        tcl+='report_utilization -file {'+(synth/'utilization.rpt').as_posix()+'}\n'
        tcl+='report_timing_summary -file {'+(synth/'timing.rpt').as_posix()+'}\n'
        tcl+='puts "W4A8_BOARD_ENDPOINT_SYNTHESIS_PASS part=$wanted"\nexit\n'
        (synth/'synth.tcl').write_text(tcl,encoding='utf-8')
        console=run([args.tools/'vivado.bat','-mode','batch','-source',(synth/'synth.tcl').as_posix()],synth,synth/'console.log')
        assert 'W4A8_BOARD_ENDPOINT_SYNTHESIS_PASS' in console
        result['synthesis']=dict(status='PASS',part='xcvu9p_CIV-flgb2104-2-i',clock_target_ns=10,
                                 implemented=False,pin_constraints=False,board_timing_closed=False,
                                 dcp_sha256=hashlib.sha256((synth/'post_synth.dcp').read_bytes()).hexdigest())
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==sha for p,sha in hashes.items()),'sources changed during validation'
    (build/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print('W4A8_BOARD_ENDPOINT_VALIDATION_PASS',flush=True)
if __name__=='__main__':main()
