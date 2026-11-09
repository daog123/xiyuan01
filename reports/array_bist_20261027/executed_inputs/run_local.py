"""Simulate and implement autonomous array BIST; no general-purpose board IO."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess,sys
ROOT=Path(__file__).parent.resolve();PROJECT=Path('E:/speed-up');TOOLS=Path('E:/AMDDesignTools/2025.2/Vivado/bin')
TARGET_PART='xcvu9p_CIV-flgb2104-2-i'
def run(args,cwd,log):
    env=os.environ.copy();env['PYTHONDONTWRITEBYTECODE']='1'
    with log.open('w',encoding='utf-8') as out:r=subprocess.run(list(map(str,args)),cwd=cwd,env=env,stdout=out,stderr=subprocess.STDOUT)
    content=log.read_text(encoding='utf-8',errors='replace')
    if r.returncode:raise RuntimeError(str(log)+'\n'+content[-4000:])
    return content
def main():
    p=argparse.ArgumentParser();p.add_argument('--variant',choices=['diag_civ','positive_civ']);args=p.parse_args()
    run([sys.executable,ROOT/'generate_vectors.py'],ROOT,ROOT/'vectors.log')
    manifest=json.loads((ROOT/'vectors.json').read_text())
    sources=[PROJECT/'rtl/mac_pe.sv',PROJECT/'rtl/w4a8_wave.sv',ROOT/'array_bist_engine.sv',ROOT/'done_telemetry.sv']
    inputs=sources+[ROOT/'array_selftest_top.sv',ROOT/'generate_vectors.py',ROOT/'shapes.svh',ROOT/'a.hex',ROOT/'b.hex',ROOT/'golden.hex',ROOT/'decode_done.py',Path(__file__).resolve()]
    hashes={str(f):hashlib.sha256(f.read_bytes()).hexdigest() for f in inputs}
    if args.variant is None:
        sources.append(ROOT/'tb_array_bist.sv')
        run([TOOLS/'xvlog.bat','--sv','-i',ROOT.as_posix(),*sources],ROOT,ROOT/'compile.log')
        run([TOOLS/'xelab.bat','tb_array_bist','-s','array_sim','-timescale','1ns/1ps'],ROOT,ROOT/'elaborate.log')
        (ROOT/'sim.tcl').write_text('run all\nquit\n')
        log=run([TOOLS/'xsim.bat','array_sim','-tclbatch',(ROOT/'sim.tcl').as_posix()],ROOT,ROOT/'simulation.log')
        assert 'ARRAY_BIST_SIM_PASS' in log and not re.search(r'Fatal:|^ERROR:|CHECK_FAILED|TIMEOUT',log,re.M),log[-3000:]
        m=re.search(r'ARRAY_BIST_SIM_PASS [^\r\n]+',log);print(m[0],flush=True)
        assert int(re.search(r'checksum=([0-9a-f]+)',m[0])[1],16)==manifest['actual_checksum16']
        log=run([sys.executable,ROOT/'decode_done.py',ROOT/'telemetry_samples.csv','--expected-status','1','--checksum',str(manifest['actual_checksum16'])],ROOT,ROOT/'decode_sim.log')
        assert 'DONE_TELEMETRY_DECODE_PASS' in log
        log=run([sys.executable,ROOT/'decode_done.py',ROOT/'telemetry_samples.csv','--expected-status','2','--checksum',str(manifest['actual_checksum16'])],ROOT,ROOT/'decode_negative_sim.log')
        assert 'DONE_TELEMETRY_DECODE_PASS' in log
        (ROOT/'simulation_result.json').write_text(json.dumps(dict(status='PASS',outputs=128,cases=8,negative_errors=1,checksum16=manifest['actual_checksum16'],source_sha256=hashes),indent=2)+'\n')
        print('ARRAY_BIST_AND_TELEMETRY_SIM_PASS',flush=True)
    else:
        assert json.loads((ROOT/'simulation_result.json').read_text())['status']=='PASS'
        out=ROOT/args.variant
        if out.exists():raise RuntimeError('variant output already exists: '+str(out))
        out.mkdir()
        mode=0 if args.variant.startswith('diag') else 1;corrupt=int(args.variant=='negative')
        source_names=sources+[ROOT/'array_selftest_top.sv']
        tcl='set_param general.maxThreads 8\n'
        tcl+='read_verilog -sv [list '+' '.join('{'+f.as_posix()+'}' for f in source_names)+']\n'
        tcl+='set_property include_dirs {'+ROOT.as_posix()+'} [current_fileset]\n'
        tcl+='synth_design -top array_selftest_top -part '+TARGET_PART+' -flatten_hierarchy none -generic {MODE=%d CORRUPT_GOLDEN=%d}\n'%(mode,corrupt)
        tcl+='create_clock -name cfg_osc -period 16.000 [get_pins startup/CFGMCLK]\n'
        tcl+='create_generated_clock -name selftest_clk -divide_by 8 -source [get_pins startup/CFGMCLK] [get_pins clock_divider/O]\n'
        tcl+='set_property BITSTREAM.CONFIG.UNUSEDPIN Pullnone [current_design]\n'
        tcl+='opt_design\nplace_design\nphys_opt_design\nroute_design\n'
        for report,name in [('report_timing_summary','timing.rpt'),('report_utilization','utilization.rpt'),('report_drc','drc.rpt')]:
            tcl+=report+' -file {'+(out/name).as_posix()+'}\n'
        tcl+='if {[llength [get_ports]] != 0} {error "unexpected general-purpose IO"}\n'
        tcl+='set bad [get_timing_paths -quiet -max_paths 1 -slack_lesser_than 0]\nif {[llength $bad] != 0} {error "negative setup slack"}\n'
        tcl+='write_checkpoint -force {'+(out/'routed.dcp').as_posix()+'}\n'
        tcl+='write_bitstream -force {'+(out/'array_selftest.bit').as_posix()+'}\n'
        tcl+='puts "ARRAY_AUTONOMOUS_BITSTREAM_PASS variant='+args.variant+'"\nexit\n'
        (out/'build.tcl').write_text(tcl,encoding='utf-8')
        log=run([TOOLS/'vivado.bat','-mode','batch','-source',(out/'build.tcl').as_posix()],ROOT,out/'console.log')
        assert 'ARRAY_AUTONOMOUS_BITSTREAM_PASS' in log
        bit=out/'array_selftest.bit'
        raw=bit.read_bytes();sync=raw.index(bytes.fromhex('aa995566'));packet=raw[sync:sync+8192]
        idheader=packet.index(bytes.fromhex('30018001'))
        assert int.from_bytes(packet[idheader+4:idheader+8],'big')==0x04b35093,'CIV IDCODE mismatch'
        assert TARGET_PART.encode() in raw[:260]
        assert all(hashlib.sha256(Path(f).read_bytes()).hexdigest()==s for f,s in hashes.items())
        result=dict(status='PASS',variant=args.variant,mode=mode,corrupt_golden=bool(corrupt),
                    bit_bytes=bit.stat().st_size,bit_sha256=hashlib.sha256(bit.read_bytes()).hexdigest(),
                    checksum16=manifest['actual_checksum16'],source_sha256=hashes,general_purpose_io=0,
                    target_part=TARGET_PART,idcode='0x04b35093',self_rtl_on_fpga=False)
        (out/'build_result.json').write_text(json.dumps(result,indent=2)+'\n')
        print('ARRAY_AUTONOMOUS_BUILD_PASS '+args.variant,flush=True)
if __name__=='__main__':main()
