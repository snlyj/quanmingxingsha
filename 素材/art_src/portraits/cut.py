from rembg import remove, new_session
from PIL import Image
import sys
s=new_session('isnet-anime')
for line in open('src.txt'):
    k,p=line.strip().split('|')
    im=Image.open(p).convert('RGB')
    cut=remove(im,session=s)  # RGBA
    a=cut.getchannel('A')
    # 清理低 alpha 噪点
    a=a.point(lambda v: 0 if v<16 else v)
    cut.putalpha(a)
    bb=a.getbbox()
    fig=cut.crop(bb)
    old=Image.open('/tmp/old_pt/%s.png'%k).getchannel('A').getbbox()
    th=old[3]-old[1]
    sc=th/fig.height
    nw=int(fig.width*sc)
    if nw>800:
        sc=800/fig.width; nw=800
    fig=fig.resize((nw,int(fig.height*sc)),Image.LANCZOS)
    cx=(old[0]+old[2])//2
    x=max(0,min(825-nw,cx-nw//2))
    y=old[3]-fig.height
    canvas=Image.new('RGBA',(825,1050),(0,0,0,0))
    canvas.alpha_composite(fig,(x,max(0,y)))
    canvas.save('%s.png'%k,optimize=True)
    print(k,bb,fig.size,(x,y))
