import sys, numpy as np, json
sys.path.insert(0,'.')
from key import key
from PIL import Image
from scipy import ndimage as ndi
R='../raw/'; SP='../sprites/'
def bbox(im): return im.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox()
def keyed(n,top=False,**k):
    src=Image.open(R+n+'_gen.png')
    bgc=np.median(np.asarray(src.convert('RGB'))[:8].reshape(-1,3),axis=0) if top else None
    im,_=key(src,bgc=bgc,**k); return im
def padto(im,pad=4):
    im=im.crop(bbox(im)); o=Image.new('RGBA',(im.width+2*pad,im.height+2*pad)); o.paste(im,(pad,pad)); return o
def fit(im,maxdim,pad=4):
    im=im.crop(bbox(im)); f=maxdim/max(im.size); im=im.resize((max(1,round(im.width*f)),max(1,round(im.height*f))),Image.LANCZOS); return padto(im,pad)
def parts(im,n,dil=25):
    m=np.array(im.getchannel('A'))>20
    lab,k=ndi.label(ndi.binary_dilation(m,iterations=dil))
    lab=np.where(m,lab,0)
    objs=[]
    for i in range(1,k+1):
        mm=lab==i
        if mm.sum()<500: continue
        ys,xs=np.where(mm); a=np.array(im); a[...,3]=np.where(mm,a[...,3],0)
        objs.append((xs.min(),Image.fromarray(a)))
    objs.sort(key=lambda t:t[0]); print('parts',len(objs)); return [o[1] for o in objs]
def despill(im):
    a=np.array(im).astype(np.int32); e=a[...,3]>=0
    r=a[...,0]; lim=np.maximum(a[...,1],a[...,2]); a[...,0]=np.where(e&(r>lim),lim,r)
    return Image.fromarray(a.astype(np.uint8))
def tile(im,b=220):
    a=np.array(im).astype(np.float32); a[...,:3]*=a[...,3:]/255.0; W=a.shape[1]; o=a[:,:W-b].copy()
    t=(np.arange(b)/b)[None,:,None]
    o[:,:b]=a[:,W-b:]*(1-t)+a[:,:b]*t
    al=o[...,3:]; o[...,:3]=np.where(al>0,o[...,:3]/np.maximum(al,1)*255.0,0)
    return Image.fromarray(np.clip(o,0,255).astype(np.uint8))
def save(im,path): im.save(SP+path+'.png'); print(path,im.size)
if __name__!='__main__' : sys.exit
what=sys.argv[1]
if what=='axe': save(fit(keyed('axe'),150),'axe')
if what=='fx':
    p=parts(keyed('fx'),3)
    for im,n,d in zip(p,('chip','leaf','log'),(48,40,96)): save(fit(im,d),'fx/'+n)
if what=='ui':
    src=Image.open(R+'ui_gen.png').convert('RGB'); k=2752/2000; p=[]
    for x0 in (82,561,1040,1519):
        t=src.crop((int((x0+5)*k),int(362*k),int((x0+395)*k),int(752*k)))
        im,_=key(t,t0=30,t1=70); p.append(im)
    for im,n in zip(p,('coin','log','clock','chain')):
        im=fit(im,120,4); o=Image.new('RGBA',(128,128)); o.paste(im,((128-im.width)//2,(128-im.height)//2)); save(o,'ui/'+n)
if what=='panel':
    im=padto(keyed('panel'),0); f=256/im.width; save(im.resize((256,round(im.height*f)),Image.LANCZOS),'ui/panel')
if what=='sky':
    im=Image.open(R+'sky_gen.png').convert('RGB'); w,h=im.size; ch=w*9//16
    if ch>h: im=im.crop((0,0,w,h)).resize((1600,900),Image.LANCZOS)
    else:
        t=(h-ch)//2; im=im.crop((0,t,w,t+ch)).resize((1600,900),Image.LANCZOS)
    save(im.convert('RGBA'),'bg/sky')
if what in('far','mid'):
    im=padto(keyed(what,top=True),0); W=1600+220; f=W/im.width; im=im.resize((W,round(im.height*f)),Image.LANCZOS)
    save(tile(despill(im)),'bg/'+what)
if what=='ground':
    im=Image.open(R+'ground_gen.png').convert('RGB'); y0=int(365*1.584); im=im.crop((0,y0,im.width,y0+int(262*1.584)*1))
    a=np.array(im).astype(int); sat=a.max(-1)-a.min(-1); chk=(sat<22)&(a.min(-1)>150)
    chk=ndi.binary_opening(chk,iterations=1); al=np.where(chk,0,255).astype(np.uint8)
    al=np.array(Image.fromarray(al).filter(__import__('PIL.ImageFilter',fromlist=['x']).GaussianBlur(0.8)))
    rgba=Image.fromarray(np.dstack([a.astype(np.uint8),al]),'RGBA')
    W=1600+220; f=W/rgba.width; rgba=rgba.resize((W,round(rgba.height*f)),Image.LANCZOS); print(rgba.size)
    save(tile(rgba),'bg/ground')

if what=='emotes':
    p=parts(keyed('emotes'),3,dil=12)
    for im,n in zip(p,('happy','cry','wow')): save(fit(im,128,0),'ui/pipsy_'+n)
