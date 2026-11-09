"""Audit current source identities and retain all three evidence layers separately."""
from pathlib import Path
import hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
def main():
    project.audit(ROOT/'build/project_v2')
    def verify(hashes):
        for name,digest in hashes.items():
            assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'stale round6 evidence: '+name
    protocol=json.loads((ROOT/'build/round6_protocol/result.json').read_text())
    perf=json.loads((ROOT/'build/round6_performance/result.json').read_text())
    assert protocol['status']==perf['status']=='PASS'
    for rec in protocol['simulations']:verify(rec['source_sha256'])
    for rec in perf['variants']:verify(rec['source_sha256'])
    baseline=json.loads((ROOT/'build/round6_baseline/manifest.json').read_text())
    for name in ['rtl/w4a8_wave.sv','rtl/llm_graph_top.sv','rtl/ffn_dma.sv','rtl/attention_q_dma.sv']:
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==baseline['source_sha256'][name],name
    large=[r for r in perf['comparison'] if r['top']=='tb_round6_linear']
    assert len(large)==8 and all(r['new_bursts']>0 for r in large)
    assert len(perf['comparison'])==32 and len(protocol['simulations'])==11
    coverage={}
    for top in ['tb_w4a8_memory_burst','tb_w4a8_memory_burst8']:
        log=(ROOT/'build/round6_protocol'/top/'run.log').read_text(encoding='utf-8')
        match=re.search(r'STORAGE_BURST_COVERAGE bursts=(\d+) required=1',log);assert match,top
        coverage[top]=int(match[1]);assert coverage[top]>0,top
    summary=dict(status='PASS',source_sha256=project.identity([ROOT/'scripts/audit_round6.py']),
        unchanged_compute_sha256=baseline['source_sha256']['rtl/w4a8_wave.sv'],
        protocol_configurations=len(protocol['simulations']),operator_pairs=len(perf['comparison']),
        exact_byte_oracle_burst_coverage=coverage,
        operator_full_image_jobs=2*len(perf['comparison']),
        operator_bytes_compared=2*sum(r['memory_bytes_compared'] for r in perf['comparison']),
        small_speedup_range=[min(r['speedup'] for r in perf['comparison'] if r not in large),max(r['speedup'] for r in perf['comparison'] if r not in large)],
        large_speedup_range=[min(r['speedup'] for r in large),max(r['speedup'] for r in large)],
        prior_compute_measurements='Retained fifth-round evidence; unchanged compute RTL, no new core-cycle claim',
        physical=json.loads((ROOT/'build/project_v2/implementation_result.json').read_text()))
    out=ROOT/'build/round6_evidence.json';out.write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print('ROUND6_CURRENT_SOURCE_EVIDENCE_PASS',json.dumps({k:v for k,v in summary.items() if k not in ['physical','source_sha256']},ensure_ascii=False),flush=True)
if __name__=='__main__':main()
