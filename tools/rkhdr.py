#!/usr/bin/env python3
# Decode a Rockchip idblock (rksd or rkspi) header; optionally de-stride rkspi and dump TPL/SPL parts.
import sys, struct
KEY = bytes([124,78,3,4,85,5,9,7,45,44,123,56,23,13,23,17])
def rc4(data):
    S = list(range(256)); j = 0
    for i in range(256):
        j = (j + S[i] + KEY[i % 16]) & 255; S[i], S[j] = S[j], S[i]
    i = j = 0; out = bytearray()
    for b in data:
        i = (i + 1) & 255; j = (j + S[i]) & 255; S[i], S[j] = S[j], S[i]
        out.append(b ^ S[(S[i] + S[j]) & 255])
    return bytes(out)
path, kind = sys.argv[1], sys.argv[2]
raw = open(path, 'rb').read()
if kind == 'spi':   # 2KB of data per 4KB page
    raw = b''.join(raw[i:i+2048] for i in range(0, min(len(raw), 0x100000), 4096))
h = rc4(raw[:512])
magic, = struct.unpack_from('<I', h, 0)
disable_rc4, = struct.unpack_from('<I', h, 8)
init_offset, = struct.unpack_from('<H', h, 12)
init_size, init_boot_size = struct.unpack_from('<HH', h, 506)
print(f'magic {magic:#010x} ({"OK" if magic == 0x0ff0aa55 else "BAD"}) disable_rc4 {disable_rc4} init_offset {init_offset} '
      f'init_size {init_size} sectors ({init_size*512} B) init_boot_size {init_boot_size} sectors ({init_boot_size*512} B)')
d = raw[init_offset*512:]
print('first 4 bytes of init code:', d[:4])
if len(sys.argv) > 3:
    open(sys.argv[3] + '.tpl', 'wb').write(d[:init_size*512])
    open(sys.argv[3] + '.spl', 'wb').write(d[init_size*512:init_boot_size*512])
