import unittest

try:
    from .w4a8_reference import gemm
    from .w4a8_task import W4A8Task, split_mn
except ImportError:
    from w4a8_reference import gemm
    from w4a8_task import W4A8Task, split_mn


def task(**updates):
    values = dict(task_id=7, m=65, n=17, k=33, a_addr=0x1000, w_addr=0x2000,
                  sx_addr=0x3000, sw_addr=0x4000, y_addr=0x5000,
                  a_stride=40, w_stride=20, sx_stride=4, sw_stride=40, y_stride=80)
    values.update(updates)
    return W4A8Task(**values)


class TaskTests(unittest.TestCase):
    def test_rejects_bad_group_and_format(self):
        with self.assertRaises(ValueError):
            task().validate(group_size=32)
        with self.assertRaises(ValueError):
            task(group_size=32, weight_format=2).validate(max_m=128, group_size=32)

    def test_rejects_address_range_overflow(self):
        with self.assertRaises(ValueError):
            task(m=2, n=1, k=1, a_stride=1, w_stride=1, sx_stride=2, sw_stride=2,
                 y_addr=(1 << 64) - 4, y_stride=4).validate()

    def test_split_mn_keeps_k_whole_and_maps_tails(self):
        pieces = split_mn(task(), tile_m=64, tile_n=16, max_k=64, group_size=32)
        self.assertEqual([(p.m, p.n, p.k) for p in pieces], [(64, 16, 33), (64, 1, 33), (1, 16, 33), (1, 1, 33)])
        self.assertEqual(pieces[2].a_addr, 0x1000 + 64 * 40)
        self.assertEqual(pieces[1].w_addr, 0x2000 + 16 * 20)
        self.assertEqual(pieces[3].y_addr, 0x5000 + 64 * 80 + 16 * 4)

    def test_reference_zero_and_signed_nibble(self):
        result = gemm([[127]], [[0xF]], [[4096]], [[4096]], 1, 1, 1, 32)
        self.assertEqual(result, [[-127 * 65536]])

    def test_runtime_accepts_contiguous_tasks(self):
        try:
            from .w4a8_runtime import W4A8Runtime
        except ImportError:
            from w4a8_runtime import W4A8Runtime

        class Transport:
            def __init__(self):
                self.event = None
                self.descriptors = []

            def write_descriptor(self, desc):
                self.descriptors.append(desc)
                self.event = type("Event", (), {"task_id": desc["task_id"], "status": 0})()

            def ring_doorbell(self):
                pass

            def read_completion(self):
                event, self.event = self.event, None
                return event

        transport = Transport()
        runtime = W4A8Runtime(transport)
        first = W4A8Task(20, 1, 1, 1, 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 1, 1, 2, 2, 4)
        second = W4A8Task(21, 1, 1, 1, 0x1000, 0x2000, 0x3000, 0x4000, 0x5000, 1, 1, 2, 2, 4)
        runtime.submit(first)
        with self.assertRaises(RuntimeError):
            runtime.submit(second)
        runtime.wait(timeout_s=0.1)
        runtime.submit(second)
        self.assertEqual(runtime.wait(timeout_s=0.1).task_id, 21)
        self.assertEqual(len(transport.descriptors), 2)


if __name__ == "__main__":
    unittest.main()
