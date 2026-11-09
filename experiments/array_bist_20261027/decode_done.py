"""Decode timestamped DONE samples; a static DONE=1 is never a pass."""
import argparse,bisect,csv,json,statistics
from pathlib import Path
def crc8(value):
    crc=0
    for i in range(55,-1,-1):
        feedback=((crc>>7)^ (value>>i))&1
        crc=((crc<<1)&255)^(7 if feedback else 0)
    return crc
def decode(samples):
    edges=[]
    for i in range(1,len(samples)):
        if samples[i][1]!=samples[i-1][1]:edges.append((samples[i][0],samples[i-1][1],samples[i][1]))
    if len(edges)<20:return []
    durations=[edges[i+1][0]-edges[i][0] for i in range(len(edges)-1)]
    base=statistics.median(durations);times=[e[0] for e in edges];frames=[]
    for i in range(len(edges)-1):
        start,before,after=edges[i];stop=edges[i+1][0]
        if before!=1 or after!=0 or stop-start<2.5*base:continue
        unit=(stop-start)/6;predicted=start+9*unit;value=0;previous=None;valid=True
        for bit in range(64):
            pos=bisect.bisect_left(times,predicted)
            candidates=[n for n in (pos-1,pos) if 0<=n<len(edges)]
            if not candidates:valid=False;break
            n=min(candidates,key=lambda n:abs(times[n]-predicted));edge=edges[n]
            if abs(edge[0]-predicted)>0.4*unit:valid=False;break
            value=(value<<1)|(1 if edge[1:]==(1,0) else 0)
            if previous is not None:unit=0.9*unit+0.1*((edge[0]-previous)/2)
            previous=edge[0];predicted=edge[0]+2*unit
        if not valid or value>>48!=0xc64a or (value>>44)&15!=1 or crc8(value>>8)!=(value&255):continue
        frames.append(dict(start=start,unit=unit,word='%016x'%value,status=(value>>40)&15,
            cases=(value>>32)&255,checksum=(value>>16)&65535,errors=(value>>8)&255))
    return frames
def main():
    p=argparse.ArgumentParser();p.add_argument('csv',type=Path);p.add_argument('--expected-status',type=int);p.add_argument('--checksum',type=lambda s:int(s,0));args=p.parse_args()
    rows=[]
    for row in csv.reader(args.csv.read_text().splitlines()):
        if row and not row[0].startswith('#'):rows.append((float(row[0]),int(row[1],0)&1))
    frames=decode(rows);print(json.dumps(frames,indent=2))
    if args.expected_status is not None:
        good=[f for f in frames if f['status']==args.expected_status and (args.checksum is None or f['checksum']==args.checksum)]
        assert len(good)>=2,'fewer than two CRC-valid expected frames'
        print('DONE_TELEMETRY_DECODE_PASS frames=%d'%len(good))
if __name__=='__main__':main()
