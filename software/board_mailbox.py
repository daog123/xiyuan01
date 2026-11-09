"""Host access to w4a8_board_top mailbox ABI 1; not the reference matrix ABI.

The IP must be integrated into a board shell before this backend can run on FPGA.
"""
import struct
from time import monotonic,sleep
from .w4a8_runtime import Completion,TaskExecutionError
from .board_xdma_io import XDMARegisterIO

MAGIC=0x58495738
ABI=1

def descriptor_words(task,*,group_size=32,max_m=64,max_n=64,max_k=4096):
    """26 consecutive little-endian words at mailbox offset 0x20."""
    task.validate(group_size=group_size,max_m=max_m,max_n=max_n,max_k=max_k,addr_width=64)
    d=task.descriptor
    words=[d.task_id,d.m,d.n,d.k]
    for address in [d.a_addr,d.w_addr,d.sx_addr,d.sw_addr,d.y_addr]:
        words.extend([address&0xffffffff,address>>32])
    words.extend([d.a_stride,d.w_stride,d.sx_stride,d.sw_stride,d.y_stride,
                  d.activation_format|(d.weight_format<<8)|(d.scale_format<<16)|(d.output_format<<24),
                  d.group_size|(d.flags<<16),task.a_bytes,task.w_bytes,task.sx_bytes,task.sw_bytes,task.y_bytes])
    assert len(words)==26 and all(0<=w<1<<32 for w in words)
    return words

class BoardMailbox:
    """One caller, one active task. IO supplies read32/write32/read_memory.

    poll/wait preserve DONE; read outputs before acknowledge(), which frees the slot.
    A timeout does not abort or reset an in-flight AXI operation.
    """
    def __init__(self,io):
        self.io=io;self.active=None
        if io.read32(0)!=MAGIC or io.read32(4)!=ABI:
            raise RuntimeError('loaded image is not w4a8_board_top mailbox ABI 1; no writes made')
        if io.read32(0x9c)!=64:raise RuntimeError('expected a 64-bit DDR address interface')
        self.limits=dict(group_size=io.read32(0x1c),max_m=io.read32(0x90),max_n=io.read32(0x94),max_k=io.read32(0x98))
    def submit(self,task):
        words=descriptor_words(task,**self.limits)
        if self.active is not None or self.io.read32(0xc)&7!=1:
            raise RuntimeError('mailbox not ready; finish and acknowledge the previous task first')
        for i,word in enumerate(words):self.io.write32(0x20+4*i,word)
        # Record ownership before START: an IO failure may have delivered the write.
        self.active=task
        self.io.write32(8,1)
    def poll(self):
        if self.active is None:return None
        if not self.io.read32(0xc)&4:return None
        event=Completion(self.io.read32(0x10),self.io.read32(0x14),self.io.read32(0x18))
        if event.task_id!=self.active.task_id:raise RuntimeError('completion task ID mismatch; preserve mailbox for diagnosis')
        return event
    def wait(self,timeout_s=30,poll_interval_s=0.001):
        if self.active is None:raise RuntimeError('no submitted task')
        deadline=monotonic()+timeout_s
        while monotonic()<deadline:
            event=self.poll()
            if event is not None:
                if event.status:raise TaskExecutionError(event)
                return event
            sleep(poll_interval_s)
        raise TimeoutError('board task still owned; timeout does not cancel hardware')
    def read_result(self):
        event=self.poll()
        if event is None:raise RuntimeError('result not complete')
        if event.status:raise TaskExecutionError(event)
        task=self.active
        return [list(struct.unpack('<%di'%task.n,self.io.read_memory(task.y_addr+r*task.y_stride,4*task.n))) for r in range(task.m)]
    def acknowledge(self):
        if self.poll() is None:raise RuntimeError('cannot acknowledge an unfinished task')
        self.io.write32(8,2);self.active=None

