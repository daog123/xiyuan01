"""Host semantics only; physical access is not emulated as a board success."""
import struct
import unittest
from dataclasses import replace
from .board_mailbox import BoardMailbox,descriptor_words,MAGIC
from .w4a8_task import W4A8Task
from .w4a8_memory_task import W4A8MemoryTask
from .w4a8_runtime import TaskExecutionError

def task():
    base=0x800000000
    return W4A8MemoryTask(W4A8Task(73,1,2,35,base+0x1000,base+0x2000,base+0x3000,base+0x4000,base+0x5000,35,18,4,4,8),35,36,4,8,8)

class Registers:
    def __init__(self):
        self.words={0:MAGIC,4:1,0xc:9,0x1c:32,0x90:64,0x94:64,0x98:4096,0x9c:64}
        self.writes=[];self.reads=[]
    def read32(self,offset):return self.words.get(offset,0)
    def write32(self,offset,value):self.writes.append((offset,value));self.words[offset]=value
    def read_memory(self,address,size):self.reads.append((address,size));return struct.pack('<2i',7,-9)
    def complete(self,status=0,id=73):self.words.update({0xc:12|(16 if status==0 else 0),0x10:id,0x14:status,0x18:456})

class BoardMailboxTests(unittest.TestCase):
    def test_word_layout_preserves_64_bit_addresses(self):
        w=descriptor_words(task());self.assertEqual(w[:4],[73,1,2,35]);self.assertEqual(w[4:6],[0x1000,8])
        self.assertEqual(w[12:14],[0x5000,8]);self.assertEqual(w[19:],[0x01010101,32,35,36,4,8,8])
    def test_image_mismatch_never_writes(self):
        io=Registers();io.words[0]=0
        with self.assertRaises(RuntimeError):BoardMailbox(io)
        self.assertEqual(io.writes,[])
    def test_abi_mismatch_never_writes(self):
        io=Registers();io.words[4]=2
        with self.assertRaises(RuntimeError):BoardMailbox(io)
        self.assertEqual(io.writes,[])
    def test_invalid_capacity_never_writes(self):
        io=Registers();board=BoardMailbox(io)
        with self.assertRaises(ValueError):board.submit(replace(task(),a_bytes=1))
        self.assertEqual(io.writes,[])
    def test_unacknowledged_completion_blocks_submit(self):
        io=Registers();io.complete();board=BoardMailbox(io)
        with self.assertRaises(RuntimeError):board.submit(task())
        self.assertEqual(io.writes,[])
    def test_complete_snapshot_result_then_ack(self):
        io=Registers();board=BoardMailbox(io);board.submit(task());self.assertEqual(io.writes[-1],(8,1))
        self.assertIsNone(board.poll());io.complete();event=board.wait()
        self.assertEqual((event.task_id,event.status,event.elapsed_cycles),(73,0,456))
        self.assertEqual(board.read_result(),[[7,-9]])
        self.assertEqual(io.reads,[(0x800005000,8)])
        self.assertNotIn((8,2),io.writes);board.acknowledge();self.assertEqual(io.writes[-1],(8,2))
        self.assertIsNone(board.active)
    def test_error_has_no_result_read(self):
        io=Registers();board=BoardMailbox(io);board.submit(task());io.complete(11)
        with self.assertRaises(TaskExecutionError):board.wait()
        with self.assertRaises(TaskExecutionError):board.read_result()
        self.assertEqual(io.reads,[]);self.assertNotIn((8,2),io.writes)
        board.acknowledge()
    def test_timeout_preserves_ownership(self):
        io=Registers();board=BoardMailbox(io);board.submit(task())
        with self.assertRaises(TimeoutError):board.wait(timeout_s=0)
        self.assertIsNotNone(board.active);self.assertNotIn((8,2),io.writes)
        with self.assertRaises(RuntimeError):board.submit(task())
    def test_mismatched_completion_preserved(self):
        io=Registers();board=BoardMailbox(io);board.submit(task());io.complete(id=74)
        with self.assertRaises(RuntimeError):board.acknowledge()
        self.assertNotIn((8,2),io.writes)
    def test_early_ack_rejected(self):
        io=Registers();board=BoardMailbox(io);board.submit(task())
        with self.assertRaises(RuntimeError):board.acknowledge()
        self.assertNotIn((8,2),io.writes)
    def test_start_io_failure_keeps_ownership(self):
        io=Registers();board=BoardMailbox(io);original=io.write32
        def fail_start(offset,value):
            original(offset,value)
            if offset==8:raise OSError('completion of host write unknown')
        io.write32=fail_start
        with self.assertRaises(OSError):board.submit(task())
        self.assertIsNotNone(board.active)

if __name__=='__main__':unittest.main()
