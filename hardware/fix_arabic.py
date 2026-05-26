fajr    = chr(1575)+chr(1604)+chr(1601)+chr(1580)+chr(1585)
shuruq  = chr(1575)+chr(1604)+chr(1588)+chr(1585)+chr(1608)+chr(1602)
dhuhr   = chr(1575)+chr(1604)+chr(1592)+chr(1607)+chr(1585)
asr     = chr(1575)+chr(1604)+chr(1593)+chr(1589)+chr(1585)
maghrib = chr(1575)+chr(1604)+chr(1605)+chr(1594)+chr(1585)+chr(1576)
isha    = chr(1575)+chr(1604)+chr(1593)+chr(1588)+chr(1575)+chr(1569)

path = "/home/sela/hub_backend/services/mawaqit_service.py"
content = open(path, encoding="utf-8").read()

import re

# Replace any run of ? chars that replaced Arabic (between quotes)
# Pattern: "??" one or more question marks inside quotes
fixes = [
    # PRAYER_NAMES list entries and all_raw tuples - replace by prayer name context
    (r'"Fajr",\s*"[^"]*"', '"Fajr",    "' + fajr + '"'),
    (r'"Sunrise",\s*"[^"]*"', '"Sunrise", "' + shuruq + '"'),
    (r'"Dhuhr",\s*"[^"]*"', '"Dhuhr",   "' + dhuhr + '"'),
    (r'"Asr",\s*"[^"]*"', '"Asr",     "' + asr + '"'),
    (r'"Maghrib",\s*"[^"]*"', '"Maghrib", "' + maghrib + '"'),
    (r'"Isha",\s*"[^"]*"', '"Isha",    "' + isha + '"'),
]

for pattern, replacement in fixes:
    content = re.sub(pattern, replacement, content)

open(path, "w", encoding="utf-8").write(content)
print("Done. Checking result:")
for line in open(path, encoding="utf-8"):
    if "Fajr" in line or "Asr" in line or "Dhuhr" in line:
        print(" ", line.rstrip())
