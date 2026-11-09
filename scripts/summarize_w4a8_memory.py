"""Audit actual self-check logs/CSV against current source hashes; no cached PASS."""
import csv
import hashlib
import json
import re
from pathlib import Path
from read_text_log import read_text

root=Path(__file__).resolve().parents[1]
configs=['tb_w4a8_memory','tb_w4a8_memory8','tb_w4a8_memory_alt','tb_w4a8_memory_unit']
summary={'configs':{},'synthesis':{'executed':False},'board_executed':False}
for config in configs:
    work=root/'build'/config
    if not (work/'PASS.txt').exists():
        continue
    inputs=json.loads(read_text(work/'source_inputs.json'))
    for path,expected in inputs['files'].items():
        assert hashlib.sha256((root/path).read_bytes()).hexdigest()==expected, f'stale evidence: {path}'
    log=read_text(work/'run.log')
    assert 'W4A8_MEMORY_TESTS_PASS' in log and not re.search(r'Fatal:|FAILED|TIMEOUT|^ERROR:',log,re.M)
    rows=list(csv.DictReader((work/'memory_results.csv').open()))
    assert len(rows)==(12 if config=='tb_w4a8_memory_unit' else 11), f'{config}: missing successful recovery jobs'
    summary['configs'][config]={'pass':True,'successful_jobs':len(rows),'metrics':[{k:int(v) for k,v in r.items()} for r in rows]}
assert summary['configs'], 'No current RTL self-check evidence'
synth=root/'build/synth_w4a8_memory/synth.console.log'
if synth.exists():
    log=read_text(synth)
    if 'W4A8_MEMORY_SYNTHESIS_PASS' in log and not re.search(r'^ERROR:',log,re.M):
        inputs=json.loads(read_text(synth.parent/'source_inputs.json'))
        for path,expected in inputs['files'].items():
            assert hashlib.sha256((root/path).read_bytes()).hexdigest()==expected, f'stale synthesis: {path}'
        summary['synthesis']={'executed':True,'completed':True,'scope':'storage only, OOC synthesis; no placement/route','part':'xcvu9p-flga2104-2L-e'}
    else:
        summary['synthesis']={'executed':True,'completed':False,'errors':re.findall(r'^ERROR:.*',log,re.M),'resources':None}
negative=root/'build/memory_negative_exit.txt'
if negative.exists():
    summary['negative_exit']=int(read_text(negative).strip());assert summary['negative_exit']!=0
timeout=root/'build/memory_timeout_exit.txt'
if timeout.exists():
    summary['timeout_exit']=int(read_text(timeout).strip());assert summary['timeout_exit']!=0
(root/'build/w4a8_memory_summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf8')
print('W4A8_MEMORY_EVIDENCE_PASS configs='+str(len(summary['configs'])))
