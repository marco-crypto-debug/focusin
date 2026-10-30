#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
FocusIn 官網 build：site-apple（極致速度優化 + 低 GPU 佔用 + Cloudflare Pages 邊緣快取）
輸出單一自包含 HTML → source/web/site/FocusIn官網.html 及 source/web/public/index.html
"""
import re, sys, os, shutil
from urllib.parse import quote

BASE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BASE, "..", "web", "site-apple")
OUT = os.path.join(BASE, "..", "web", "site", "FocusIn官網.html")
PUBLIC_OUT = os.path.join(BASE, "..", "web", "public", "index.html")
HEADERS_OUT = os.path.join(BASE, "..", "web", "public", "_headers")

def read(p):
    with open(p, "r", encoding="utf-8") as f:
        return f.read()

def minify_css(css_text):
    # 移除註解
    css_text = re.sub(r'/\*[\s\S]*?\*/', '', css_text)
    # 壓縮空白
    css_text = re.sub(r'\s+', ' ', css_text)
    css_text = re.sub(r'\s*([\{\};:,>])\s*', r'\1', css_text)
    css_text = css_text.replace(';}', '}')
    return css_text.strip()

def minify_js(js_text):
    # 移除塊級註解
    js_text = re.sub(r'/\*[\s\S]*?\*/', '', js_text)
    # 移除純註解行與多餘空行
    lines = []
    for line in js_text.splitlines():
        s = line.strip()
        if not s or s.startswith('//'):
            continue
        lines.append(line)
    return '\n'.join(lines)

html = read(os.path.join(SRC, "index.html"))
css  = read(os.path.join(SRC, "styles.css"))
js   = read(os.path.join(SRC, "app.js"))
svg  = read(os.path.join(SRC, "assets", "focusin-icon.svg"))

# 壓縮 CSS 與 JS
min_css = minify_css(css)
min_js  = minify_js(js)

# ---------- 1. SVG → data URI ----------
svg_uri = "data:image/svg+xml," + quote(svg, safe="")

# ---------- 2. 資源內嵌 ----------
html = html.replace('<link rel="stylesheet" href="styles.css">', "")
html = html.replace('<script src="app.js"></script>', "")
html = html.replace('src="assets/focusin-icon.svg"', 'src="%s"' % svg_uri)
html = html.replace('href="assets/focusin-icon.svg"', 'href="%s"' % svg_uri)

# 插入壓縮後 <style>
style_block = "<style>\n" + min_css + "\n</style>\n"
html = html.replace("</head>", style_block + "</head>", 1)

# 插入壓縮後 <script>
script_block = "<script>\n" + min_js + "\n</script>\n"
html = html.replace("</body>", script_block + "</body>", 1)

# ---------- 3. 輸出至 site/ 及 public/ (Cloudflare Pages) ----------
for out_path in [OUT, PUBLIC_OUT]:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print("OK →", out_path)

# ---------- 4. Cloudflare Pages _headers ----------
headers_content = """/*
  X-Frame-Options: SAMEORIGIN
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()

/assets/*
  Cache-Control: public, max-age=31536000, immutable

/*.html
  Cache-Control: public, max-age=0, must-revalidate

/
  Cache-Control: public, max-age=0, must-revalidate
"""
with open(HEADERS_OUT, "w", encoding="utf-8") as f:
    f.write(headers_content)
print("OK →", HEADERS_OUT)

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

print("HTML size = %.1f KB (原始 uncompressed)" % (len(html.encode("utf-8")) / 1024))
print("剩餘外部引用:", re.findall(r'(?:src|href)="(?!data:|#|https?:|mailto:)[^"]+"', html) or "無")
