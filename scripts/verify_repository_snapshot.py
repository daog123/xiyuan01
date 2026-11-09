"""Verify the files in this published snapshot without creating build output."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
def main():
    record=json.loads((ROOT/'reports/sync_20261109/snapshot_manifest.json').read_text(encoding='utf-8'))
    failed=[]
    for name,sha in record['files'].items():
        p=ROOT/name
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=sha:failed.append(name)
    if failed:raise SystemExit('SNAPSHOT_DIFFERS: '+', '.join(failed[:20]))
    print('REPOSITORY_SNAPSHOT_PASS files='+str(len(record['files'])))
if __name__=='__main__':main()
