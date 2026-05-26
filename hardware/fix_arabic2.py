fajr    = chr(1575)+chr(1604)+chr(1601)+chr(1580)+chr(1585)
shuruq  = chr(1575)+chr(1604)+chr(1588)+chr(1585)+chr(1608)+chr(1602)
dhuhr   = chr(1575)+chr(1604)+chr(1592)+chr(1607)+chr(1585)
asr     = chr(1575)+chr(1604)+chr(1593)+chr(1589)+chr(1585)
maghrib = chr(1575)+chr(1604)+chr(1605)+chr(1594)+chr(1585)+chr(1576)
isha    = chr(1575)+chr(1604)+chr(1593)+chr(1588)+chr(1575)+chr(1569)

import re

for path in [
    "/home/sela/hub_backend/services/prayer_times.py",
    "/home/sela/hub_backend/services/mawaqit_service.py",
]:
    content = open(path, encoding="utf-8").read()
    fixes = [
        (r'"Fajr",\s*"[^"]*"',    '"Fajr",    "' + fajr    + '"'),
        (r'"Sunrise",\s*"[^"]*"', '"Sunrise", "' + shuruq  + '"'),
        (r'"Dhuhr",\s*"[^"]*"',   '"Dhuhr",   "' + dhuhr   + '"'),
        (r'"Asr",\s*"[^"]*"',     '"Asr",     "' + asr     + '"'),
        (r'"Maghrib",\s*"[^"]*"', '"Maghrib", "' + maghrib + '"'),
        (r'"Isha",\s*"[^"]*"',    '"Isha",    "' + isha    + '"'),
    ]
    for pattern, replacement in fixes:
        content = re.sub(pattern, replacement, content)
    open(path, "w", encoding="utf-8").write(content)
    print("Fixed:", path)
