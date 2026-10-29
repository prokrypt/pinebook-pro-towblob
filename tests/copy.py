# 2 x 256MB copy loop for N seconds (same load as the step 5 test)
import sys, time
a = bytearray(256 << 20); b = bytearray(256 << 20); t = time.time() + float(sys.argv[1]); n = 0
while time.time() < t: b[:] = a; n += 1
print(f"{n * 256 / float(sys.argv[1]):.0f}MB/s copied")
