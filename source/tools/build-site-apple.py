#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FocusIn 官網 build：site-apple（內容+Live demo）+ Apple 藍白風格
輸出單一自包含 HTML → source/web/site/FocusIn官網.html
"""
import re, sys, os
from urllib.parse import quote

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "..", "web", "site-apple")
OUT = os.path.join(BASE, "..", "web", "site", "FocusIn官網.html")

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

html = read(os.path.join(SRC, "index.html"))
css  = read(os.path.join(SRC, "styles.css"))
js   = read(os.path.join(SRC, "app.js"))
svg  = read(os.path.join(SRC, "assets", "focusin-icon.svg"))

# ---------- 1. SVG → data URI ----------
svg_uri = "data:image/svg+xml," + quote(svg, safe="")

# ---------- 2. 色板 Apple 化（粉紅 → Apple 藍系） ----------
css = css.replace("--accent: #e0416a;", "--accent: #0071e3;")
css = css.replace("--accent-soft: #ff6b8a;", "--accent-soft: #3395ff;")
css = css.replace("--accent-deep: #c22d55;", "--accent-deep: #0058b0;")
css = css.replace("--violet: #8b3dff;", "--violet: #5e5ce6;")
# text-gradient 主漸變
css = css.replace(
    "linear-gradient(100deg, #ff7c99 0%, #e0416a 34%, #b03cf0 68%, #5b7cff 100%)",
    "linear-gradient(100deg, #4a90ff 0%, #0071e3 34%, #5e5ce6 68%, #7c5bff 100%)")
# hero orbs
css = css.replace("rgba(255, 122, 153, 0.36)", "rgba(0, 113, 227, 0.30)")
css = css.replace("rgba(139, 61, 255, 0.24)", "rgba(94, 92, 230, 0.22)")
# demo glow / 深色區 glow
css = css.replace("rgba(224, 65, 106, 0.28), rgba(139, 61, 255, 0.14) 48%, transparent 70%",
                  "rgba(0, 113, 227, 0.26), rgba(94, 92, 230, 0.14) 48%, transparent 70%")
css = css.replace("rgba(224, 65, 106, 0.26), rgba(139, 61, 255, 0.12) 48%, transparent 72%",
                  "rgba(0, 113, 227, 0.24), rgba(94, 92, 230, 0.12) 48%, transparent 72%")
# teacher-window / 粉紅漸變條 → 藍
css = css.replace("linear-gradient(180deg, #ff708f, var(--accent))",
                  "linear-gradient(180deg, #4a90ff, var(--accent))")
# sparkline 藍
css = css.replace("#ff6b8a", "#0071e3")
css = css.replace("#e0416a", "#0071e3")
css = css.replace("#c22d55", "#0058b0")

# ---------- 3. HTML 內部色板 ----------
html = html.replace('stop-color="#ff6b8a"', 'stop-color="#0071e3"')
html = html.replace('stroke="#ff6b8a"', 'stroke="#0071e3"')

# ---------- 4. 資源內嵌 ----------
html = html.replace('<link rel="stylesheet" href="styles.css">', "")
html = html.replace('<script src="app.js"></script>', "")
html = html.replace('src="assets/focusin-icon.svg"', 'src="%s"' % svg_uri)
html = html.replace('href="assets/focusin-icon.svg"', 'href="%s"' % svg_uri)

# 插入 <style>
style_block = "<style>\n" + css + "\n</style>\n"
html = html.replace("</head>", style_block + "</head>", 1)

# 插入 <script>
script_block = "<script>\n" + js + "\n</script>\n"
html = html.replace("</body>", script_block + "</body>", 1)

# ---------- 5. 輸出 ----------
os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    f.write(html)

print("OK →", OUT)
print("size = %.1f KB" % (len(html.encode("utf-8")) / 1024))
print("剩餘外部引用:", re.findall(r'(?:src|href)="(?!data:|#|https?:|mailto:)[^"]+"', html) or "無")
