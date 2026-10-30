import sys
from PIL import Image
n=sys.argv[1]; names=[f'{n}_{s}' for s in ('0','1','2','3','stump')]
ims=[Image.open(f'../sprites/trees/{x}.png') for x in names]
W=sum(i.width for i in ims)+20*(len(ims)+1); c=Image.new('RGBA',(W,max(i.height for i in ims)+20),(150,200,220,255)); x=20
for i in ims: c.alpha_composite(i,(x,c.height-i.height-10)); x+=i.width+20
c.save(f'../raw/chk_{n}.png')
