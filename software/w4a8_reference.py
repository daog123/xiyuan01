"""Integer reference for signed INT8 x packed signed INT4 with group UQ4.12 scales."""

def signed_nibble(value):
    value &= 0xF
    return value - 16 if value & 8 else value


def gemm(a, packed_w, sx, sw, m, n, k, group_size=32):
    groups = (k + group_size - 1) // group_size
    out = [[0] * n for _ in range(m)]
    for i in range(m):
        for j in range(n):
            accum = 0
            for g in range(groups):
                psum = 0
                start, end = g * group_size, min(k, (g + 1) * group_size)
                for kk in range(start, end):
                    byte = packed_w[j][kk // 2]
                    weight = signed_nibble(byte >> (4 if kk & 1 else 0))
                    psum = (psum + int(a[i][kk]) * weight) & 0xFFFFFFFF
                psum = psum - (1 << 32) if psum & (1 << 31) else psum
                accum += psum * int(sx[i][g]) * int(sw[g][j])
            accum &= 0xFFFFFFFFFFFFFFFF
            if accum & (1 << 63):
                accum -= 1 << 64
            value = ((abs(accum) + 128) >> 8) * (-1 if accum < 0 else 1)
            out[i][j] = max(-(1 << 31), min((1 << 31) - 1, value))
    return out
