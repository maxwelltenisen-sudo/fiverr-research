import json, sys
from PIL import Image, ImageDraw
frames = json.load(open("frames.json"))
want = [float(x) for x in sys.argv[2:]] if len(sys.argv) > 2 else [f["t"] for f in frames]
frames = [f for f in frames if f["t"] in want]
W, H = 520, 300
S = 56.0
X0, Y0 = -5.2, 0.0
def lines(o):
    return [("hips","chest"),("chest","head"),("rs","re"),("re","rw"),("rw","rh"),("ls","le"),("le","lw"),("lw","lh"),
            ("rhip","rk"),("rk","ra"),("ra","rt"),("lhip","lk"),("lk","la"),("la","lt"),("rs","ls"),("rhip","lhip")]
cols = {"blue": (70,150,255), "purple": (190,90,255)}
def draw(d, o, col, ox, oy, view):
    def pt(p):
        x = p[0]; v = p[1] if view == "side" else p[2]
        sx = ox + (x - X0) * S
        sy = oy - (v * S if view == "side" else (v) * S)
        return (sx, sy)
    for a, b in lines(o):
        d.line([pt(o[a]), pt(o[b])], fill=col, width=3)
    h = pt(o["head"]); d.ellipse([h[0]-9, h[1]-9, h[0]+9, h[1]+9], outline=col, width=2)
    for k in ("rh","lh"):
        p = pt(o[k]); d.ellipse([p[0]-5, p[1]-5, p[0]+5, p[1]+5], fill=col)
cols_n = 2
rows = (len(frames) + cols_n - 1) // cols_n
img = Image.new("RGB", (W*cols_n, H*2*rows), (20,20,28))
d = ImageDraw.Draw(img)
for i, f in enumerate(frames):
    cx, cy = (i % cols_n) * W, (i // cols_n) * H * 2
    d.text((cx+6, cy+4), "t=%.2f side (X right, Y up)" % f["t"], fill=(220,220,220))
    d.line([(cx, cy+H-40), (cx+W, cy+H-40)], fill=(70,70,80))
    for who in ("blue","purple"):
        draw(d, f[who], cols[who], cx, cy+H-40, "side")
    d.text((cx+6, cy+H+4), "t=%.2f top (X right, Z down)" % f["t"], fill=(220,220,220))
    d.line([(cx, cy+H+H//2), (cx+W, cy+H+H//2)], fill=(70,70,80))
    for who in ("blue","purple"):
        # top view: z down
        o = f[who]
        def pt(p): return (cx + (p[0]-X0)*S, cy + H + H//2 + p[2]*S)
        for a, b in lines(o):
            d.line([pt(o[a]), pt(o[b])], fill=cols[who], width=3)
        h = pt(o["head"]); d.ellipse([h[0]-9,h[1]-9,h[0]+9,h[1]+9], outline=cols[who], width=2)
img.save(sys.argv[1])
print("saved", sys.argv[1], img.size)
