"""Small synchronous software backend; hardware access is supplied by a transport."""
from dataclasses import dataclass
from time import monotonic, sleep


@dataclass
class Completion:
    task_id: int
    status: int
    elapsed_cycles: int = 0
    stage: int | None = None


class TaskExecutionError(RuntimeError):
    def __init__(self, completion):
        self.completion=completion
        super().__init__(f"W4A8 task failed with status {completion.status}, stage {completion.stage}")


class W4A8Runtime:
    def __init__(self, transport, *, max_m=64, max_n=64, max_k=4096, group_size=32):
        self.transport = transport
        self.limits = dict(max_m=max_m, max_n=max_n, max_k=max_k, group_size=group_size)
        self.active_task = None

    def submit(self, task):
        task.validate(**self.limits)
        if self.active_task is not None:
            raise RuntimeError("single-active-task backend is busy")
        self.transport.write_descriptor(task.to_dict())
        self.transport.ring_doorbell()
        self.active_task = task.task_id

    def poll(self):
        if self.active_task is None:
            return None
        event = self.transport.read_completion()
        if event is None:
            return None
        if event.task_id != self.active_task:
            raise RuntimeError("completion task_id does not match active task")
        self.active_task = None
        return event

    def wait(self, timeout_s=30.0, poll_interval_s=0.001):
        deadline = monotonic() + timeout_s
        while monotonic() < deadline:
            completion = self.poll()
            if completion is not None:
                if completion.status:
                    raise TaskExecutionError(completion)
                return completion
            sleep(poll_interval_s)
        raise TimeoutError("W4A8 completion timeout")

    def read_result(self, task, *, timeout_s=30.0):
        if self.active_task is not None:
            self.wait(timeout_s=timeout_s)
        return self.transport.read_tensor(task.y_addr, task.m, task.n, task.y_stride)
