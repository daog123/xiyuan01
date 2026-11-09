"""Prepare own-project deterministic vectors without fetching upstream code."""
from pathlib import Path
import json,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def run(script):subprocess.run([sys.executable,str(ROOT/script)],cwd=ROOT,check=True)
def main():
    if not all((ROOT/f'build/w4a8_vectors/group{g}.json').exists() for g in [32,12]):run('model/w4a8_reference.py')
    if not all((ROOT/f'build/w4a8_systolic_vectors/group{g}.json').exists() for g in [32,12]):run('model/w4a8_systolic_vectors.py')
    for group in [32,12]:
        d=json.loads((ROOT/f'build/w4a8_systolic_vectors/group{group}.json').read_text())
        assert d['group_size']==group and len(d['cases'])==15
    out=ROOT/'build/compute_experiments';out.mkdir(exist_ok=True)
    if not (out/'common_cases.json').exists():
        sys.path.insert(0,str(ROOT/'scripts'));from run_compute_experiments import generate
        generate(out)
    data=json.loads((out/'common_cases.json').read_text());assert len(data)==9
    assert {(c['m'],c['n'],c['k']) for c in data}=={(m,64,k) for m in [1,4,8] for k in [128,512,4096]}
    print('ROUND5_INPUTS_READY local deterministic reference only')
if __name__=='__main__':main()
