import urllib.request, json, re

url = "https://mawaqit.net/api/2.0/mosque/search?lat=48.8566&lon=2.3522&word="
req = urllib.request.Request(url, headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req, timeout=10) as r:
    mosques = json.loads(r.read())
print(f"Found {len(mosques)} mosques")
for m in mosques[:3]:
    print(f"  - {m['name']} (slug: {m['slug']})")

slug = mosques[0]["slug"]
url2 = f"https://mawaqit.net/fr/{slug}"
req2 = urllib.request.Request(url2, headers={"Accept": "application/json", "User-Agent": "Mozilla/5.0"})
with urllib.request.urlopen(req2, timeout=10) as r:
    html = r.read().decode()

m = re.search(r"confData\s*=\s*(\{.*?\});", html, re.DOTALL)
if m:
    data = json.loads(m.group(1))
    print(f"\nMosque: {data.get('name')}")
    print(f"Times today: {data.get('times')}")
    print(f"Timezone: {data.get('timezone')}")
else:
    print("confData not found")
    print(html[:300])
