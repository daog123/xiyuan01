"""Independent LINEAR -> dynamic INT8 Q -> integer attention test vectors."""
from pathlib import Path
import argparse,json,math,random,sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'vector'))
from dynamic_reference import dynamic
from w4a8_reference import reference
from attention_reference import attention

def generate(out):
 out.mkdir(parents=True,exist_ok=True);summary=[]
 for g in [32,3,1]:
  for cid,(d,k,kind) in enumerate([(9,13,'random'),(64,5,'clipped'),(1,1,'zero')]):
   rng=random.Random(3100+g*10+cid);t=3;gk=(k+g-1)//g;gd=(d+g-1)//g
   a=[[rng.randint(-12,12) for _ in range(k)]];w=[[rng.randint(-8,7) for _ in range(d)] for _ in range(k)]
   sx=[[4096]*gk];sw=[[rng.choice([1200,4096,8000]) for _ in range(d)] for _ in range(gk)]
   if kind=='zero':a=[[0]*k]
   if kind=='clipped':a=[[127]*k];w=[[7 if n%2 else -8 for n in range(d)] for _ in range(k)];sx=[[65535]*gk];sw=[[65535]*d for _ in range(gk)]
   q16,_,_=reference(a,w,sx,sw,g);q=[];qs=[]
   for j in range(gd):
    quant=dynamic(q16[j*g:min(d,(j+1)*g)]);q+=quant['q'];qs.append(quant['scale'])
   keys=[[rng.randint(-8,8) for _ in range(d)] for _ in range(t)]
   vals=[[rng.randint(-15,15) for _ in range(d)] for _ in range(t)]
   ks=[[rng.choice([500,1200,4096]) for _ in range(gd)] for _ in range(t)]
   vs=[[rng.choice([600,1700,4096]) for _ in range(gd)] for _ in range(t)]
   gain=round(4096/math.sqrt(d));y,stats=attention(q,qs,keys,ks,vals,vs,g,gain)
   image=bytearray([0xcd]*65536);rd=bytearray(65536);wr=bytearray(65536)
   def put(base,data,read=True,write=False):
    image[base:base+len(data)]=bytes(data)
    if read:rd[base:base+len(data)]=b'\x01'*len(data)
    if write:wr[base:base+len(data)]=b'\x01'*len(data)
   def word(v,n):return (v&((1<<(8*n))-1)).to_bytes(n,'little')
   abase,wbase,sxbase,swbase,qbase,ybase=4093,10001,16000,18000,26000,30000
   wstride=(k+1)//2+3
   put(abase,bytes(x&255 for x in a[0]));put(sxbase,b''.join(word(x,2) for x in sx[0]))
   for n in range(d):put(wbase+n*wstride,bytes((w[j][n]&15)|((w[j+1][n]&15)<<4 if j+1<k else 0) for j in range(0,k,2)))
   for j in range(gk):put(swbase+j*2*d,b''.join(word(x,2) for x in sw[j]))
   put(qbase,b''.join(word(x,4) for x in q16),write=True)
   wr[ybase:ybase+4*d]=b'\x01'*(4*d)
   bases=[34001,38001,42000,46000];strides=[d+3,d+5,2*gd+4,2*gd+6];sizes=[3*s+(d if p<2 else 2*gd) for p,s in enumerate(strides)]
   append=[];expected=bytearray(image)
   for token in range(t):
    planes=[bytes(x&255 for x in keys[token]),bytes(x&255 for x in vals[token]),b''.join(word(x,2) for x in ks[token]),b''.join(word(x,2) for x in vs[token])]
    for p,raw in enumerate(planes):
     start=bases[p]+token*strides[p];rd[start:start+len(raw)]=b'\x01'*len(raw);wr[start:start+len(raw)]=b'\x01'*len(raw)
     expected[start:start+len(raw)]=raw;append+=raw
   expected[ybase:ybase+4*d]=b''.join(word(x,4) for x in y)
   task=[1100+cid,1,d,k,abase,wbase,sxbase,swbase,qbase,k,wstride,2*gk,2*d,4*d,k,(d-1)*wstride+(k+1)//2,2*gk,gk*2*d,4*d]
   tokens=[d,k,t,gain,len(append)]+task+bases+strides+sizes+q+[qs[i//g] for i in range(d)]+append
   stem=out/f'g{g}_c{cid}';stem.with_suffix('.txt').write_text('\n'.join(map(str,tokens))+'\n',encoding='ascii')
   for suffix,data in [('input',image),('expected',expected),('read',rd),('write',wr)]:
    (out/f'g{g}_c{cid}.{suffix}.hex').write_text(''.join(f'{v:02x}\n' for v in data),encoding='ascii')
   summary.append(dict(group=g,case=cid,dimension=d,k=k,kind=kind,q16=q16,q=q,scales=qs,attention=y))
 (out/'manifest.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
 print('PROJECTION_REFERENCE_PASS cases='+str(len(summary)))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);generate(p.parse_args().out)
