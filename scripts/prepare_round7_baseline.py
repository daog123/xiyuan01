"""Restore only the frozen inputs required by the R7 paired benchmark."""
from pathlib import Path
import hashlib,json,shutil
ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'baselines/round6_for_round7'
target=ROOT/'build/round7_baseline'
manifest=json.loads((source/'manifest.json').read_text(encoding='utf-8'))
for name,sha in manifest['source_sha256'].items():
    old=source/'source'/name;new=target/'source'/name
    assert hashlib.sha256(old.read_bytes()).hexdigest()==sha,name
    if new.exists():
        assert hashlib.sha256(new.read_bytes()).hexdigest()==sha,'existing baseline differs: '+name
    else:
        new.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(old,new)
out=target/'manifest.json'
if out.exists():
    current=json.loads(out.read_text(encoding='utf-8'))['source_sha256']
    assert all(current.get(k)==v for k,v in manifest['source_sha256'].items()),'existing baseline manifest differs'
else:out.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print('ROUND7_FROZEN_INPUTS_READY files='+str(len(manifest['source_sha256'])))
