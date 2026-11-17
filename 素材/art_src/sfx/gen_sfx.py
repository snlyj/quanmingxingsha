# 程序合成的音效（V0.30）：numpy 生成，无外部素材
import numpy as np, wave, subprocess, os
SR = 22050
OUT = "/workspace/newproj/proj/game/assets/sfx"
rng = np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def env(n, a=0.005, r=None):
    e = np.ones(n); na = max(1,int(SR*a)); e[:na] = np.linspace(0,1,na)
    if r is None: r = n/SR
    e *= np.exp(-np.arange(n)/(SR*r/5)); return e
def bell(f, d, r=None, h=(1,0.5,0.25)):
    x=t(d); s=sum(a*np.sin(2*np.pi*f*(i+1)*x) for i,a in enumerate(h)); return s*env(len(x), r=r or d)
def noise(d): return rng.standard_normal(int(SR*d))
def lp(x, k):  # 简单一阶低通
    y=np.zeros_like(x); a=k
    for i in range(1,len(x)): y[i]=y[i-1]+a*(x[i]-y[i-1])
    return y
def mix(*parts):
    n=max(int(SR*off)+len(p) for off,p in parts); y=np.zeros(n)
    for off,p in parts:
        o=int(SR*off); y[o:o+len(p)]+=p
    return y
def save(name, y, gain=0.8):
    y = y/ (np.max(np.abs(y))+1e-9) * gain
    pcm=(y*32767).astype(np.int16); wp=f"/tmp/{name}.wav"
    with wave.open(wp,"wb") as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg","-loglevel","error","-nostdin","-y","-i",wp,"-c:a","libvorbis","-q:a","3",f"{OUT}/{name}.ogg"],check=True)
x=t(0.06); save("click", np.sin(2*np.pi*(900-3000*x)*x)*env(len(x),r=0.06), 0.5)
n=noise(0.14); save("card", lp(n,0.35)*np.hanning(len(n)), 0.45)
save("play", mix((0,bell(660,0.25)),(0.06,bell(990,0.3))), 0.55)
x=t(0.3); thump=np.sin(2*np.pi*(150*np.exp(-x*8))*x*3)*env(len(x),r=0.3); save("hit", mix((0,thump),(0,lp(noise(0.12),0.2)*env(int(SR*0.12),r=0.12)*0.6)), 0.85)
n=noise(0.28); k=np.linspace(0.05,0.6,len(n)); y=np.zeros_like(n)
for i in range(1,len(n)): y[i]=y[i-1]+k[i]*(n[i]-y[i-1])
save("dodge", y*np.hanning(len(n)), 0.5)
save("heal", mix(*[(i*0.08,bell(f,0.45,h=(1,0.3))) for i,f in enumerate([523,659,784,1047])]), 0.55)
n=noise(0.07); save("draw", lp(n,0.5)*env(len(n),r=0.07), 0.35)
save("turn", mix((0,bell(784,0.5,h=(1,0.4,0.2))),(0.0,bell(1175,0.5,h=(0.5,)))), 0.45)
save("skill", mix(*[(i*0.04,bell(f,0.3,h=(1,))) for i,f in enumerate([1319,1568,1760,2093,2637])]), 0.45)
save("win", mix(*[(i*0.14,bell(f,0.7 if i<4 else 1.2,h=(1,0.5,0.3))) for i,f in enumerate([523,659,784,1047,1319])]), 0.7)
save("lose", mix(*[(i*0.22,bell(f,0.8,h=(1,0.6))) for i,f in enumerate([494,440,392,330])]), 0.6)
x=t(0.18); hb=np.sin(2*np.pi*60*x)*env(len(x),r=0.18); save("dying", mix((0,hb),(0.25,hb*0.8)), 0.8)
print(sorted(os.listdir(OUT)))
