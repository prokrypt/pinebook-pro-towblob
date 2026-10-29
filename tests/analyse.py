# Per phase: mean voltage/current after a 30s settle; each 328MHz phase vs the mean of its
# 856MHz neighbours (cancels the discharge drift). dI = dV / R, R = 78mOhm (pwrprof 2026-10-12 fit).
import csv, sys, statistics as st
R = 0.078
rows = list(csv.DictReader(open(sys.argv[1])))
ph = {}
for r in rows:
    ph.setdefault(int(r['phase']), []).append(r)
m = {}
for p, rs in sorted(ph.items()):
    t0 = int(rs[0]['t']); k = [r for r in rs if int(r['t']) - t0 >= 30]
    mhz = {r['mhz'] for r in rs}; bl = {r['bl'] for r in rs}
    v = st.mean(int(r['uv']) for r in k) / 1e6; i = st.mean(int(r['ua']) for r in k) / 1e6
    m[p] = (v, i)
    print(f"phase {p}: {'/'.join(sorted(mhz))}MHz  {len(k)} samples  V {v:.4f}V (sd {st.pstdev(int(r['uv']) for r in k)/1e3:.1f}mV)  gauge I {i*1000:.0f}mA ({v*i:.2f}W)  bl {'/'.join(bl)}")
print()
dvs, dis = [], []
for p in sorted(m):
    if p % 2 == 0:
        nb = [m[q] for q in (p - 1, p + 1) if q in m]
        vref = st.mean(x[0] for x in nb); iref = st.mean(x[1] for x in nb)
        dv = m[p][0] - vref; di = iref - m[p][1]
        dvs.append(dv); dis.append(di)
        print(f"328 phase {p} vs 856 neighbours: dV +{dv*1000:.1f}mV -> {dv/R*1000:.0f}mA = {dv/R*m[p][0]:.2f}W less;  gauge: {di*1000:+.0f}mA = {di*m[p][0]:+.2f}W")
v = st.mean(x[0] for x in m.values())
print(f"\nmean: voltage method {st.mean(dvs)/R*v:.2f}W saved at 328MHz, gauge {st.mean(dis)*v:+.2f}W")
