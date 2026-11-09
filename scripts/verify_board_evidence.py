"""Read-only replay of archived physical samples; never opens hardware."""
from pathlib import Path,PureWindowsPath
import csv,gzip,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
EXP=ROOT/'experiments/array_bist_20261027'
REPORT=ROOT/'reports/array_bist_20261027'
sys.path.insert(0,str(EXP));from decode_done import decode

def main():
    result=json.loads((REPORT/'physical_validation_result.json').read_text(encoding='utf-8'))
    run=REPORT/'evidence'/result['physical_run']
    with (run/'done_samples.csv').open() as f:
        samples=[(float(r[0]),int(r[1],0)&1) for r in csv.reader(f) if r and not r[0].startswith('#')]
    frames=decode(samples)
    good=[f for f in frames if (f['status'],f['cases'],f['checksum'],f['errors'])==(1,8,0x1f41,0)]
    bad=[f for f in frames if (f['status'],f['cases'],f['checksum'],f['errors'])==(2,8,0x1f41,1)]
    assert len(good)>=2 and len(bad)>=2 and frames==result['frames']
    assert len(samples)==result['raw_samples']==72184
    assert 'REFERENCE_RESTORED\nFINAL_EXIT=0' in (run/'run.log').read_text()
    build=json.loads((REPORT/'implementation/positive_civ/build_result.json').read_text())
    for original,sha in build['source_sha256'].items():
        name=PureWindowsPath(original).name
        current=ROOT/'rtl'/name if name in ['mac_pe.sv','w4a8_wave.sv'] else EXP/name
        if name=='run_local.py':current=REPORT/'executed_inputs/run_local.py'
        assert hashlib.sha256(current.read_bytes()).hexdigest()==sha,name
    artifact=ROOT/'artifacts/array_bist_20261027'
    image=gzip.decompress((artifact/'array_selftest_c6.bit.gz').read_bytes())
    identity=json.loads((artifact/'image_manifest.json').read_text())
    assert hashlib.sha256(image).hexdigest()==identity['normalized_sha256']
    assert b'xcvu9p_CIV-flgb2104-2-i' in image[:260]
    assert bytes.fromhex('3001800104b35093') in image[:4096]
    print(json.dumps(dict(status='PASS',offline_replay=True,new_board_run=False,
                         samples=len(samples),normal_crc_frames=len(good),negative_crc_frames=len(bad),
                         source_identity='PASS',loaded_image_sha256=identity['normalized_sha256'])))
if __name__=='__main__':main()
