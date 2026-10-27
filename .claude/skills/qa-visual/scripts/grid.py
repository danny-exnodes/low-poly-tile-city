"""Usage: python3 grid.py out.png cols img1 [img2 ...]  (labels = file stems)"""
import sys
from PIL import Image, ImageDraw
out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
ims = [Image.open(f).convert('RGB') for f in files]
w = max(i.width for i in ims); h = max(i.height for i in ims)
scale = min(1.0, 1600 / (w * cols))
tw, th = int(w * scale), int(h * scale)
rows = (len(ims) + cols - 1) // cols
g = Image.new('RGB', (tw * cols, (th + 22) * rows), (30, 25, 20))
d = ImageDraw.Draw(g)
for k, (f, im) in enumerate(zip(files, ims)):
    x, y = (k % cols) * tw, (k // cols) * (th + 22)
    g.paste(im.resize((tw, th)), (x, y + 22))
    d.text((x + 6, y + 4), f.rsplit('/', 1)[-1].rsplit('.', 1)[0], fill=(240, 230, 210))
g.save(out)
print('saved', out)
