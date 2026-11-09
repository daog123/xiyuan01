from pathlib import Path
import json,re,struct,sys
root=Path(__file__).resolve().parents[2];out=root/'build/controlled_compute';out.mkdir(exist_ok=True)
source=root/'build/upstream_compute/sources';experiment=root/'experiments/controlled_compute';experiment.mkdir(parents=True,exist_ok=True)
common=json.loads((root/'build/compute_experiments/common_cases.json').read_text());cases=[]
for c in common:
 if c['m'] not in (1,8) or c['k'] not in (128,512):continue
 c=dict(c);c['n']=8;c['weights']=[row[:8] for row in c['weights']];c['sw']=[row[:8] for row in c['sw']]
 c['output']=[c['output'][r*64+n] for r in range(c['m']) for n in range(8)]
 c['psum']=[[group[:8] for group in row] for row in c['psum']];c['packed']=c['packed'][:8*((c['k']+1)//2)]
 cases.append(c)
cases.extend(c for c in common if c['m'] in (1,8) and c['k']==4096)
sys.path.insert(0,str(root/'model'));from w4a8_reference import reference
for c in list(cases[4:6]):
 d=dict(c);k=2048;ng=k//32;a=[row[:k] for row in c['a']];w=c['weights'][:k];sx=[[4096]*ng for _ in range(c['m'])];sw=[[4096]*c['n'] for _ in range(ng)]
 y,psum,_=reference(a,w,sx,sw,32);packed=[(w[q][n]&15)|((w[q+1][n]&15)<<4) for n in range(c['n']) for q in range(0,k,2)]
 d.update(k=k,groups=ng,a=a,weights=w,sx=sx,sw=sw,output=y,psum=psum,packed=packed);cases.append(d)
(out/'cases.json').write_text(json.dumps(cases)+'\n')
for half in [False,True]:
 selected=cases[:4]+[cases[6]] if half else cases
 tokens=[len(selected)]
 for i,c in enumerate(selected):
  tokens +=[15+i,c['m'],c['n'],c['k']]+[x for row in c['a'] for x in row]+[c['weights'][q][n] for n in range(c['n']) for q in range(c['k'])]
  tokens +=[struct.unpack('<H' if half else '<I',struct.pack('<e' if half else '<f',x/65536))[0] for x in c['output']]
 (out/('common_vectors_half.txt' if half else 'common_vectors.txt')).write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
# Source-controlled harness transformation; upstream arithmetic modules unchanged.
s=(root/'experiments/compute_upstream/tb_opentpu_core.sv').read_text()
s=s.replace('module tb_opentpu_core #(parameter integer IMPL=2);','module tb_opentpu_controlled;\n    localparam integer IMPL=2;')
s=s.replace('D=128,MCOLS=4','D=64,MCOLS=1').replace('for(integer fmt=0;fmt<3;fmt++)','for(integer fmt=1;fmt<2;fmt++)')
s=s.replace('count==9','count==8').replace('cases=27','cases=8').replace('if(fmt!=0 && m<=2)','if(fmt!=0 && 2*m<=MCOLS)')
s=s.replace('((k+255)/256)*128','((k+2*D-1)/(2*D))*D').replace('k/128','k/D')
s=s.replace('logic a_gnt=1,b_gnt=1,','logic a_gnt,b_gnt,')
s=s.replace('integer m,n,k,format_id,','integer credit=0,preload_cycles,command_started;bit feeding=0;integer act_mem[0:32767];\n    assign a_gnt=credit>=(dut.need_b?D:0)+4;assign b_gnt=a_gnt;\n    integer m,n,k,format_id,')
s=s.replace('b_rvalid<=0;a_rvalid<=0;','b_rvalid<=0;a_rvalid<=0;credit<=0;',1)
s=s.replace('b_rvalid<=b_req;a_rvalid<=a_req;', '''b_rvalid<=b_req;a_rvalid<=a_req;
            if(feeding) begin
                require(credit>=(b_req?D:0)+(a_req?4:0),"shared ingress budget never overspends");
                credit<=credit+8-(b_req?D:0)-(a_req?4:0)>4*D?4*D:credit+8-(b_req?D:0)-(a_req?4:0);
            end else credit<=0;''')
s=s.replace("format_id==2?32'h11113f00:32'h3f800000","format_id==2?32'h11113f00:32'h11113f80")
s=s.replace("a_rdata2<=32'h11113f00","a_rdata2<=32'h11113f80")
s=s.replace("8'(a[row*k+q])","8'(act_mem[row*k+q])")
s=s.replace("fmt==1?8'h11","fmt==1?8'h10") # Disable the unit-scale bypass.
s=s.replace('rst=1;start=0;go=0;checking=0;','rst=1;start=0;go=0;checking=0;feeding=0;')
s=s.replace('checking=1;start=1;started=ticks+1;', '''checking=1;started=ticks+1;
                // Same empty-cache boundary: preload INT8 ACT at 8 bytes/clock.
                for(integer offset=0;offset<m*k;offset+=8) begin
                    @(negedge clk);for(integer byte_index=0;byte_index<8;byte_index++) if(offset+byte_index<m*k)act_mem[offset+byte_index]=a[offset+byte_index];
                end
                // Native FP32 ACT-scale cache: same useful bytes as UQ4.12/group32.
                repeat((4*m*(k/D)+7)/8)@(negedge clk);
                command_started=ticks+1;preload_cycles=command_started-started;feeding=1;start=1;''')
s=s.replace('input_issue_cycles,weight_requests','input_issue_cycles,weight_requests,core_cycles,preload_cycles')
s=s.replace('%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",fmt,cid,m,n,k,ticks-started,macs,pops,requests','%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",fmt,cid,m,n,k,ticks-started,macs,pops,requests,ticks-command_started,preload_cycles')
s=s[:s.index('module tb_opentpu_tree;')]
(experiment/'tb_opentpu_controlled.sv').write_text(s,encoding='utf-8')
# 64 lanes: keep the two original 32-lane banks. Original FP32 reduction remains
# four-input; its two unused operands are exact zero with matching valid/last.
original=(root/'build/upstream_compute/llama_core/MulAddSGNew_extracted.v').read_text()
wrapper=re.search(r'^module MulAddSGNew\b.*?^endmodule',original,re.M|re.S)[0].replace('module MulAddSGNew (','module MulAddSGNew64 (')
wrapper=wrapper.replace('[2047:0] wkvIn_tdata','[1023:0] wkvIn_tdata').replace('[2047:0] dotIn_tdata','[1023:0] dotIn_tdata').replace('[2047:0] resAdd_tdata','[1023:0] resAdd_tdata').replace('[2047:0] vecOut_tdata','[1023:0] vecOut_tdata')
for bank in [2,3]:
 wrapper,n=re.subn(r'  MulAddEngineNew banks_'+str(bank)+r' \(.*?\n  \);','',wrapper,flags=re.S);assert n==1
 for suffix,value in [('scalarOut_tvalid','banks_0_scalarOut_tvalid'),('scalarOut_tlast','banks_0_scalarOut_tlast'),('scalarOut_tdata',"16'd0"),('scalarOut_tuser','banks_0_scalarOut_tuser'),('vecOut_tdata',"512'd0")]:wrapper+=f'\nassign banks_{bank}_{suffix}={value};'
 for stem in ['wkvIn','dotIn','resAdd']:
  wrapper=re.sub(r'assign '+stem+'Split_'+str(bank)+r' = .*?;',f"assign {stem}Split_{bank} = 512'd0;",wrapper)
wrapper=wrapper.replace('\nendmodule','')+'\nendmodule\n'
(out/'llama_core64.v').write_text(original+'\n'+wrapper,encoding='utf-8')
s=(root/'experiments/compute_upstream/tb_llama_core.sv').read_text().replace('module tb_llama_core;','module tb_llama_controlled #(parameter integer WB_INTERVAL=16,AB_INTERVAL=16);')
s=s.replace('[2047:0]','[1023:0]').replace('128','64').replace('MulAddSGNew dut','MulAddSGNew64 dut').replace('count==9','count==5').replace('cases=9','cases=5')
s=s.replace('@(negedge clk_0_clk);dotIn_tvalid=1;', '@(negedge clk_0_clk);dotIn_tvalid=0;repeat(AB_INTERVAL-1)@(negedge clk_0_clk);dotIn_tvalid=1;')
s=s.replace('@(negedge clk_0_clk);wkvIn_tvalid=1;', '@(negedge clk_0_clk);wkvIn_tvalid=0;repeat(WB_INTERVAL-1)@(negedge clk_0_clk);wkvIn_tvalid=1;')
s=s.replace('fork send_activation(row);send_weights();join','send_activation(row);send_weights();')
s+='\nmodule tb_llama_controlled_bytes;tb_llama_controlled #(.WB_INTERVAL(16),.AB_INTERVAL(16)) test();endmodule\nmodule tb_llama_controlled_elements;tb_llama_controlled #(.WB_INTERVAL(4),.AB_INTERVAL(8)) test();endmodule\n'
s=s.replace('"common_vectors_half.txt"','"'+(out/'common_vectors_half.txt').as_posix()+'"')
(experiment/'tb_llama_controlled.sv').write_text(s,encoding='utf-8')
print('CONTROLLED_INPUTS_PREPARED open_cases=8 llama_cases=5 max_llama_K=2048')
