"""Chroma key: python -I key.py in.png out.png [maxh] [pad] [t0] [t1]
Samples bg colour from border median; border-connected flood + soft edge + unmix despill; trims; resizes to maxh."""
import sys, numpy as np
from PIL import Image
from scipy import ndimage as ndi

def key(im, t0=34, t1=80, bgc=None):
    a = np.asarray(im.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    border = np.concatenate([a[:6].reshape(-1,3), a[-6:].reshape(-1,3), a[:,:6].reshape(-1,3), a[:,-6:].reshape(-1,3)])
    bg = np.median(border, axis=0) if bgc is None else np.array(bgc,np.float32)
    d = np.sqrt(((a - bg) ** 2).sum(-1))
    cand = d < t1
    lab, n = ndi.label(cand)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:,0], lab[:,-1]]))) - {0}
    isbg = np.isin(lab, list(edge)) if edge else np.zeros_like(cand)
    isbg |= d < t0   # enclosed holes of clearly-bg colour
    # opaque everywhere except bg; soft ramp on pixels adjacent to bg
    alpha = np.ones((h, w), np.float32)
    alpha[isbg & (d < t0)] = 0
    ring = ndi.binary_dilation(isbg, iterations=2) & ~(isbg & (d < t0))
    ramp = np.clip((d - t0) / (t1 - t0), 0, 1)
    alpha[ring] = ramp[ring]
    alpha[isbg & (d >= t0) & ~ring] = ramp[isbg & (d >= t0) & ~ring]
    # unmix despill
    af = np.maximum(alpha, 0.05)[..., None]
    fg = (a - (1 - alpha)[..., None] * bg) / af
    fg = np.clip(fg, 0, 255)
    out = np.where(alpha[..., None] > 0.98, a, fg)
    # drop tiny specks
    m = alpha > 0.1
    lab2, n2 = ndi.label(m)
    if n2 > 1:
        sizes = ndi.sum(m, lab2, range(1, n2 + 1))
        keep = np.isin(lab2, [i + 1 for i, s in enumerate(sizes) if s >= max(30, sizes.max() * 0.002)])
        alpha = np.where(keep, alpha, 0)
    rgba = np.dstack([out, alpha * 255]).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA"), bg

def trim(im, pad):
    bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    im = im.crop(bb)
    c = Image.new("RGBA", (im.width + 2*pad, im.height + 2*pad), (0,0,0,0))
    c.paste(im, (pad, pad)); return c

if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    maxh = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    pad = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    t0 = float(sys.argv[5]) if len(sys.argv) > 5 else 34
    t1 = float(sys.argv[6]) if len(sys.argv) > 6 else 80
    im, bg = key(Image.open(src), t0, t1)
    im = trim(im, pad)
    if maxh and im.height > maxh:
        im = im.resize((round(im.width * maxh / im.height), maxh), Image.LANCZOS)
    im.save(dst); print(dst, im.size, "bg", bg.astype(int))
