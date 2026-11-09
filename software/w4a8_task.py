"""Task descriptor helpers matching task_desc_pkg.sv."""
from dataclasses import asdict, dataclass

STATUS_OK = 0
FORMAT_INT8 = FORMAT_SINT4_PACKED = FORMAT_UQ4_12 = FORMAT_Q16_16 = 1


@dataclass(frozen=True)
class W4A8Task:
    task_id: int
    m: int
    n: int
    k: int
    a_addr: int
    w_addr: int
    sx_addr: int
    sw_addr: int
    y_addr: int
    a_stride: int
    w_stride: int
    sx_stride: int
    sw_stride: int
    y_stride: int
    activation_format: int = FORMAT_INT8
    weight_format: int = FORMAT_SINT4_PACKED
    scale_format: int = FORMAT_UQ4_12
    output_format: int = FORMAT_Q16_16
    group_size: int = 32
    flags: int = 0

    def validate(self, *, max_m=64, max_n=64, max_k=4096, group_size=32):
        if not (0 < self.m <= max_m and 0 < self.n <= max_n and 0 < self.k <= max_k):
            raise ValueError("dimension outside supported W4A8 capacity")
        if (self.activation_format, self.weight_format, self.scale_format, self.output_format) != (1, 1, 1, 1):
            raise ValueError("unsupported tensor format")
        if self.group_size != group_size:
            raise ValueError(f"group_size must match configured hardware value {group_size}")
        if self.flags != 0:
            raise ValueError("unsupported flags")
        if any(address <= 0 or address >= 1 << 64 for address in
               (self.a_addr, self.w_addr, self.sx_addr, self.sw_addr, self.y_addr)):
            raise ValueError("addresses must be non-zero unsigned 64-bit values")
        if self.sx_addr & 1 or self.sw_addr & 1 or self.y_addr & 3:
            raise ValueError("scale addresses require 2-byte and output address 4-byte alignment")
        groups = (self.k + group_size - 1) // group_size
        if (self.a_stride < self.k or self.w_stride < (self.k + 1) // 2 or
                self.sx_stride < groups * 2 or self.sw_stride < self.n * 2 or self.y_stride < self.n * 4):
            raise ValueError("byte stride is smaller than its logical row")
        spans = (
            (self.a_addr, (self.m - 1) * self.a_stride + self.k),
            (self.w_addr, (self.n - 1) * self.w_stride + (self.k + 1) // 2),
            (self.sx_addr, (self.m - 1) * self.sx_stride + groups * 2),
            (self.sw_addr, (groups - 1) * self.sw_stride + self.n * 2),
            (self.y_addr, (self.m - 1) * self.y_stride + self.n * 4),
        )
        if any(base + length > 1 << 64 for base, length in spans):
            raise ValueError("tensor address range overflows uint64")
        if self.task_id < 0 or self.task_id >= 1 << 32:
            raise ValueError("task_id must fit uint32")
        return self

    def to_dict(self):
        return asdict(self)


def split_mn(task: W4A8Task, tile_m=64, tile_n=64, *, max_k=4096, group_size=32):
    """Tile M/N; preserve full K because this core has no partial-sum continuation API."""
    task.validate(max_m=65535, max_n=65535, max_k=max_k, group_size=group_size)
    pieces = []
    for m0 in range(0, task.m, tile_m):
        for n0 in range(0, task.n, tile_n):
            mm, nn = min(tile_m, task.m - m0), min(tile_n, task.n - n0)
            pieces.append(W4A8Task(
                task_id=task.task_id + len(pieces), m=mm, n=nn, k=task.k,
                a_addr=task.a_addr + m0 * task.a_stride,
                w_addr=task.w_addr + n0 * task.w_stride,
                sx_addr=task.sx_addr + m0 * task.sx_stride,
                sw_addr=task.sw_addr + n0 * 2,
                y_addr=task.y_addr + m0 * task.y_stride + n0 * 4,
                a_stride=task.a_stride, w_stride=task.w_stride, sx_stride=task.sx_stride,
                sw_stride=task.sw_stride, y_stride=task.y_stride,
                activation_format=task.activation_format, weight_format=task.weight_format,
                scale_format=task.scale_format, output_format=task.output_format,
                group_size=task.group_size, flags=task.flags))
    return pieces
