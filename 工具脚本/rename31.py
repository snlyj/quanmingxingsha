import os,re,sys
ROOT='/workspace/newproj/proj'
REPL=[
 ("初音岛 D.C. ~Da Capo~","星樱坂学园"),("《初音岛》","《星樱坂学园》"),("初音岛","星樱坂学园"),
 ("芳乃樱","花宫雏"),("朝仓音梦","柚木铃奈"),("白河小鸟","宫坂歌织"),("天枷美春","森崎千夏"),
 ("水越萌","夜宫静羽"),("水越真子","绯山响"),("鹭泽赖子","藤代小梅"),
 ("不凋樱","花愈"),("读心","心曲"),("发条","不屈"),("香蕉动力","元气补给"),("入梦","星眠"),("锅物","茶会"),
 ("budiao","huayu"),("duxin","xinqu"),("fatiao","buqu"),("xiangjiao","yuanqi"),("rumeng","xingmian"),("guowu","chahui"),
 ("音梦","铃奈"),("美春","千夏"),("赖子","小梅"),("真子","响"),
]
n=0
for dp,dn,fn in os.walk(ROOT):
    if '.godot' in dp or '/.git' in dp: continue
    for f in fn:
        if not f.endswith(('.gd','.md','.cfg','.tscn','.txt','.sh','.py','.json')): continue
        p=os.path.join(dp,f); s=open(p,encoding='utf-8').read(); o=s
        for a,b in REPL: s=s.replace(a,b)
        if s!=o: open(p,'w',encoding='utf-8').write(s); n+=1; print('mod',p)
print(n)
