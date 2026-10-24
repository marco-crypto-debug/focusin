#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FocusIn 官網 build：site-apple（內容 + Live demo + FocusIn Red 原生色板）
輸出單一自包含 HTML → source/web/site/FocusIn官網.html 及 source/web/public/index.html (供 Cloudflare Pages)
"""
import re, sys, os, shutil
from urllib.parse import quote

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "..", "web", "site-apple")
OUT = os.path.join(BASE, "..", "web", "site", "FocusIn官網.html")
PUBLIC_OUT = os.path.join(BASE, "..", "web", "public", "index.html")

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

html = read(os.path.join(SRC, "index.html"))
css  = read(os.path.join(SRC, "styles.css"))
js   = read(os.path.join(SRC, "app.js"))
svg  = read(os.path.join(SRC, "assets", "focusin-icon.svg"))

# ---------- 1. SVG → data URI ----------
svg_uri = "data:image/svg+xml," + quote(svg, safe="")

# ---------- 2. 資源內嵌（styles.css 已原生同步 FocusIn #D71920 品牌色系） ----------
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

# ---------- 3. 輸出至 site/ 及 public/ (Cloudflare Pages) ----------
for out_path in [OUT, PUBLIC_OUT]:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print("OK →", out_path)

# 同步複製 static assets 至 public/
assets_src = os.path.join(SRC, "assets")
assets_dst = os.path.join(BASE, "..", "web", "public", "assets")
if os.path.exists(assets_src):
    os.makedirs(assets_dst, exist_ok=True)
    for item in os.listdir(assets_src):
        s = os.path.join(assets_src, item)
        d = os.path.join(assets_dst, item)
        if os.path.isfile(s):
            shutil.copy2(s, d)
    print("Assets synced to", assets_dst)

print("size = %.1f KB" % (len(html.encode("utf-8")) / 1024))
print("剩餘外部引用:", re.findall(r'(?:src|href)="(?!data:|#|https?:|mailto:)[^"]+"', html) or "無")

