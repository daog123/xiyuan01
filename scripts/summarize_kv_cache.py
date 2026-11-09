"""Check current source identity plus actual simulator/probe evidence."""
import csv
import hashlib
import json
import re
from pathlib import Path
from read_text_log import read_text

root=Path(__file__).resolve().parents[1]
summary={'tensor_handoff':{},'kv':{},'attention_integrated':False,'two_layer_numerics_integrated':False}
for name in ['tb_w4a8_tensor_dependency','tb_kv_cache','tb_kv_cache_group3']:
    work=root/'build'/name
    assert (work/'PASS.txt').exists(),f'{name} missing actual PASS'
    inputs=json.loads(read_text(work/'source_inputs.json'))
    for path,expected in inputs['files'].items():
        assert hashlib.sha256((root/path).read_bytes()).hexdigest()==expected,f'stale evidence: {path}'
    log=read_text(work/'run.log')
    assert not re.search(r'Fatal:|FAILED|TIMEOUT|^ERROR:',log,re.M)
    if name=='tb_w4a8_tensor_dependency':
        m=re.search(r'TENSOR_DEPENDENCY_TESTS_PASS checks=(\d+) handoffs=(\d+)',log);assert m
        summary['tensor_handoff']={'checks':int(m[1]),'handoffs':int(m[2]),'scope':'dependency and workspace lease gate; external fences, no numerical module'}
    else:
        m=re.search(r'KV_CACHE_TESTS_PASS group=(\d+) commands=(\d+) checks=(\d+) append_stalls=(\d+) read_stalls=(\d+)',log);assert m
        rows=list(csv.DictReader((work/'kv_results.csv').open()))
        assert len(rows)==int(m[2])
        summary['kv'][name]={'group':int(m[1]),'commands':int(m[2]),'checks':int(m[3]),'append_stalls':int(m[4]),'read_stalls':int(m[5]),'metrics':[{k:int(v) for k,v in x.items()} for x in rows]}
for probe in ['CorruptExpected','TimeoutProbe']:
    code=int(read_text(root/f'build/kv_{probe}.exit.txt').strip());assert code!=0
    summary[probe+'_exit']=code
summary['synthesis']={'completed':False,'resources':None,'note':'No successful KV synthesis evidence; see explicit attempt log if present'}
synth=root/'build/synth_kv_cache/synth.console.log'
if synth.exists():
    text=read_text(synth)
    summary['synthesis']['attempted']=True
    summary['synthesis']['errors']=re.findall(r'^ERROR:.*',text,re.M)
    if 'KV_SYNTHESIS_PASS' in text and not summary['synthesis']['errors']:
        inputs=json.loads(read_text(synth.parent/'source_inputs.json'))
        for path,expected in inputs['files'].items():
            assert hashlib.sha256((root/path).read_bytes()).hexdigest()==expected,f'stale synthesis: {path}'
        assert (synth.parent/'utilization.rpt').exists() and (synth.parent/'kv_cache.dcp').exists()
        summary['synthesis']={'attempted':True,'completed':True,'part':'xcvu9p-flga2104-2L-e','scope':'KV only, OOC synthesis, no placement/route','resources_report':'build/synth_kv_cache/utilization.rpt'}
(root/'build/kv_cache_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
print('KV_STORAGE_EVIDENCE_PASS configs=2 tensor_handoffs='+str(summary['tensor_handoff']['handoffs']))
