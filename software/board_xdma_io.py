"""Python 3.6+ C6 XDMA transport; no FPGA programming or reset."""
import os
import stat
import struct
import threading
from pathlib import Path

class XDMARegisterIO:
    """Linux C6 channel-0 transport with fixed-PCI device-number checks.

    Paths may be private character nodes, as used by the validated bring-up script.
    No node creation, programming, reset, PCI rebind or persistent Flash operation.
    Address mapping is the candidate shell contract and must match its final wiring.
    """
    def __init__(self,h2c,c2h,*,pci='0000:84:00.0',control_base=0x20d0000000,aurora_base=0x2000000000):
        if os.name!='posix':raise RuntimeError('XDMA device access requires Linux')
        if pci!='0000:84:00.0':raise ValueError('this bring-up backend is restricted to PCI 0000:84:00.0')
        import fcntl
        self.hfd=self.rfd=None;self._locks=[];self._mutex=threading.Lock()
        self.control_base=control_base;self.aurora_base=aurora_base
        sys=Path('/sys/bus/pci/devices')/pci
        if (sys/'vendor').read_text().strip()!='0x10ee' or (sys/'device').read_text().strip()!='0x9038' or (sys/'subsystem_device').read_text().strip()!='0xeec6':
            raise RuntimeError('unexpected PCI device identity')
        users=list((sys/'xdma').glob('*_user'))
        if len(users)!=1:raise RuntimeError('ambiguous target XDMA mapping')
        xid=users[0].name[:-len('_user')]
        try:
            for lockpath in ['/tmp/xiyuan_bringup_84_00_0.lock','/tmp/dynamicstream_phase1_card0.lock']:
                fd=os.open(lockpath,os.O_RDWR|os.O_CREAT,0o600);self._locks.append(fd)
                fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            for attr,path,kind in [('hfd',h2c,'h2c_0'),('rfd',c2h,'c2h_0')]:
                fd=os.open(path,os.O_RDWR);setattr(self,attr,fd)
                major,minor=map(int,(Path('/sys/class/xdma')/(xid+'_'+kind)/'dev').read_text().split(':'))
                info=os.fstat(fd)
                if not stat.S_ISCHR(info.st_mode) or info.st_rdev!=os.makedev(major,minor):
                    raise RuntimeError('device node does not belong to selected PCI channel')
        except BaseException:
            self.close();raise
    def close(self):
        for attr in ['hfd','rfd']:
            fd=getattr(self,attr,None)
            if fd is not None:os.close(fd);setattr(self,attr,None)
        for fd in self._locks:os.close(fd)
        self._locks=[]
    def __enter__(self):return self
    def __exit__(self,*_):self.close()
    def _transfer(self,address,value,writing):
        if not 0<=address<1<<63:raise ValueError('address outside seekable XDMA space')
        size=len(value) if writing else value
        if size<0 or address+size>1<<63:raise ValueError('invalid transfer range')
        fd=self.hfd if writing else self.rfd
        if fd is None:raise RuntimeError('transport is closed')
        done=0;result=bytearray()
        with self._mutex:
            while done<size:
                if os.lseek(fd,address+done,os.SEEK_SET)!=address+done:raise OSError('XDMA seek failed')
                chunk=min(size-done,1<<20)
                part=os.write(fd,value[done:done+chunk]) if writing else os.read(fd,chunk)
                count=part if writing else len(part)
                if not count:raise OSError('short XDMA transfer')
                if not writing:result.extend(part)
                done+=count
        return bytes(result)
    def read32(self,offset):
        if offset%4 or not 0<=offset<4096:raise ValueError('invalid mailbox offset')
        return struct.unpack('<I',self._transfer(self.control_base+offset,4,False))[0]
    def write32(self,offset,value):
        if offset%4 or not 0<=offset<4096:raise ValueError('invalid mailbox offset')
        self._transfer(self.control_base+offset,struct.pack('<I',value),True)
    def read_memory(self,address,size):return self._transfer(self.aurora_base+address,size,False)
    def write_memory(self,address,value):self._transfer(self.aurora_base+address,value,True)
