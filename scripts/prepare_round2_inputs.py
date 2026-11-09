"""Prepare deterministic vectors, frozen baseline and pinned upstream dependencies."""
from pathlib import Path
import hashlib,importlib.util,json,shutil,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
def run(*args):subprocess.run([sys.executable,*map(str,args)],cwd=ROOT,check=True)
if not (ROOT/'build/w4a8_vectors/group32.json').exists():run(ROOT/'model/w4a8_reference.py')
if not (ROOT/'build/w4a8_systolic_vectors/group32.json').exists():run(ROOT/'model/w4a8_systolic_vectors.py')
if not (ROOT/'build/compute_experiments/common_cases.json').exists():
 sys.path.insert(0,str(ROOT/'scripts'));from run_compute_experiments import generate
 out=ROOT/'build/compute_experiments';out.mkdir(parents=True,exist_ok=True);generate(out)
for name,rel in [('w4a8_wave_round1.sv','rtl/w4a8_wave.sv'),('tb_w4a8_wave_round1.sv','tb/tb_w4a8_wave.sv')]:
 source=ROOT/'tb/baselines'/name;target=ROOT/'build/round2_baseline'/rel;target.parent.mkdir(parents=True,exist_ok=True)
 if target.exists():assert source.read_bytes()==target.read_bytes(),'baseline identity mismatch: '+str(target)
 else:shutil.copy2(source,target)
spec=importlib.util.spec_from_file_location('pinned_upstream',ROOT/'experiments/compute_upstream/run_upstream_compute.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
manifest=json.loads((ROOT/'experiments/compute_upstream/sources.json').read_text())
base=ROOT/'build/upstream_compute/sources'
for name in ['openTPU','llama-fpga']:module.stage(manifest[name],base/name,None)
destination=ROOT/'build/upstream_compute/llama_core/MulAddSGNew_extracted.v';destination.parent.mkdir(parents=True,exist_ok=True)
temporary=destination.with_name('fresh_extracted.v');module.extract(base/'llama-fpga/DataPath_xN.v',temporary)
if destination.exists():assert destination.read_text()==temporary.read_text(),'derived upstream core differs from pinned source'
else:shutil.copy2(temporary,destination)
print('ROUND2_INPUTS_READY')
