import urllib.request, json, re

slug = "grande-mosquee-de-paris"
url = f"https://mawaqit.net/fr/{slug}"
req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req, timeout=10) as r:
    html = r.read().decode()

m = re.search(r"confData\s*=\s*(\{.*?\});", html, re.DOTALL)
data = json.loads(m.group(1))
# Print all keys
for k, v in data.items():
    print(f"{k}: {json.dumps(v, ensure_ascii=False)[:120]}")
