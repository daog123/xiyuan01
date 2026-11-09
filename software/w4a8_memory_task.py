"""Host-side checks for w4a8_team_top's bounded 32/64-bit AXI interfaces."""
from dataclasses import asdict, dataclass
from .w4a8_task import W4A8Task


@dataclass(frozen=True)
class W4A8MemoryTask:
    descriptor: W4A8Task
    a_bytes: int
    w_bytes: int
    sx_bytes: int
    sw_bytes: int
    y_bytes: int

    @property
    def task_id(self):
        return self.descriptor.task_id

    @property
    def y_addr(self):
        return self.descriptor.y_addr

    @property
    def y_stride(self):
        return self.descriptor.y_stride

    @property
    def m(self):
        return self.descriptor.m

    @property
    def n(self):
        return self.descriptor.n

    def validate(self, *, max_m=64, max_n=64, max_k=4096, group_size=32, addr_width=32):
        if addr_width not in (32, 64):
            raise ValueError('address width must be 32 or 64')
        d = self.descriptor.validate(max_m=max_m, max_n=max_n, max_k=max_k, group_size=group_size)
        groups = (d.k + group_size - 1) // group_size
        if d.sx_stride % 2 or d.sw_stride % 2 or d.y_stride % 4:
            raise ValueError('storage scale/output strides require 2/4-byte alignment')
        if any(not 0 < s < 1 << 32 for s in (d.a_stride, d.w_stride, d.sx_stride, d.sw_stride, d.y_stride)):
            raise ValueError('byte strides must fit the uint32 host ABI')
        regions = [
            (d.a_addr, self.a_bytes, (d.m - 1) * d.a_stride + d.k),
            (d.w_addr, self.w_bytes, (d.n - 1) * d.w_stride + (d.k + 1) // 2),
            (d.sx_addr, self.sx_bytes, (d.m - 1) * d.sx_stride + 2 * groups),
            (d.sw_addr, self.sw_bytes, (groups - 1) * d.sw_stride + 2 * d.n),
            (d.y_addr, self.y_bytes, (d.m - 1) * d.y_stride + 4 * d.n),
        ]
        for base, size, extent in regions:
            if not isinstance(size, int) or not 0 < size < 1 << 32 or extent > size:
                raise ValueError('allocation capacity does not contain tensor extent')
            if base >= 1 << addr_width or base + size > 1 << addr_width:
                raise ValueError('allocation outside configured AXI address space')
        y, size, _ = regions[-1]
        if any(y < base + count and base < y + size for base, count, _ in regions[:-1]):
            raise ValueError('output allocation overlaps an input allocation')
        return self

    def to_dict(self):
        """Transport implementations send descriptor plus all five capacity sidebands."""
        return asdict(self)
