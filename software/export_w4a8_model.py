"""Emit a JSON task manifest for already-quantized W4A8 tensor buffers."""
import argparse
import json
from pathlib import Path

from w4a8_task import W4A8Task


def export(task, output):
    task.validate()
    Path(output).write_text(json.dumps(task.to_dict(), indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--task-id", type=int, default=1)
    parser.add_argument("--m", type=int, required=True)
    parser.add_argument("--n", type=int, required=True)
    parser.add_argument("--k", type=int, required=True)
    parser.add_argument("--a", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--w", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--sx", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--sw", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--y", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--group-size", type=int, default=32)
    args = parser.parse_args()
    task = W4A8Task(args.task_id, args.m, args.n, args.k, args.a, args.w, args.sx, args.sw, args.y,
                    args.k, (args.k + 1) // 2, ((args.k + args.group_size - 1) // args.group_size) * 2,
                    args.n * 2, args.n * 4, group_size=args.group_size)
    export(task, args.output)


if __name__ == "__main__":
    main()
