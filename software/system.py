"""Version 5 host API shared by llm_top, project configuration and examples.

The transport owns register/stream access; this module does not pretend that a
PCIe/DDR driver exists. All completions come from the actual transport.
"""
from dataclasses import asdict,dataclass
from enum import IntEnum
from .w4a8_memory_task import W4A8MemoryTask
from .w4a8_runtime import W4A8Runtime

ABI_VERSION=5
class Opcode(IntEnum):
    LINEAR=0
    FFN=1
    ATTENTION=2
    KV_CONFIG=3
    KV_COMMAND=4
    Q_ATTENTION=5
    QKV_ATTENTION=6

def overlap(a,n,b,m):return a<b+m and b<a+n
def bounded_wire(t):
    d=asdict(t);d['desc']=d.pop('descriptor');return d

@dataclass(frozen=True)
class FFNPlan:
    task_id:int
    gate_task:W4A8MemoryTask
    up_task:W4A8MemoryTask
    down_task:W4A8MemoryTask

    def validate(self,*,max_m=64,max_n=64,max_k=4096,group_size=32,addr_width=64,max_h=64,capacity=512):
        for t in (self.gate_task,self.up_task,self.down_task):
            t.validate(max_m=max_m,max_n=max_n,max_k=max_k,group_size=group_size,addr_width=addr_width)
        g,u,d=(t.descriptor for t in (self.gate_task,self.up_task,self.down_task))
        if not 0<=self.task_id<1<<32 or len({g.task_id,u.task_id,d.task_id})!=3:
            raise ValueError('invalid or overlapping task IDs')
        if (g.m,g.n,g.k)!=(u.m,u.n,u.k) or (d.m,d.k)!=(g.m,g.n) or g.n>max_h or g.m*g.n>capacity:
            raise ValueError('incompatible FFN branch/down shapes or bridge capacity')
        writable=[(g.y_addr,self.gate_task.y_bytes),(u.y_addr,self.up_task.y_bytes),
                  (d.a_addr,self.down_task.a_bytes),(d.sx_addr,self.down_task.sx_bytes),(d.y_addr,self.down_task.y_bytes)]
        immutable=[]
        for t in (self.gate_task,self.up_task):
            immutable += [(getattr(t.descriptor,x+'_addr'),getattr(t,x+'_bytes')) for x in ('a','w','sx','sw')]
        immutable += [(d.w_addr,self.down_task.w_bytes),(d.sw_addr,self.down_task.sw_bytes)]
        for i,(base,size) in enumerate(writable):
            if any(overlap(base,size,b,n) for b,n in immutable+writable[i+1:]):
                raise ValueError('FFN workspace aliases live input/output allocations')
        return self

    def to_dict(self):
        return dict(task_id=self.task_id,**{name:bounded_wire(getattr(self,name)) for name in ('gate_task','up_task','down_task')})

@dataclass(frozen=True)
class KVConfig:
    config_id:int
    layers:int
    heads:int
    capacity:int
    dimension:int
    group_size:int
    base:tuple
    bytes:tuple
    token_stride:tuple
    head_stride:tuple
    layer_stride:tuple
    format_id:int=1

    def validate(self,*,group_size=32,addr_width=64,max_dim=64,max_tokens=16,**_):
        if not (0<=self.config_id<1<<32 and 0<self.layers<=4 and 0<self.heads<=8 and
                0<self.capacity<=max_tokens and 0<self.dimension<=max_dim and self.group_size==group_size and self.format_id==1):
            raise ValueError('unsupported KV configuration')
        if any(len(x)!=4 for x in (self.base,self.bytes,self.token_stride,self.head_stride,self.layer_stride)):
            raise ValueError('KV requires exactly K,V,SK,SV planes')
        for p in range(4):
            width=self.dimension if p<2 else 2*((self.dimension+group_size-1)//group_size)
            head=(self.capacity-1)*self.token_stride[p]+width
            layer=(self.heads-1)*self.head_stride[p]+head
            extent=(self.layers-1)*self.layer_stride[p]+layer
            if not (0<=self.base[p]<1<<addr_width and 0<self.bytes[p]<1<<32 and
                    self.base[p]+self.bytes[p]<=1<<addr_width and extent<=self.bytes[p] and
                    self.token_stride[p]>=width and self.head_stride[p]>=head and self.layer_stride[p]>=layer):
                raise ValueError('KV allocation does not contain its layout')
            if any(not 0<=x<1<<32 for x in (self.token_stride[p],self.head_stride[p],self.layer_stride[p])):
                raise ValueError('KV strides must fit uint32')
            if p>=2 and any(x%2 for x in (self.base[p],self.token_stride[p],self.head_stride[p],self.layer_stride[p])):
                raise ValueError('KV scale layout must be 2-byte aligned')
            if any(overlap(self.base[p],self.bytes[p],self.base[q],self.bytes[q]) for q in range(p)):
                raise ValueError('KV planes overlap')
        return self

@dataclass(frozen=True)
class AttentionTask:
    task_id:int
    layer:int
    head:int
    tokens:int
    dimension:int
    score_scale:int
    y_addr:int
    y_bytes:int
    q_source:int=0
    q_addr:int=0
    qs_addr:int=0
    q_bytes:int=0
    qs_bytes:int=0

    def validate(self,*,addr_width=64,max_dim=64,max_tokens=16,group_size=32,config=None,committed=None,**_):
        if not (0<=self.task_id<1<<32 and 0<=self.layer<4 and 0<=self.head<8 and
                0<self.tokens<=max_tokens and 0<self.dimension<=max_dim and 0<self.score_scale<1<<16):
            raise ValueError('unsupported attention shape or score scale')
        if not (0<=self.y_addr<1<<addr_width and self.y_addr%4==0 and
                4*self.dimension<=self.y_bytes<1<<32 and self.y_addr+self.y_bytes<=1<<addr_width):
            raise ValueError('invalid attention output allocation')
        if self.q_source not in (0,1,2):raise ValueError('unsupported Q source')
        if self.q_source==0:
            if any((self.q_addr,self.qs_addr,self.q_bytes,self.qs_bytes)):
                raise ValueError('stream Q must have zero memory allocation fields')
        else:
            regions=[(self.q_addr,self.q_bytes,self.dimension*(4 if self.q_source==2 else 1))]
            if self.q_source==1:regions.append((self.qs_addr,self.qs_bytes,2*((self.dimension+group_size-1)//group_size)))
            elif self.q_addr%4 or self.qs_addr or self.qs_bytes:raise ValueError('Q16 query requires aligned values and zero scale allocation fields')
            for base,size,width in regions:
                if not (0<=base<1<<addr_width and width<=size<1<<32 and base+size<=1<<addr_width):
                    raise ValueError('invalid Q input allocation')
                if overlap(self.y_addr,self.y_bytes,base,size):raise ValueError('Q input overlaps output')
            if self.q_source==1 and overlap(self.q_addr,self.q_bytes,self.qs_addr,self.qs_bytes):raise ValueError('Q and scale allocations overlap')
        if committed is not None and self.tokens>committed:raise ValueError('attention reads uncommitted tokens')
        if config is not None:
            if self.dimension!=config.dimension or self.layer>=config.layers or self.head>=config.heads:
                raise ValueError('attention metadata differs from KV layout')
            if any(overlap(self.y_addr,self.y_bytes,b,n) for b,n in zip(config.base,config.bytes)):
                raise ValueError('attention output overlaps KV storage')
        return self

@dataclass(frozen=True)
class KVCommand:
    task_id:int
    operation:int
    layer:int=0
    head:int=0
    token:int=0
    count:int=0
    plane:int=0
    offset:int=0
    length:int=0

    def validate(self,*,group_size=32,max_dim=64,max_tokens=16,**_):
        if not (0<=self.task_id<1<<32 and 0<=self.layer<4 and 0<=self.head<8 and
                0<=self.plane<4 and all(0<=x<1<<16 for x in (self.token,self.count,self.offset,self.length))):
            raise ValueError('invalid KV command fields')
        if self.operation==2:
            legal=(self.token,self.count,self.plane,self.offset,self.length)==(0,0,0,0,0)
        elif self.operation==0:
            legal=self.count>0 and self.token+self.count<=max_tokens and (self.plane,self.offset,self.length)==(0,0,0)
        elif self.operation==1:
            width=max_dim if self.plane<2 else 2*((max_dim+group_size-1)//group_size)
            legal=self.count>0 and self.token+self.count<=max_tokens and self.length>0 and self.offset+self.length<=width
        else:legal=False
        if not legal:raise ValueError('unsupported KV operation or range')
        return self

@dataclass(frozen=True)
class ProjectedAttentionPlan:
    projection:W4A8MemoryTask
    attention:AttentionTask

    @property
    def task_id(self):return self.attention.task_id

    def validate(self,*,max_m=64,max_n=64,max_k=4096,group_size=32,addr_width=64,config=None,committed=None):
        self.projection.validate(max_m=max_m,max_n=max_n,max_k=max_k,group_size=group_size,addr_width=addr_width)
        a=self.attention;d=self.projection.descriptor
        a.validate(group_size=group_size,addr_width=addr_width,config=config,committed=committed)
        if d.m!=1 or d.n!=a.dimension or a.q_source!=2 or a.q_addr!=d.y_addr or a.q_bytes!=self.projection.y_bytes:
            raise ValueError('projection must produce the single Q16 query allocation')
        for field in ('a','w','sx','sw'):
            if overlap(a.y_addr,a.y_bytes,getattr(d,field+'_addr'),getattr(self.projection,field+'_bytes')):
                raise ValueError('attention output aliases a live projection input')
        if config is not None and any(overlap(d.y_addr,self.projection.y_bytes,b,n) for b,n in zip(config.base,config.bytes)):
            raise ValueError('projection workspace aliases persistent KV storage')
        return self

    def to_dict(self):return dict(linear_task=bounded_wire(self.projection),attention_task=asdict(self.attention))

@dataclass(frozen=True)
class QKVAttentionPlan:
    q_task:W4A8MemoryTask
    k_task:W4A8MemoryTask
    v_task:W4A8MemoryTask
    attention:AttentionTask
    token:int=0

    @property
    def task_id(self):return self.attention.task_id

    def validate(self,*,max_m=64,max_n=64,max_k=4096,group_size=32,addr_width=64,config=None,committed=None):
        nodes=(self.q_task,self.k_task,self.v_task);a=self.attention
        for t in nodes:t.validate(max_m=max_m,max_n=max_n,max_k=max_k,group_size=group_size,addr_width=addr_width)
        a.validate(group_size=group_size,addr_width=addr_width,config=config)
        if len({t.task_id for t in nodes})!=3:raise ValueError('projection IDs must be distinct')
        if not 0<=self.token<16 or a.tokens!=self.token+1 or (config is not None and self.token>=config.capacity):
            raise ValueError('single-token graph must query its newly appended prefix')
        if committed is not None and self.token!=committed:raise ValueError('append token differs from committed length')
        if any(t.m!=1 or t.n!=a.dimension or t.descriptor.k!=nodes[0].descriptor.k for t in nodes):
            raise ValueError('Q/K/V must be compatible single-query projections')
        if a.q_source!=2 or a.q_addr!=self.q_task.y_addr or a.q_bytes!=self.q_task.y_bytes:
            raise ValueError('graph query must use its Q16 projection allocation')
        outputs=[(t.y_addr,t.y_bytes)for t in nodes]+[(a.y_addr,a.y_bytes)]
        inputs=[(getattr(t.descriptor,f+'_addr'),getattr(t,f+'_bytes'))for t in nodes for f in ('a','w','sx','sw')]
        if config is not None:inputs+=list(zip(config.base,config.bytes))
        for i,(b,n) in enumerate(outputs):
            if any(overlap(b,n,c,m)for c,m in inputs+outputs[i+1:]):raise ValueError('graph output aliases live input, KV or workspace')
        return self

    def kv_committed(self,completion):
        if completion.task_id!=self.task_id:raise ValueError('completion belongs to a different graph')
        if completion.status==0:return True
        if completion.stage is None:return None
        if completion.stage==13:return True
        if completion.stage in (0,8,9,10,11,12):return False
        return None

    def resume_query(self):return ProjectedAttentionPlan(self.q_task,self.attention)

    def to_dict(self):return dict(qkv_plan=dict(q_task=bounded_wire(self.q_task),k_task=bounded_wire(self.k_task),v_task=bounded_wire(self.v_task),attention=asdict(self.attention),token=self.token))

@dataclass(frozen=True)
class SystemJob:
    opcode:Opcode
    payload:object

    @property
    def task_id(self):return self.payload.config_id if self.opcode==Opcode.KV_CONFIG else self.payload.task_id

    def validate(self,*,max_m=64,max_n=64,max_k=4096,group_size=32,addr_width=64):
        limits=dict(max_m=max_m,max_n=max_n,max_k=max_k,group_size=group_size,addr_width=addr_width)
        expected={Opcode.LINEAR:W4A8MemoryTask,Opcode.FFN:FFNPlan,Opcode.ATTENTION:AttentionTask,Opcode.KV_CONFIG:KVConfig,Opcode.KV_COMMAND:KVCommand,Opcode.Q_ATTENTION:ProjectedAttentionPlan,Opcode.QKV_ATTENTION:QKVAttentionPlan}
        if self.opcode not in expected or not isinstance(self.payload,expected[self.opcode]):
            raise ValueError('unsupported opcode/payload')
        self.payload.validate(**limits)
        return self

    def to_dict(self):
        if self.opcode in (Opcode.Q_ATTENTION,Opcode.QKV_ATTENTION):return dict(abi_version=ABI_VERSION,job_opcode=int(self.opcode),**self.payload.to_dict())
        field={Opcode.LINEAR:'linear_task',Opcode.FFN:'ffn_plan',Opcode.ATTENTION:'attention_task',Opcode.KV_CONFIG:'kv_config',Opcode.KV_COMMAND:'kv_command'}[self.opcode]
        data=bounded_wire(self.payload) if self.opcode==Opcode.LINEAR else self.payload.to_dict() if self.opcode==Opcode.FFN else asdict(self.payload)
        return dict(abi_version=ABI_VERSION,job_opcode=int(self.opcode),**{field:data})

class ProjectRuntime(W4A8Runtime):
    def __init__(self,transport,*,addr_width=64,**limits):
        super().__init__(transport,**limits);self.limits['addr_width']=addr_width

    def submit(self,job):
        if not isinstance(job,SystemJob):raise TypeError('ProjectRuntime expects a versioned SystemJob')
        return super().submit(job)
