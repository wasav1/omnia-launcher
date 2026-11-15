#!/usr/bin/env python3
"""Descarga las tipografías de la estantería desde Google Fonts a ~/.local/share/fonts/estanteria."""
import os, re, urllib.request, urllib.parse
DEST = os.path.expanduser("~/.local/share/fonts/estanteria")
FAM = {
 "Cinzel Decorative": "400;700", "Cinzel": "400;600", "Almendra": "400;700", "Uncial Antiqua": "400",
 "Marcellus SC": "400", "Metamorphous": "400", "Orbitron": "500;700",
 "Rajdhani": "500;600;700", "Hanken Grotesk": "400;500;600",
}
os.makedirs(DEST, exist_ok=True)
for fam, w in FAM.items():
    url = "https://fonts.googleapis.com/css2?family=" + urllib.parse.quote(fam).replace("%20", "+") + ":wght@" + w
    css = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "curl/8"}), timeout=30).read().decode()
    for i, u in enumerate(sorted(set(re.findall(r"url\((https://[^)]+)\)", css)))):
        ext = os.path.splitext(u)[1] or ".ttf"
        out = os.path.join(DEST, f"{fam.replace(' ', '')}-{i}{ext}")
        if not os.path.exists(out):
            open(out, "wb").write(urllib.request.urlopen(u, timeout=60).read())
    print("ok", fam)
