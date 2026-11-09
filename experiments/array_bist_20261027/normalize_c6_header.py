"""Normalize only .bit metadata to the working C6 128-byte payload offset.

The configuration packet payload must remain byte-for-byte identical.
"""
from pathlib import Path
import argparse,hashlib,json,struct
def parse(data):
    n=struct.unpack_from('>H',data,0)[0];p=2+n
    key_length=struct.unpack_from('>H',data,p)[0];assert key_length==1;p+=2
    prefix=data[:p];fields=[]
    for expected in b'abcd':
        key=data[p];assert key==expected;p+=1
        length=struct.unpack_from('>H',data,p)[0];p+=2
        fields.append(data[p:p+length]);p+=length
    assert data[p]==ord('e');p+=1
    length=struct.unpack_from('>I',data,p)[0];p+=4
    assert p+length==len(data)
    return prefix,fields,data[p:],p
def normalize(source,destination):
    data=source.read_bytes();prefix,fields,payload,old_offset=parse(data)
    text=fields[0].rstrip(b'\0').split(b';SW_CRC=')[0]
    fields[0]=text+b'\0'
    def header():return prefix+b''.join(bytes([key])+struct.pack('>H',len(v))+v for key,v in zip(b'abcd',fields))+b'e'+struct.pack('>I',len(payload))
    padding=128-len(header());assert padding>=0
    name,separator,options=fields[0].partition(b';')
    fields[0]=name+b'_'*padding+separator+options
    result=header()+payload
    assert len(header())==128 and parse(result)[2]==payload
    assert result.find(bytes.fromhex('aa995566'))%4==0
    destination.write_bytes(result)
    record=dict(source_sha256=hashlib.sha256(data).hexdigest(),normalized_sha256=hashlib.sha256(result).hexdigest(),
        old_payload_offset=old_offset,new_payload_offset=128,payload_sha256=hashlib.sha256(payload).hexdigest(),
        payload_unchanged=True,bytes=len(result),design_field=fields[0].decode().rstrip('\0'))
    destination.with_suffix('.normalization.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path);a=p.parse_args();normalize(a.source,a.destination)
