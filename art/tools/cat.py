import sys; sys.path.insert(0,'.')
from key import key
from PIL import Image
A,_=key(Image.open('../raw/pipsy_ref.png')); B,_=key(Image.open('../raw/swing_gen.png'))
bbs=[x.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox() for x in (A,B)]
# union, but vertical bottom from feet (idle) -- use union anyway
l=min(b[0] for b in bbs);t=min(b[1] for b in bbs);r=max(b[2] for b in bbs);bt=max(b[3] for b in bbs)
H=bt-t; f=262/H; pad=4
for im,n in ((A,'idle'),(B,'swing')):
    c=im.crop((l,t,r,bt)); c=c.resize((round(c.width*f),round(c.height*f)),Image.LANCZOS)
    o=Image.new('RGBA',(c.width+8,c.height+8)); o.paste(c,(4,4)); o.save(f'../sprites/cat/{n}.png'); print(n,o.size)
