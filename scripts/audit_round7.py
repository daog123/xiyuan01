"""Current-source numerical, protocol, ablation and physical evidence audit."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'scripts'));import project
def verify(hashes):
 for name,digest in hashes.items():
  assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'stale round7 evidence: '+name
def functional():
 protocol=json.loads((ROOT/'build/round7_protocol/result.json').read_text())
 perf=json.loads((ROOT/'build/round7_performance/result.json').read_text())
 assert protocol['status']==perf['status']=='PASS'
 assert len(protocol['simulations'])==17 and len(perf['comparison'])==32
 assert perf['disabled_cache_pairs']==32 and len(perf['ablations'])==16
 for rec in protocol['simulations']:verify(rec['source_sha256'])
 for rec in perf['variants']:verify(rec['source_sha256'])
 negative=next(r for r in protocol['simulations'] if r['top']=='tb_w4a8_memory_burst')['negative_probes']
 assert {r['probe'] for r in negative}=={'corrupt_weight_cache','corrupt_sx_cache'} and all(r['expected_failure'] for r in negative)
 baseline=json.loads((ROOT/'build/round7_baseline/manifest.json').read_text())
 for name,digest in baseline['source_sha256'].items():
  assert hashlib.sha256((ROOT/'build/round7_baseline/source'/name).read_bytes()).hexdigest()==digest,'baseline changed: '+name
 for name in ['rtl/w4a8_wave.sv','rtl/llm_graph_top.sv','rtl/ffn_dma.sv','rtl/attention_q_dma.sv','rtl/w4a8_axi_read.sv']:
  assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==baseline['source_sha256'][name],name
 large=[r for r in perf['comparison'] if r['top']=='tb_round7_linear']
 small=[r for r in perf['comparison'] if r['top']!='tb_round7_linear']
 summary=dict(protocol_configurations=17,operator_pairs=32,disabled_cache_equivalence_pairs=32,ablation_jobs=16,
  full_image_jobs=112,paired_full_image_bytes=2*sum(r['memory_bytes_compared'] for r in perf['comparison']),
  all_full_image_bytes=3*sum(r['memory_bytes_compared'] for r in perf['comparison'])+16*262144,
  protected_compute_sha256=baseline['source_sha256']['rtl/w4a8_wave.sv'],
  long_speedup_range=[min(r['speedup'] for r in large),max(r['speedup'] for r in large)],
  small_linear_speedup_range=[min(r['speedup'] for r in small if r['operator']=='LINEAR'),max(r['speedup'] for r in small if r['operator']=='LINEAR')],
  small_ffn_speedup_range=[min(r['speedup'] for r in small if r['operator']=='FFN'),max(r['speedup'] for r in small if r['operator']=='FFN')],
  negative_probes=negative)
 print('ROUND7_FUNCTIONAL_SOURCE_EVIDENCE_PASS',json.dumps(summary,ensure_ascii=False),flush=True)
 return summary
def main():
 project.audit(ROOT/'build/project_v2')
 result=functional();result.update(status='PASS',source_sha256=project.identity([ROOT/'scripts/audit_round7.py']),
  physical=json.loads((ROOT/'build/project_v2/implementation_result.json').read_text()))
 assert result['physical']['status']=='PASS'
 (ROOT/'build/round7_evidence.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 print('ROUND7_CURRENT_SOURCE_EVIDENCE_PASS',flush=True)
if __name__=='__main__':main()
