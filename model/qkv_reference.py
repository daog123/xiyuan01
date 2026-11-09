"""Integer Q/K/V projections, full-group quantization, committed per-head KV."""
from pathlib import Path
import argparse,json,math,random,sys
sys.path.insert(0,str(Path(__file__).resolve().parent/'vector'))
from dynamic_reference import dynamic
from w4a8_reference import reference
from attention_reference import attention
def generate(out):
 out.mkdir(parents=True,exist_ok=True);manifest=[]
 for g in [32,3,1]:
  for cid,(d,k,kind) in enumerate([(9,13,'random'),(64,5,'clipped'),(1,1,'zero')]):
   ng=(k+g-1)//g;gd=(d+g-1)//g;gain=round(4096/math.sqrt(d));image=bytearray([0xcd]*65536)
   bases=[34001,38001,42000,46000];strides=[d+3,d+5,2*gd+4,2*gd+6];hs=[4*x+16 for x in strides]
   sizes=[hs[p]+3*strides[p]+(d if p<2 else 2*gd)for p in range(4)]
   rd=bytearray(65536);wr=bytearray(65536);cache=[[],[]]
   for p in range(4):
    for h in range(2):
     for t in range(4):
      x=bases[p]+h*hs[p]+t*strides[p];width=d if p<2 else 2*gd;rd[x:x+width]=b'\x01'*width;wr[x:x+width]=b'\x01'*width
   def word(v,n):return (v&((1<<(8*n))-1)).to_bytes(n,'little')
   for step,(head,token)in enumerate([(0,0),(0,1),(1,0)]):
    rng=random.Random(41000+g*100+cid*10+step);a=[[rng.randint(-12,12)for _ in range(k)]]
    if kind=='zero':a=[[0]*k]
    if kind=='clipped':a=[[127]*k]
    tasks=[];values=[];quant=[]
    def put(addr,data):
     image[addr:addr+len(data)]=bytes(data);rd[addr:addr+len(data)]=b'\x01'*len(data)
    put(4093,bytes(x&255 for x in a[0]));wstride=(k+1)//2+3;swstride=2*d+4
    for branch in range(3):
     w=[[rng.randint(-8,7)for _ in range(d)]for _ in range(k)];sx=[[rng.choice([2000,4096,7000])for _ in range(ng)]];sw=[[rng.choice([1000,4096,8000])for _ in range(d)]for _ in range(ng)]
     if kind=='clipped':w=[[7 if (c+branch)%2 else -8 for c in range(d)]for _ in range(k)];sx=[[65535]*ng];sw=[[65535]*d for _ in range(ng)]
     y,_,_=reference(a,w,sx,sw,g);values.append(y);q=[];s=[]
     for j in range(gd):
      v=dynamic(y[j*g:min(d,(j+1)*g)]);q+=v['q'];s.append(v['scale'])
     quant.append((q,s));wb=10001+branch*2000;sb=16000+branch*1000;swb=19000+branch*2000;yb=26000+branch*1000
     for c in range(d):put(wb+c*wstride,bytes((w[z][c]&15)|((w[z+1][c]&15)<<4 if z+1<k else 0)for z in range(0,k,2)))
     put(sb,b''.join(word(x,2)for x in sx[0]))
     for j in range(ng):put(swb+j*swstride,b''.join(word(x,2)for x in sw[j]))
     rd[yb:yb+4*d]=b'\x01'*(4*d);wr[yb:yb+4*d]=b'\x01'*(4*d)
     tasks.append([1000+cid*100+step*10+branch,1,d,k,4093,wb,sb,swb,yb,k+3,wstride,2*ng+2,swstride,4*d+4,k,(d-1)*wstride+(k+1)//2,2*ng,(ng-1)*swstride+2*d,4*d])
    before=bytearray(image);cache[head].append((quant[1],quant[2]));assert len(cache[head])==token+1
    keys=[x[0][0]for x in cache[head]];ks=[x[0][1]for x in cache[head]];vals=[x[1][0]for x in cache[head]];vs=[x[1][1]for x in cache[head]]
    y,_=attention(quant[0][0],quant[0][1],keys,ks,vals,vs,g,gain)
    for branch in range(3):image[26000+branch*1000:26000+branch*1000+4*d]=b''.join(word(v,4)for v in values[branch])
    for p,raw in enumerate([bytes(v&255 for v in quant[1][0]),bytes(v&255 for v in quant[2][0]),b''.join(word(v,2)for v in quant[1][1]),b''.join(word(v,2)for v in quant[2][1])]):
     addr=bases[p]+head*hs[p]+token*strides[p];image[addr:addr+len(raw)]=raw
    image[30000:30000+4*d]=b''.join(word(v,4)for v in y);wr[30000:30000+4*d]=b'\x01'*(4*d)
    tokens=[d,k,head,token,gain,5000+cid*100+step*10]+[v for t in tasks for v in t]+bases+strides+hs+sizes
    tokens +=[v for q,s in quant for v in q]+[s[i//g]for q,s in quant for i in range(d)]
    stem=f'g{g}_c{cid}_s{step}';(out/(stem+'.txt')).write_text('\n'.join(map(str,tokens))+'\n')
    for suffix,data in [('input',before),('expected',image),('read',rd),('write',wr)]:
     (out/(stem+'.'+suffix+'.hex')).write_text(''.join(f'{v:02x}\n'for v in data),encoding='ascii')
    manifest.append(dict(group=g,case=cid,step=step,dimension=d,k=k,head=head,token=token,kind=kind,q16=values,quant=quant,attention=y))
 (out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
 print('QKV_REFERENCE_PASS steps='+str(len(manifest)))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);generate(p.parse_args().out)
