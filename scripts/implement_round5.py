"""Isolated old/new 4x4 and 8x8 physical implementation, same part and clock."""
from pathlib import Path
import argparse,json,os,re
import project
ROOT=project.ROOT;OUT=ROOT/'build/round5_physical'
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
def main():
    p=argparse.ArgumentParser();p.add_argument('--names',nargs='*');args=p.parse_args()
    for name,rows,old in [('before8',8,True),('after8',8,False),('before4',4,True),('after4',4,False)]:
        if args.names and name not in args.names:continue
        work=OUT/name;work.mkdir(parents=True,exist_ok=True)
        core=ROOT/('tb/baselines/w4a8_wave_round4.sv' if old else 'rtl/w4a8_wave.sv')
        src=[ROOT/'rtl'/f'{n}.sv' for n in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack']]+[core,ROOT/'scripts/implement_round5_core.tcl',Path(__file__)]
        result=dict(status='RUNNING',rows=rows,cols=rows,source_sha256=project.identity(src));path=work/'result.json';path.write_text(json.dumps(result,indent=2))
        try:
            log=project.run([TOOLS/'vivado.bat','-mode','batch','-source',ROOT/'scripts/implement_round5_core.tcl','-tclargs',core,rows],work,work/'console.log')
            assert 'ROUND5_OOC_PASS' in log
            m=re.search(r'WNS=([\d.-]+) WHS=([\d.-]+)',(work/'timing_values.txt').read_text());assert m and min(float(m[1]),float(m[2]))>=0
            util=(work/'utilization.rpt').read_text();resources={key:float(re.search(r'^\|\s*'+re.escape(key)+r'\*?\s*\|\s*([\d.]+)',util,re.M)[1]) for key in ['CLB LUTs','CLB Registers','DSPs','Block RAM Tile']}
            route=(work/'route_status.rpt').read_text();r={key:int(re.search('# of '+label+r'\.+\s*:\s*(\d+)',route)[1]) for key,label in [('routable','routable nets'),('fully_routed','fully routed nets'),('errors','nets with routing errors')]}
            assert r['errors']==0 and r['routable']==r['fully_routed']
            result.update(status='PASS',WNS_ns=float(m[1]),WHS_ns=float(m[2]),resources=resources,route=r)
            print(name,'ROUND5_OOC_PASS',m[0],resources,flush=True)
        except Exception as exc:result.update(status='FAIL',error=str(exc));raise
        finally:path.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
