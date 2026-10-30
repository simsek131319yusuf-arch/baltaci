import sys
from PIL import Image
def comp(src, dst):
    im = Image.open(src).convert("RGBA"); W = im.width*2+30; 
    c = Image.new("RGBA", (W, im.height+20), (0,0,0,255))
    c.paste(Image.new("RGBA",(im.width+15, im.height+20),(30,25,35,255)),(0,0))
    c.paste(Image.new("RGBA",(im.width+15, im.height+20),(240,235,220,255)),(im.width+15,0))
    c.alpha_composite(im,(5,10)); c.alpha_composite(im,(im.width+20,10)); c.save(dst)
comp(sys.argv[1], sys.argv[2])
