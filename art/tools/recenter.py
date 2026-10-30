import sys, numpy as np
from PIL import Image
for p in sys.argv[1:]:
    im=Image.open(p).convert('RGBA'); a=np.array(im)[...,3]
    ys=np.where(a.max(1)>128)[0]; yb=ys.max(); rows=a[max(0,yb-4):yb+1]
    xs=np.where(rows.max(0)>128)[0]; cx=(xs.min()+xs.max())/2
    W=im.width; L=cx; Rr=W-cx; m=max(L,Rr); nw=int(round(2*m))
    o=Image.new('RGBA',(nw,im.height)); o.paste(im,(int(round(m-L)),0)); o.save(p); print(p,(W,im.height),'->',o.size,'cx',cx)
