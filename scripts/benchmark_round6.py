"""Frozen fifth-round supply vs bounded burst, identical MAC and memory service."""
from pathlib import Path
import csv,hashlib,json,os,random,re,sys
ROOT=Path(__file__).resolve().parents[1];sys.path[:0]=[str(ROOT/'scripts'),str(ROOT/'model')]
import project
from w4a8_reference import make_case
TOOLS=Path(os.environ.get('VIVADO_BIN','E:/AMDDesignTools/2025.2/Vivado/bin'))
OUT=ROOT/'build/round6_performance';OUT.mkdir(parents=True,exist_ok=True)
result=dict(status='RUNNING',kind='RTL simulation; bounded single-outstanding AXI service, no board/model throughput',variants=[],comparison=[])
def save():(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
def large_vectors(out):
    out.mkdir(parents=True,exist_ok=True);records=[]
    for k in [512,4096]:
        for m in [1,2,4,8]:
            cid=len(records);n=64;group=32;ng=k//group
            c=make_case(random.Random(2026102600+cid),f'large{cid}',m,n,k,group,'float')
            image=bytearray([0xcd]*262144);rp=bytearray(len(image));wp=bytearray(len(image))
            aa,ww,sx,sw,yy=4096,65536,204800,210000,245760
            astr,wstr,sxstr,swstr,ystr=k,k//2,ng*2,n*2,n*4
            def put(buf,base,stride,rows,width,vals,permissions,unit=1):
                it=iter(vals)
                for r in range(rows):
                    for j in range(width):
                        a=base+r*stride+j*unit;buf[a:a+unit]=(next(it)&((1<<(unit*8))-1)).to_bytes(unit,'little');permissions[a:a+unit]=b'\x01'*unit
            flat=lambda a:[x for row in a for x in row]
            put(image,aa,astr,m,k,flat(c['a']),rp);put(image,ww,wstr,n,k//2,c['packed'],rp)
            put(image,sx,sxstr,m,ng,flat(c['sx']),rp,2);put(image,sw,swstr,ng,n,flat(c['sw']),rp,2)
            expected=image.copy();put(expected,yy,ystr,m,n,c['output'],wp,4)
            tokens=[1600+cid,m,n,k,aa,ww,sx,sw,yy,astr,wstr,sxstr,swstr,ystr,m*astr,n*wstr,m*sxstr,ng*swstr,m*ystr]
            (out/f'large{cid}.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
            for suffix,buf in [('input',image),('expected',expected),('read',rp),('write',wp)]:
                (out/f'large{cid}.{suffix}.hex').write_text(''.join(f'{b:02x}\n' for b in buf),encoding='ascii')
            records.append(dict(case=cid,M=m,N=n,K=k,group=group))
    (out/'manifest.json').write_text(json.dumps(records,indent=2)+'\n',encoding='utf-8')
    return records
def main():
    save();vec=OUT/'vectors'
    project.run([sys.executable,ROOT/'model/system_vectors.py','--out',vec],ROOT,OUT/'reference.log')
    shapes=json.loads((vec/'manifest.json').read_text());large=large_vectors(OUT/'large_vectors')
    src=[ROOT/'rtl'/(n+'.sv') for n in project.MANIFEST.read_text(encoding='utf-8-sig').splitlines()]
    bench=[ROOT/'tb/llm_test_shells.sv',ROOT/'tb/system_axi_memory.sv',ROOT/'tb/tb_accelerator.sv',ROOT/'tb/tb_round6_linear.sv']
    changed={'w4a8_axi_read','w4a8_memory_packet','w4a8_memory_bridge'};all_rows=[]
    frozen=ROOT/'build/round6_baseline/source';frozen_hash=json.loads((frozen.parent/'manifest.json').read_text())['source_sha256']
    for variant in ['before','after']:
        work=OUT/variant;work.mkdir(exist_ok=True)
        for folder in [vec,OUT/'large_vectors']:
            for p in folder.glob('*'):
                if p.name!='manifest.json':(work/p.name).write_bytes(p.read_bytes())
        selected=[frozen/'rtl'/p.name if variant=='before' and p.stem in changed else p for p in src]
        for p in selected:
            if frozen in p.parents:assert hashlib.sha256(p.read_bytes()).hexdigest()==frozen_hash[p.relative_to(frozen).as_posix()]
        inputs=project.identity(selected+bench+[Path(__file__),project.PROFILE,ROOT/'model/w4a8_reference.py',ROOT/'model/system_vectors.py']+list(vec.glob('*'))+list((OUT/'large_vectors').glob('*')))
        project.run([TOOLS/'xvlog.bat','--sv',*selected,*bench],work,work/'compile.log')
        rec=dict(name=variant,source_sha256=inputs,simulations=[])
        for top in ['tb_perf_r0','tb_perf_r8','tb_perf_r24','tb_perf_g12','tb_round6_linear']:
            project.run([TOOLS/'xelab.bat',top,'-s',top,'-timescale','1ns/1ps'],work,work/(top+'.elaborate.log'))
            tcl=ROOT/'scripts'/('run_w4a8_memory_xsim.tcl' if top=='tb_round6_linear' else 'run_xsim.tcl')
            cmd=[TOOLS/'xsim.bat',top,'-tclbatch',tcl.as_posix()]
            log=project.run(cmd,work,work/(top+'.run.log'));marker='ROUND6_LARGE_PASS' if top=='tb_round6_linear' else 'PERFORMANCE_TESTS_PASS'
            assert project.valid_log(log,marker),top
            rows=[dict(re.findall(r'(\w+)=(-?\d+)',s)) for s in re.findall(r'(?:PERF_RECORD|LARGE_RECORD) ([^\r\n]+)',log)]
            assert len(rows)==(8 if top=='tb_round6_linear' else 6)
            all_rows +=[dict(variant=variant,top=top,**{k:int(v) for k,v in r.items()}) for r in rows]
            rec['simulations'].append(dict(top=top,result=next(x for x in log.splitlines() if x.startswith(marker))))
            if variant=='after' and top=='tb_round6_linear':
                bad=project.run(cmd+['-testplusarg','corrupt_expected'],work,work/'large_corrupt.log',allow_failure=True)
                assert 'ROUND6_LINEAR_CHECK_FAILED full image' in bad and not project.valid_log(bad,marker)
                rec['corrupt_expected_probe']='expected failure'
            print(variant,top,'PASS',flush=True)
        result['variants'].append(rec);save()
    for old in [r for r in all_rows if r['variant']=='before']:
        new=next(r for r in all_rows if r['variant']=='after' and (r['top'],r.get('opcode',0),r['case'])==(old['top'],old.get('opcode',0),old['case']))
        for key in ['read_payload','read_beats','writes','acks','bytes']:assert new[key]==old[key],(key,old,new)
        assert new['reads']<=old['reads'] and new['acks']==new['writes']
        if old['top']=='tb_round6_linear':shape=large[old['case']];m,n,k,group=(shape[x] for x in ['M','N','K','group']);macs=m*n*k;operator='LINEAR';delay=8
        else:
            shape=next(s for s in shapes if (s['group'],s['case'])==(new['group'],new['case']))
            m,k,h,n=(shape[x] for x in ['m','k','h','n']);group=new['group'];operator='LINEAR' if new['opcode']==0 else 'FFN';delay=new['read_delay']
            macs=m*k*h if new['opcode']==0 else 2*m*k*h+m*h*n
            if operator=='LINEAR':n=h
        row=dict(top=new['top'],operator=operator,case=new['case'],group=group,M=m,N=n,K=k,read_delay=delay,
            old_cycles=old['cycles'],new_cycles=new['cycles'],speedup=old['cycles']/new['cycles'],
            old_read_transactions=old['reads'],new_read_transactions=new['reads'],new_bursts=new['burst_reads'],
            read_beats=new['read_beats'],read_payload_bytes=new['read_payload'],writes=new['writes'],acks=new['acks'],
            useful_matrix_MACs=macs,old_effective_MAC_per_clock=macs/old['cycles'],new_effective_MAC_per_clock=macs/new['cycles'],memory_bytes_compared=new['bytes'],
            old_wait_r=old.get('wait_r'),new_wait_r=new.get('wait_r'))
        result['comparison'].append(row)
    assert len(result['comparison'])==32
    with (OUT/'comparison.csv').open('w',encoding='utf-8-sig',newline='')as f:
        writer=csv.DictWriter(f,fieldnames=list(result['comparison'][0]));writer.writeheader();writer.writerows(result['comparison'])
    assert any(r['new_read_transactions']<r['old_read_transactions'] for r in result['comparison'])
    result['status']='PASS';save();print('ROUND6_PERFORMANCE_PASS pairs=32 full_image_jobs=64',flush=True)
if __name__=='__main__':main()
