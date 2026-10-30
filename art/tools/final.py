import os, json, numpy as np
from PIL import Image, ImageDraw
SP='../sprites/'; man={}
def piv(im,kind):
    a=np.array(im)[...,3]; yb=np.where(a.max(1)>128)[0].max(); xs=np.where(a[max(0,yb-4):yb+1].max(0)>128)[0]
    return [round((xs.min()+xs.max())/2),int(yb)]
notes={'cat':'Pipsy; pivot=feet center; idle/swing share canvas','trees':'pivot=root bottom-center; _1.._3 progressive axe notch derived from _0','axe':'pivot=handle end','bg':'parallax layer','fx':'particle','ui':'icon/panel'}
files=[]
for d,_,fs in os.walk(SP):
    for f in fs:
        if f.endswith('.png'): files.append(os.path.join(d,f))
bad=[]
for p in sorted(files):
    i=os.path.relpath(p,SP).replace(os.sep,'/')[:-4]; im=Image.open(p)
    with open(p,'rb') as fh: ct=fh.read(26)[25]
    if ct!=6: bad.append(i)
    k=i.split('/')[0]; n=notes.get(k,'')
    pv=[im.width//2,im.height]
    if k in('cat','trees') or i=='axe': pv=piv(im,k)
    if k=='bg': pv=[0,0]
    man[i]={'w':im.width,'h':im.height,'pivot':pv,'notes':n+(' (tileable horizontally, ~220px crossfade)' if i in('bg/far','bg/mid','bg/ground') else '')}
json.dump(man,open('../manifest.json','w'),indent=1); print(len(man),'alpha-bad',bad)
# contact sheet
cells=[(i,Image.open(SP+i+'.png').convert('RGBA')) for i in man]
S=0.5; th=[]
for i,im in cells:
    f=min(1,(300 if not i.startswith('bg') else 360)/im.width, 260/im.height) if i!='bg/sky' else 360/im.width
    th.append((i,im.resize((max(1,int(im.width*f)),max(1,int(im.height*f))),Image.LANCZOS)))
W=1700; x=y=10; rowh=0; pos=[]
for i,t in th:
    if x+t.width+10>W: x=10; y+=rowh+30; rowh=0
    pos.append((i,t,x,y)); x+=t.width+20; rowh=max(rowh,t.height)
c=Image.new('RGBA',(W,y+rowh+40),(128,128,128,255)); d=ImageDraw.Draw(c)
for i,t,x,y in pos: c.alpha_composite(t,(x,y)); d.text((x,y+t.height+4),i,fill=(0,0,0,255))
c.save('../contact_sheet.png'); print(c.size)
