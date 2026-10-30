import sys, numpy as np, math, random
sys.path.insert(0,'.')
from key import key
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage as ndi
H=420
YF={'kavak':0.13,'cam':0.13,'ladin':0.04}
SF={'kavak':0.2,'cam':0.2,'ladin':0.075}
INNER={'kavak':(236,196,128),'cam':(244,190,120),'ladin':(236,190,120)}
def largest(im):
    a=np.array(im); m=a[...,3]>10
    lab,n=ndi.label(m)
    if n>1:
        s=ndi.sum(m,lab,range(1,n+1)); k=1+int(np.argmax(s))
        a[...,3]=np.where(lab==k,a[...,3],0)
    return Image.fromarray(a)
def recenter(im):
    a=np.array(im)[...,3]; yb=np.where(a.max(1)>128)[0].max(); rows=a[max(0,yb-4):yb+1]
    xs=np.where(rows.max(0)>128)[0]; cx=(xs.min()+xs.max())/2; W=im.width; m=max(cx,W-cx); o=Image.new('RGBA',(int(round(2*m)),im.height)); o.paste(im,(int(round(m-cx)),0)); return o
def make0(n):
    im,_=key(Image.open(f'../raw/{n}_gen.png')); im=largest(im)
    bb=im.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox(); im=im.crop(bb)
    f=H/im.height; im=im.resize((round(im.width*f),H),Image.LANCZOS)
    o=Image.new('RGBA',(im.width+8,H+8)); o.paste(im,(4,4)); return recenter(o)
def trunk_span(a,y,br=False):
    m=a[y,:,3]>128
    if br: m=m&(a[y,:,0].astype(int)>a[y,:,1].astype(int)+20)
    cols=np.where(m)[0]; return cols.min(),cols.max()
def damage(im,n,stage):
    S=4; W,Hh=im.size
    big=im.resize((W*S,Hh*S),Image.LANCZOS); a=np.array(big)
    WOOD=(236,176,98); DEEP=(176,104,52); dark=(66,34,20,255)
    ycen=int((Hh-4-YF[n]*H)*S)
    br=(n=='ladin')
    xl,xr=trunk_span(a,ycen,br); tw=xr-xl
    inside=a[...,3]>128
    if br: inside=trunkmask(a)
    ol=Image.new('RGBA',big.size,(0,0,0,0)); od=ImageDraw.Draw(ol)
    random.seed(stage*11+len(n))
    def notch(side,yc,depth,sc):
        # side=+1 left bite, -1 right bite
        x0=xl if side>0 else xr; ex=-14*S*side
        tipx=x0+side*depth*tw; up=max(depth*tw*0.95,(0.03+0.012*stage)*H*S*(0.35 if n=='ladin' else 1))*sc; dn=up*0.22
        P=[(x0+ex,yc-up),(tipx,yc),(x0+ex,yc+dn)]
        f=Image.new('L',big.size,0); ImageDraw.Draw(f).polygon(P,fill=255)
        m=(np.array(f)>0)&inside
        yy,xx=np.indices(m.shape)
        t=np.clip(np.abs(xx-x0)/max(1,depth*tw),0,1)
        for c in range(3):
            col=(WOOD[c]*(1-t)+DEEP[c]*t)
            a[...,c]=np.where(m,col.astype(np.uint8),a[...,c])
        # shadow strip under the upper edge
        od.line([P[0],P[1]],fill=dark,width=int(2.6*S)); od.line([P[1],P[2]],fill=dark,width=int(2.2*S))
        return P
    depth=[0,0.40,0.62,0.82][stage]
    tipL=notch(1,ycen,depth,1.0)[1]
    if stage>=3 and n!='ladin':
        notch(-1,ycen-int(0.09*H*S),0.3,0.8)
    ncr=[0,2,4,6][stage]; ytop=int(Hh*S*0.62)
    for i in range(ncr):
        up=1 if i%2==0 else -1
        x,y=tipL[0]+random.uniform(0,0.15)*tw, tipL[1]+up*random.uniform(0,3)*S
        pl=[(x,y)]
        for k in range(2):
            x+=random.uniform(0.05,0.18)*tw; y+=up*random.uniform(0.012,0.024)*H*S; pl.append((x,y))
        od.line(pl,fill=dark,width=int(1.4*S),joint='curve')
    out=Image.fromarray(a)
    la=np.array(ol); la[...,3]=np.where(inside,la[...,3],0); ol=Image.fromarray(la)
    out=Image.alpha_composite(out,ol)
    return out.resize((W,Hh),Image.LANCZOS)
def trunkmask(a):
    br=(a[...,3]>128)&(a[...,0].astype(int)>a[...,1].astype(int)+20)
    e=ndi.binary_erosion(br,iterations=2); lab,k=ndi.label(e)
    yb=np.where(a[...,3].max(1)>128)[0].max(); xs=np.where(e[yb-8])[0]
    l=lab[yb-8,xs[len(xs)//2]] if len(xs) else 0
    return ndi.binary_dilation(lab==l,iterations=2)&br
def stump_ladin(im):
    a=np.array(im); br=trunkmask(a)
    ys,xs=np.where(br); y0=ys.min(); crop=a.copy(); crop[~br]=0
    c=Image.fromarray(crop).crop((0,y0,im.width,im.height)); bb=c.getchannel('A').getbbox(); c=c.crop(bb)
    c=c.resize((round(c.width*1.25),round(c.height*2.6)),Image.LANCZOS)
    W,Hh=c.size; S=4; big=c.resize((W*S,Hh*S),Image.LANCZOS); al=big.getchannel('A').filter(ImageFilter.MedianFilter(15)).filter(ImageFilter.GaussianBlur(3)).point(lambda v:255 if v>128 else 0).filter(ImageFilter.GaussianBlur(1.2)); big.putalpha(al); arr=np.array(big)
    cy=int(0.3*Hh*S); cols=np.where(arr[cy+4*S,:,3]>128)[0]; xl,xr=cols.min(),cols.max(); arr[:cy,:,3]=0; big=Image.fromarray(arr); d=ImageDraw.Draw(big)
    cx=(xl+xr)/2; rw=(xr-xl)/2+2*S; rh=rw*0.38
    d.ellipse([cx-rw,cy-rh,cx+rw,cy+rh],fill=INNER['ladin']+(255,),outline=(66,34,20,255),width=3*S)
    for k in (0.65,0.38,0.14): d.ellipse([cx-rw*k,cy-rh*k,cx+rw*k,cy+rh*k],outline=(150,95,55,255),width=2*S)
    out=big.resize((W,Hh),Image.LANCZOS); out=out.crop(out.getchannel('A').getbbox()); out=out.resize((round(out.width*96/out.height),96),Image.LANCZOS)
    o=Image.new('RGBA',(out.width+8,out.height+8)); o.paste(out,(4,4)); return recenter(o)
def stump(im,n):
    if n=='ladin': return stump_ladin(im)
    # derive: take bottom 20% of tree trunk, flat-cut top with ring ellipse
    W,Hh=im.size; a=np.array(im)
    cut=Hh-4-int(SF[n]*H); crop=im.crop((0,cut-4,W,Hh))
    ca=np.array(crop); ca[:6,:,3]=0
    # find trunk columns at top row
    top=6; cols=np.where(ca[top,:,3]>128)[0]
    xl,xr=cols.min(),cols.max(); S=4
    big=crop.resize((crop.width*S,crop.height*S),Image.LANCZOS)
    inner=INNER[n]; ring=(150,95,55)
    d=ImageDraw.Draw(big); cx=(xl+xr)/2*S; rw=(xr-xl)/2*S+2*S; rh=rw*0.38; cy=top*S
    # clear above cut
    arr=np.array(big); arr[:int(cy),:,3]=0; big=Image.fromarray(arr); d=ImageDraw.Draw(big)
    d.ellipse([cx-rw,cy-rh,cx+rw,cy+rh],fill=inner+(255,),outline=(70,38,22,255),width=3*S)
    for k in (0.65,0.38,0.14):
        d.ellipse([cx-rw*k,cy-rh*k,cx+rw*k,cy+rh*k],outline=ring+(255,),width=2*S)
    out=big.resize(crop.size,Image.LANCZOS); bb=out.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
    out=out.crop(bb); o=Image.new('RGBA',(out.width+8,out.height+8)); o.paste(out,(4,4)); return recenter(o)
if __name__=='__main__':
    for n in sys.argv[1:]:
        im=make0(n); im.save(f'../sprites/trees/{n}_0.png'); print(n,im.size)
        for s in (1,2,3): damage(im,n,s).save(f'../sprites/trees/{n}_{s}.png')
        stump(im,n).save(f'../sprites/trees/{n}_stump.png')
