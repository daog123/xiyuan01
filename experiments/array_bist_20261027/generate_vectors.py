"""Fixed, independently computed signed INT8 x INT4 array BIST cases."""
from pathlib import Path
import hashlib,json,random
ROOT=Path(__file__).parent
specs=[(4,4,32,'random'),(4,4,31,'limits'),(3,2,17,'random'),(1,4,1,'limits'),
       (2,3,8,'zero'),(4,4,16,'ramp'),(4,4,32,'limits'),(4,4,37,'random')]
rng=random.Random(20261027);aa=[];bb=[];gg=[];cases=[];checksum=0
for cid,(m,n,k,kind) in enumerate(specs):
    a=[[0]*64 for _ in range(4)];b=[[0]*4 for _ in range(64)]
    for r in range(m):
        for q in range(k):
            a[r][q]=0 if kind=='zero' else [-128,127,-1,0][(r+q+cid)%4] if kind=='limits' else ((r*19+q*7)%256)-128 if kind=='ramp' else rng.randrange(-128,128)
    for q in range(k):
        for c in range(n):
            b[q][c]=0 if kind=='zero' else [-8,7,-1,0][(q+c+cid)%4] if kind=='limits' else ((c*3+q)%16)-8 if kind=='ramp' else rng.randrange(-8,8)
    golden=[sum(a[r][q]*b[q][c] for q in range(k)) if r<m and c<n else 0 for r in range(4) for c in range(4)]
    aa.extend(a[r][q]&255 for r in range(4) for q in range(64))
    bb.extend(b[q][c]&255 for c in range(4) for q in range(64))
    gg.extend(v&0xffffffff for v in golden)
    for slot,v in enumerate(golden):
        checksum=(((checksum<<1)|(checksum>>15)) ^ (v&65535) ^ ((v&0xffffffff)>>16) ^ (cid*16+slot))&65535
    cases.append(dict(id=cid,m=m,n=n,k=k,kind=kind,a=[r[:k] for r in a],b=b[:k],golden=golden))
for name,data,width in [('a.hex',aa,2),('b.hex',bb,2),('golden.hex',gg,8)]:
    (ROOT/name).write_text(''.join(('%0*x\n'%(width,v)) for v in data),encoding='ascii')
def fn(name,index,default):
    return 'function automatic [15:0] '+name+'(input logic [2:0] cid);\ncase(cid)\n'+''.join("3'd%d: %s=16'd%d;\n"%(i,name,s[index]) for i,s in enumerate(specs))+'default: '+name+'='+str(default)+';\nendcase\nendfunction\n'
(ROOT/'shapes.svh').write_text(fn('rows_for',0,0)+fn('cols_for',1,0)+fn('k_for',2,0),encoding='ascii')
manifest=dict(seed=20261027,rows=4,cols=4,cases=cases,compared_outputs=128,
              actual_checksum16=checksum,valid_macs=sum(m*n*k for m,n,k,_ in specs),
              core='current w4a8_compute_array, vector_mode=0, scalar INT8 x sign-extended INT4')
(ROOT/'vectors.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('ARRAY_VECTORS_READY cases=8 outputs=128 checksum=%04x'%checksum)
