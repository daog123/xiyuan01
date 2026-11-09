"""Deterministic INT8 / wrapping INT32 oracle; Optional independent NumPy crosscheck."""
import argparse
import json
import random
from pathlib import Path

SEED = 20261011
MAX_M, MAX_N, MAX_K = 16, 16, 32
try:
    import numpy as np
except (ImportError, OSError):
    np = None


def i32(value):
    value &= 0xffffffff
    return value - 0x100000000 if value & 0x80000000 else value


def gemm(a, b):
    # Wrap every addition, matching the RTL accumulator exactly.
    m, k, n = len(a), len(b), len(b[0])
    out = [[0] * n for _ in range(m)]
    for r in range(m):
        for c in range(n):
            for q in range(k):
                out[r][c] = i32(out[r][c] + a[r][q] * b[q][c])
    return out


def expected_cycles(m, n, k, rows, cols, tile_k):
    output_tiles = ((m + rows - 1) // rows) * ((n + cols - 1) // cols)
    k_tiles = (k + tile_k - 1) // tile_k
    # CLEAR, per-K-tile serial load, PRIME, RUN, SAVE, ADVANCE.
    return output_tiles * (1 + k_tiles * (2 * tile_k * (rows + cols) + rows * cols + 2) + k)


def optimized_cycles(m, n, k, rows, cols, tile_k):
    mt = (m + rows - 1) // rows
    ot = mt * ((n + cols - 1) // cols)
    kt = (k + tile_k - 1) // tile_k
    return mt * (rows * k + 1) + ot * (1 + cols * k + 3 * kt + k + rows * cols)


def double_buffer_cycles(m, n, k, rows, cols, tile_k, gap=0):
    """Event-time recurrence: fill completion, bank release, consumer take."""
    def output_tile(with_a):
        previous_release = 1 + (rows * k + 1 if with_a else 0)
        previous_fill = 0
        releases = []
        for index, start_k in enumerate(range(0, k, tile_k)):
            length = min(tile_k, k - start_k)
            claim = 2 if index == 0 else previous_fill + gap + 1
            if index >= 2:
                claim = max(claim, releases[index - 2] + 1)
            fill = claim + cols * length * (gap + 1)
            take = max(previous_release + 1, fill + 1)
            release = take + length + 2
            if start_k + tile_k >= k:
                release += rows * cols
            releases.append(release)
            previous_release, previous_fill = release, fill
        return previous_release
    mt = (m + rows - 1) // rows
    nt = (n + cols - 1) // cols
    return mt * (output_tile(True) + (nt - 1) * output_tile(False))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--out', type=Path, default=Path('build/vectors'))
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    rng = random.Random(SEED)
    specs = [
        ('zero', 4, 4, 8, 'zero'),
        ('signed', 4, 4, 4, 'signed'),
        ('int8_bounds', 4, 4, 8, 'bounds'),
        ('random_rect', 3, 7, 6, 'random'),
        ('cross_k', 4, 4, 19, 'random'),
        ('all_tails', 7, 9, 13, 'random'),
        ('gemv', 1, 9, 17, 'bounds'),
        ('consecutive_nonzero', 5, 3, 11, 'random'),
        ('consecutive_zero', 5, 3, 11, 'zero'),
        ('minimal', 1, 1, 1, 'bounds'),
        ('full_capacity', 16, 16, 32, 'random'),
        ('tall_rect', 13, 2, 9, 'signed'),
        ('resume_after_reset', 2, 5, 7, 'random'),
    ]
    cases = []
    with (args.out / 'vectors.txt').open('w', encoding='ascii') as f:
        f.write(f'{len(specs)}\n')
        for cid, (name, m, n, k, mode) in enumerate(specs):
            def elem(index, offset):
                if mode == 'zero':
                    return 0
                if mode == 'bounds':
                    return [-128, 127, -1, 0, 1, -128, 127][(index + offset) % 7]
                if mode == 'signed':
                    return ((index * 7 + offset * 3) % 31) - 15
                return rng.randrange(-128, 128)
            a = [[elem(r * k + q, 0) for q in range(k)] for r in range(m)]
            b = [[elem(q * n + c, 2) for c in range(n)] for q in range(k)]
            c = gemm(a, b)
            if np is not None:
                independent = np.asarray(a, dtype=np.int64) @ np.asarray(b, dtype=np.int64)
                assert [[i32(int(v)) for v in row] for row in independent] == c
            f.write(f'{cid} {m} {n} {k}\n')
            for mat in (a, b, c):
                f.write(' '.join(str(x) for row in mat for x in row) + '\n')
            cases.append({'id': cid, 'name': name, 'm': m, 'n': n, 'k': k,
                          'outputs': m * n, 'A': a, 'B': b, 'C': c,
                          'cycles_4x4_k8': expected_cycles(m,n,k,4,4,8),
                          'cycles_2x3_k5': expected_cycles(m,n,k,2,3,5),
                          'optimized_cycles_4x4_k8': optimized_cycles(m,n,k,4,4,8),
                          'optimized_cycles_2x3_k5': optimized_cycles(m,n,k,2,3,5),
                          'double_buffer_cycles_4x4_k8': double_buffer_cycles(m,n,k,4,4,8),
                          'double_buffer_cycles_2x3_k5': double_buffer_cycles(m,n,k,2,3,5)})
    pe_specs = [(2147483647,-128,-128), (-2147483648,-128,127),
                (0,-128,-128), (0,-128,127), (0,127,127),
                (-1,1,1), (2147483600,127,1), (-2147483600,-128,1)]
    with (args.out / 'pe_vectors.txt').open('w', encoding='ascii') as f:
        f.write(f'{len(pe_specs)}\n')
        for seed,a,b in pe_specs:
            f.write(f'{seed} {a} {b} {i32(seed+a*b)}\n')
    # A naturally overflowing dot product, as a reference-model self-check.
    assert i32(sum((-128) * (-128) for _ in range(131073))) == -2147467264
    assert i32(2147483647 + 1) == -2147483648
    assert i32(-2147483648 - 1) == 2147483647
    metadata = {'seed': SEED, 'backend': 'Python standard-library integers',
                'numpy_crosscheck_version': None if np is None else np.__version__,
                'overflow': 'wrap modulo 2^32, interpreted signed',
                'capacities': [MAX_M, MAX_N, MAX_K], 'cases': cases,
                'matrix_output_comparisons_per_configuration': sum(c['outputs'] for c in cases),
                'pe_cases': len(pe_specs)}
    (args.out / 'manifest.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    print('NumPy independent crosscheck: ' + ('unavailable; standard-library oracle used' if np is None else np.__version__))
    print(f'MODEL_PASS: {len(cases)} matrices, {metadata["matrix_output_comparisons_per_configuration"]} outputs, {len(pe_specs)} PE cases; seed={SEED}')


if __name__ == '__main__':
    main()
