from pathlib import Path
import json,os,re,sys
import project
root=project.ROOT;tools=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
for name,rows,broadcast,packed in [('default4',4,0,0),('tile32',8,0,0),('broadcast8',8,1,0),('packed8',8,1,1)]:
 work=root/'build/round2_compute'/name/'implementation';work.mkdir(parents=True,exist_ok=True)
 result={'status':'RUNNING','source_sha256':project.identity([root/'rtl'/f'{n}.sv' for n in ['sync_sdp_ram','mac_pe','mac_array','systolic_pe','systolic_array','w4_unpack','w4a8_wave']]+[root/'scripts/implement_round2_core.tcl',Path(__file__).resolve()])}
 path=work/'result.json';path.write_text(json.dumps(result))
 try:
  log=project.run([tools/'vivado.bat','-mode','batch','-source',(root/'scripts/implement_round2_core.tcl').as_posix(),'-tclargs',rows,broadcast,packed],work,work/'console.log')
  assert 'ROUND2_OOC_PASS' in log
  timing=(work/'timing_values.txt').read_text();m=re.search(r'WNS=([\d.-]+) WHS=([\d.-]+)',timing);assert m and min(float(m[1]),float(m[2]))>=0
  util=(work/'utilization.rpt').read_text();resources={key:float(re.search(r'^\|\s*'+re.escape(key)+r'\*?\s*\|\s*([\d.]+)',util,re.M)[1]) for key in ['CLB LUTs','CLB Registers','DSPs','Block RAM Tile']}
  route=(work/'route_status.rpt').read_text();r={key:int(re.search('# of '+label+r'\.+\s*:\s*(\d+)',route)[1]) for key,label in [('routable','routable nets'),('fully_routed','fully routed nets'),('errors','nets with routing errors')]}
  assert r['errors']==0 and r['routable']==r['fully_routed']
  result.update(status='PASS',WNS_ns=float(m[1]),WHS_ns=float(m[2]),resources=resources,route=r);print(name,'OOC_PASS',timing.strip(),resources,flush=True)
 except Exception as e:result.update(status='FAIL',error=str(e));raise
 finally:path.write_text(json.dumps(result,indent=2)+'\n')
