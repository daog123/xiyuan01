import argparse,csv,json
from pathlib import Path
from decode_done import decode
p=argparse.ArgumentParser();p.add_argument('csv',type=Path);p.add_argument('--mode',choices=['diag','array'],required=True);p.add_argument('--checksum',type=lambda s:int(s,0));args=p.parse_args()
samples=[]
for row in csv.reader(args.csv.read_text().splitlines()):
    if row and not row[0].startswith('#'):samples.append((float(row[0]),int(row[1],0)&1))
frames=decode(samples)
if args.mode=='diag':
    accepted=[f for f in frames if f['status']==13 and f['cases']==0 and f['checksum']==0xd10a and f['errors']==0]
    passed=len(accepted)>=2
else:
    positive=[f for f in frames if f['status']==1 and f['cases']==8 and f['checksum']==args.checksum and f['errors']==0]
    negative=[f for f in frames if f['status']==2 and f['cases']==8 and f['checksum']==args.checksum and f['errors']==1]
    accepted=positive+negative;passed=len(positive)>=2 and len(negative)>=2
result=dict(status='PASS' if passed else 'FAIL',mode=args.mode,physical_capture=True,accepted_frames=len(accepted),frames=frames,
            self_rtl_on_fpga=bool(passed and args.mode=='array'))
args.csv.with_suffix('.decoded.json').write_text(json.dumps(result,indent=2)+'\n')
print('DONE_CAPTURE_'+result['status']+' '+json.dumps(result))
raise SystemExit(0 if passed else 1)
