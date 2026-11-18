# V0.41 高保真立体声二次元×三国杀移动版音效与配乐合成器（44.1kHz Stereo）
import numpy as np, wave, subprocess, os

SR = 44100
ROOT = "/opt/quanmingxingsha/work/全明星杀_V0.31.0_交接包"
OUT_SFX = f"{ROOT}/game/assets/sfx"
OUT_BGM = f"{ROOT}/game/assets/bgm"
os.makedirs(OUT_SFX, exist_ok=True)
os.makedirs(OUT_BGM, exist_ok=True)
rng = np.random.default_rng(41)

def t_arr(d):
    return np.arange(int(SR * d), dtype=np.float64) / SR

def adsr(n, a=0.006, d=0.06, s=0.45, r=0.18):
    y = np.zeros(n, dtype=np.float64)
    na = max(1, min(n - 1, int(SR * a)))
    nd = max(1, min(n - na, int(SR * d)))
    y[:na] = np.linspace(0.0, 1.0, na)
    y[na:na + nd] = np.linspace(1.0, s, nd)
    rem = n - (na + nd)
    if rem > 0:
        y[na + nd:] = s * np.exp(-np.arange(rem) / max(1.0, SR * r * 0.35))
    return y

def lp1(x, cutoff_hz):
    rc = 1.0 / (2.0 * np.pi * max(cutoff_hz, 20.0))
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    klen = min(len(x), max(8, int(4.0 / max(alpha, 1e-4))))
    ker = alpha * ((1.0 - alpha) ** np.arange(klen))
    return np.convolve(x, ker, mode="full")[:len(x)]

def hp1(x, cutoff_hz):
    return x - lp1(x, cutoff_hz)

def reverb_stereo(mono, delay_ms=26.0, decay=0.28):
    n = len(mono)
    pad = int(SR * 0.22)
    L = np.zeros(n + pad, dtype=np.float64)
    R = np.zeros(n + pad, dtype=np.float64)
    L[:n] += mono
    R[:n] += mono
    for tap_i, (ms_l, ms_r, g) in enumerate([
        (delay_ms, delay_ms * 1.18, decay),
        (delay_ms * 1.9, delay_ms * 2.15, decay * 0.58),
        (delay_ms * 3.1, delay_ms * 3.45, decay * 0.32),
    ]):
        dl = int(SR * ms_l / 1000.0)
        dr = int(SR * ms_r / 1000.0)
        if dl + n <= len(L):
            L[dl:dl + n] += mono * g
        if dr + n <= len(R):
            R[dr:dr + n] += mono * g * (1.0 if tap_i % 2 == 0 else -0.9)
    return np.stack([L, R], axis=1)

def pluck_koto(freq, dur, bright=1.0):
    x = t_arr(dur)
    n = len(x)
    # 东方古筝/樱花琴泛音列 + 拨弦瞬态
    harms = [1.0, 0.58 * bright, 0.34 * bright, 0.19 * bright, 0.11 * bright, 0.06 * bright]
    sig = np.zeros(n)
    for idx, amp in enumerate(harms):
        h = idx + 1
        detune = 1.0 + (idx * 0.0004)
        decay_h = max(0.06, dur / (1.0 + 0.55 * idx))
        sig += amp * np.sin(2.0 * np.pi * freq * h * detune * x) * np.exp(-x / (decay_h * 0.38))
    # 拨片瞬态噪声
    transient_n = min(n, int(SR * 0.014))
    sig[:transient_n] += lp1(rng.standard_normal(transient_n), 3200.0) * np.linspace(0.45, 0.0, transient_n)
    return sig * adsr(n, a=0.003, d=0.05, s=0.65, r=dur * 0.75)

def crystal_bell(freq, dur):
    x = t_arr(dur)
    n = len(x)
    # 二次元风铃/水晶泛音（含非整数泛音营造晶莹感）
    ratios = [(1.0, 1.0), (2.0, 0.45), (2.756, 0.25), (4.0, 0.16), (5.404, 0.09)]
    sig = sum(a * np.sin(2.0 * np.pi * freq * r * x) * np.exp(-x / (dur * (0.45 / r**0.5))) for r, a in ratios)
    return sig * adsr(n, a=0.002, d=0.04, s=0.5, r=dur * 0.8)

def mix_mono(*parts):
    n = max(int(SR * off) + len(p) for off, p in parts)
    y = np.zeros(n, dtype=np.float64)
    for off, p in parts:
        o = int(SR * off)
        y[o:o + len(p)] += p
    return y

def save_ogg(out_dir, name, data, gain=0.82, stereo_reverb=True, q="4"):
    if data.ndim == 1:
        st = reverb_stereo(data) if stereo_reverb else np.stack([data, data], axis=1)
    else:
        st = data
    peak = np.max(np.abs(st)) + 1e-9
    st = np.clip(st / peak * gain, -0.99, 0.99)
    pcm = (st * 32767.0).astype(np.int16)
    wp = f"/tmp/{name}.wav"
    with wave.open(wp, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-nostdin", "-y", "-i", wp, "-c:a", "libvorbis", "-q:a", q, f"{out_dir}/{name}.ogg"],
        check=True,
    )
    os.remove(wp)

# 1. click: 二次元清脆水晶按键音
c_part = mix_mono((0.0, crystal_bell(1568.0, 0.055) * 0.7), (0.012, crystal_bell(2349.0, 0.075)))
save_ogg(OUT_SFX, "click", c_part, 0.58)

# 2. card: 纸牌轻盈点选摩擦声 + 微弱泛音
x = t_arr(0.11)
card_swish = hp1(lp1(rng.standard_normal(len(x)), 3400.0), 600.0) * np.hanning(len(x))
card_tone = crystal_bell(1046.5, 0.09) * 0.25
save_ogg(OUT_SFX, "card", mix_mono((0.0, card_swish), (0.01, card_tone)), 0.55)

# 3. draw: 手杀标志性「唰」摸牌飞入声
x = t_arr(0.14)
draw_n = hp1(lp1(rng.standard_normal(len(x)), 4600.0), 800.0) * np.sin(np.pi * x / 0.14) ** 1.3
draw_chime = pluck_koto(1318.5, 0.12, 0.8) * 0.22
save_ogg(OUT_SFX, "draw", mix_mono((0.0, draw_n), (0.02, draw_chime)), 0.52)

# 4. play: 手杀甩牌破空 + 古筝双泛音
x = t_arr(0.16)
snap = hp1(lp1(rng.standard_normal(len(x)), 3800.0), 500.0) * np.exp(-x * 22.0) * 0.65
p_mel = mix_mono((0.0, snap), (0.0, pluck_koto(659.25, 0.24)), (0.045, pluck_koto(987.77, 0.28)))
save_ogg(OUT_SFX, "play", p_mel, 0.65)

# 5. slash: 刀剑出鞘破空斩击（金属铮鸣 + 空气挥砍）
x = t_arr(0.28)
whoosh = hp1(lp1(rng.standard_normal(len(x)), 4200.0), 700.0) * np.sin(np.pi * np.clip(x / 0.22, 0, 1)) * 0.8
blade_f = 2400.0 * np.exp(-x * 5.5) + 680.0
blade = (np.sin(2 * np.pi * blade_f * x) + 0.5 * np.sin(2 * np.pi * 2637.0 * x) * np.exp(-x * 16.0)) * np.exp(-x * 10.0)
save_ogg(OUT_SFX, "slash", mix_mono((0.0, blade * 0.75), (0.02, whoosh)), 0.78)

# 6. hit: 手杀物理重击受创（低频战鼓重锤 + 护甲震击 + 剑气）
x = t_arr(0.34)
sub_thump = np.sin(2 * np.pi * (165.0 * np.exp(-x * 11.0) + 42.0) * x) * np.exp(-x * 7.5) * 1.2
impact_noise = lp1(rng.standard_normal(len(x)), 1600.0) * np.exp(-x * 18.0) * 0.85
metal_ring = crystal_bell(440.0, 0.22) * 0.3
save_ogg(OUT_SFX, "hit", mix_mono((0.0, sub_thump), (0.0, impact_noise), (0.01, metal_ring)), 0.90)

# 7. fire_hit: 烈焰爆燃伤害（低频轰燃 + 高频火焰噼啪）
x = t_arr(0.45)
roar = lp1(rng.standard_normal(len(x)), 650.0) * np.sin(np.pi * np.clip(x / 0.38, 0, 1)) * 1.1
crackle = hp1(rng.standard_normal(len(x)), 2600.0) * (rng.random(len(x)) > 0.92).astype(float) * np.exp(-x * 4.5) * 0.9
f_thump = np.sin(2 * np.pi * (130.0 * np.exp(-x * 8.0) + 38.0) * x) * np.exp(-x * 8.0)
save_ogg(OUT_SFX, "fire_hit", mix_mono((0.0, f_thump), (0.0, roar), (0.02, crackle)), 0.90)

# 8. thunder_hit: 雷霆劈落伤害（高频电弧炸裂 + 滚雷低频轰鸣）
x = t_arr(0.48)
crack = hp1(rng.standard_normal(len(x)), 1800.0) * np.exp(-x * 16.0) * 1.1
zap = np.sin(2 * np.pi * (1800.0 * np.exp(-x * 14.0) + 120.0) * x) * np.exp(-x * 9.0) * 0.75
rumble = lp1(rng.standard_normal(len(x)), 240.0) * np.exp(-x * 3.8) * 1.2
save_ogg(OUT_SFX, "thunder_hit", mix_mono((0.0, crack), (0.0, zap), (0.03, rumble)), 0.92)

# 9. dodge: 轻盈疾风闪避 + 樱花风铃
x = t_arr(0.26)
wind = hp1(lp1(rng.standard_normal(len(x)), 3200.0), 500.0) * np.hanning(len(x)) * 0.7
d_chime = mix_mono((0.0, wind), (0.03, crystal_bell(1318.5, 0.16) * 0.45), (0.09, crystal_bell(1760.0, 0.18) * 0.45))
save_ogg(OUT_SFX, "dodge", d_chime, 0.65)

# 10. heal: 圣光治愈竖琴大七和弦琶音
heal_notes = [523.25, 659.25, 783.99, 987.77, 1046.5, 1318.5]
heal_m = mix_mono(*[(i * 0.055, pluck_koto(f, 0.42, 0.9) * 0.65 + crystal_bell(f * 2, 0.42) * 0.25) for i, f in enumerate(heal_notes)])
save_ogg(OUT_SFX, "heal", heal_m, 0.68)

# 11. equip: 穿戴武器防具金属锁扣 + 剑鸣
x = t_arr(0.18)
clink1 = crystal_bell(1480.0, 0.18) + hp1(rng.standard_normal(len(x)), 2800.0) * np.exp(-x * 30.0) * 0.4
clink2 = crystal_bell(2217.5, 0.22) + pluck_koto(880.0, 0.22, 1.2) * 0.5
save_ogg(OUT_SFX, "equip", mix_mono((0.0, clink1), (0.065, clink2)), 0.68)

# 12. trick: 锦囊妙计展开（竹简刷开 + 古筝五声扫弦）
x = t_arr(0.15)
scroll = lp1(rng.standard_normal(len(x)), 2200.0) * np.hanning(len(x)) * 0.45
t_notes = [587.33, 659.25, 880.0, 1174.66]
trick_m = mix_mono((0.0, scroll), *[(0.02 + i * 0.032, pluck_koto(f, 0.28, 1.1) * 0.65) for i, f in enumerate(t_notes)])
save_ogg(OUT_SFX, "trick", trick_m, 0.66)

# 13. nullify: 看破/无懈可击（清冽冰晶屏障反制声）
nul_m = mix_mono(
    (0.0, crystal_bell(1975.5, 0.18)),
    (0.04, crystal_bell(2637.0, 0.26)),
    (0.08, pluck_koto(1318.5, 0.32, 1.3) * 0.7),
)
save_ogg(OUT_SFX, "nullify", nul_m, 0.72)

# 14. judge: 天命判定悬念飞旋 + 定音鼓点
j_m = mix_mono(
    (0.0, pluck_koto(659.25, 0.14)),
    (0.08, pluck_koto(880.0, 0.14)),
    (0.16, pluck_koto(1318.5, 0.30) + crystal_bell(1318.5, 0.30) * 0.5),
)
save_ogg(OUT_SFX, "judge", j_m, 0.66)

# 15. chain: 铁索连环金属链条交错声
ch_parts = []
for i, f in enumerate([1100.0, 1420.0, 960.0, 1680.0]):
    x = t_arr(0.09)
    ring = (np.sin(2 * np.pi * f * x) + 0.6 * np.sin(2 * np.pi * (f * 1.41) * x)) * np.exp(-x * 26.0)
    nz = hp1(rng.standard_normal(len(x)), 2400.0) * np.exp(-x * 32.0) * 0.45
    ch_parts.append((i * 0.055, ring + nz))
save_ogg(OUT_SFX, "chain", mix_mono(*ch_parts), 0.68)

# 16. skill: 二次元必杀技觉醒（能量上行 + 华丽五声琶音绽放）
x = t_arr(0.18)
sweep = np.sin(2 * np.pi * (440.0 + 1800.0 * (x / 0.18) ** 2) * x) * np.hanning(len(x)) * 0.35
sk_notes = [659.25, 783.99, 987.77, 1318.5, 1567.98, 1975.5]
sk_m = mix_mono((0.0, sweep), *[(0.03 + i * 0.032, crystal_bell(f, 0.32) * 0.55 + pluck_koto(f, 0.32) * 0.45) for i, f in enumerate(sk_notes)])
save_ogg(OUT_SFX, "skill", sk_m, 0.70)

# 17. turn: 自己回合开始（古风清越玉磬 + 樱花风铃）
turn_m = mix_mono(
    (0.0, pluck_koto(587.33, 0.45) * 0.7),
    (0.05, pluck_koto(880.0, 0.50) * 0.8),
    (0.11, crystal_bell(1760.0, 0.55) * 0.55),
)
save_ogg(OUT_SFX, "turn", turn_m, 0.64)

# 18. dying: 濒死双连急促心跳 + 警报低音弦
x = t_arr(0.20)
hb1 = np.sin(2 * np.pi * (72.0 * np.exp(-x * 5.0) + 36.0) * x) * np.exp(-x * 11.0)
hb2 = np.sin(2 * np.pi * (64.0 * np.exp(-x * 5.0) + 34.0) * x) * np.exp(-x * 12.0) * 0.85
warn = pluck_koto(220.0, 0.45, 0.5) * 0.35
save_ogg(OUT_SFX, "dying", mix_mono((0.0, hb1), (0.19, hb2), (0.02, warn)), 0.86)

# 19. death: 阵亡落幕古钟下行
death_m = mix_mono(
    (0.0, pluck_koto(392.0, 0.45, 0.6)),
    (0.14, pluck_koto(329.63, 0.48, 0.6)),
    (0.28, pluck_koto(246.94, 0.75, 0.5) + crystal_bell(246.94, 0.75) * 0.4),
)
save_ogg(OUT_SFX, "death", death_m, 0.72)

# 20. revive: 濒死获救破晓竖琴琶音
rev_m = mix_mono(*[(i * 0.06, pluck_koto(f, 0.45) + crystal_bell(f * 2, 0.45) * 0.35) for i, f in enumerate([523.25, 659.25, 783.99, 1046.5, 1567.98])])
save_ogg(OUT_SFX, "revive", rev_m, 0.72)

# 21. shield: 护甲凝聚/圣盾共鸣
sh_m = mix_mono((0.0, crystal_bell(880.0, 0.25)), (0.04, crystal_bell(1318.5, 0.35)), (0.08, pluck_koto(1760.0, 0.35) * 0.5))
save_ogg(OUT_SFX, "shield", sh_m, 0.65)

# 22. spree: 手杀连破/一血/无双战鼓号角齐鸣
x = t_arr(0.25)
drum = np.sin(2 * np.pi * (140.0 * np.exp(-x * 9.0) + 45.0) * x) * np.exp(-x * 7.0)
sp_m = mix_mono(
    (0.0, drum),
    (0.12, drum * 0.9),
    (0.0, pluck_koto(587.33, 0.35, 1.3)),
    (0.08, pluck_koto(880.0, 0.42, 1.3)),
    (0.16, pluck_koto(1174.66, 0.65, 1.4) + crystal_bell(1760.0, 0.65) * 0.5),
)
save_ogg(OUT_SFX, "spree", sp_m, 0.85)

# 23. win: 胜利凯旋华丽管弦古筝交响 Fanfare
win_seq = [
    (0.00, 523.25, 0.28),
    (0.13, 659.25, 0.28),
    (0.26, 783.99, 0.28),
    (0.39, 1046.50, 0.42),
    (0.56, 880.00, 0.24),
    (0.70, 1046.50, 0.30),
    (0.86, 1318.51, 1.15),
]
win_parts = []
for off, f, d in win_seq:
    win_parts.append((off, pluck_koto(f, d, 1.2) * 0.8 + crystal_bell(f, d) * 0.4 + pluck_koto(f * 0.5, d, 0.7) * 0.45))
save_ogg(OUT_SFX, "win", mix_mono(*win_parts), 0.80)

# 24. lose: 惜败婉转弦乐下行叹息
lose_seq = [
    (0.00, 493.88, 0.45),
    (0.24, 440.00, 0.45),
    (0.48, 392.00, 0.48),
    (0.74, 329.63, 1.10),
]
lose_parts = [(off, pluck_koto(f, d, 0.6) * 0.75 + pluck_koto(f * 0.5, d, 0.4) * 0.5) for off, f, d in lose_seq]
save_ogg(OUT_SFX, "lose", mix_mono(*lose_parts), 0.68)

print("SFX_GENERATED:", len([f for f in os.listdir(OUT_SFX) if f.endswith(".ogg")]))

# ---------------- 生成 3 首原创「二次元樱华国风 × 三国杀移动版」无缝循环 BGM ----------------
def warm_pad(freq, dur):
    x = t_arr(dur)
    s = (
        0.55 * np.sin(2 * np.pi * freq * x)
        + 0.30 * np.sin(2 * np.pi * freq * 1.5 * x)
        + 0.20 * np.sin(2 * np.pi * freq * 2.002 * x)
    )
    return s * np.sin(np.pi * np.clip(x / dur, 0, 1)) ** 0.7

def taiko_hit(dur=0.22, pitch=95.0):
    x = t_arr(dur)
    body = np.sin(2 * np.pi * (pitch * np.exp(-x * 12.0) + 42.0) * x) * np.exp(-x * 9.5)
    skin = lp1(rng.standard_normal(len(x)), 900.0) * np.exp(-x * 26.0) * 0.35
    return body + skin

# BGM 1: home_sakura.ogg 《樱华序曲 · 星樱学园》（五声宫调 + 樱花琴琶音 + 柔美弦乐 Pad）
beat = 0.45  # ~133 BPM 八分音符
# D大调/五声：D4=293.66, E4=329.63, F#4=369.99, A4=440.0, B4=493.88, D5=587.33, E5=659.25, F#5=739.99, A5=880.0
melody_home = [
    659.25, 587.33, 493.88, 440.00, 493.88, 587.33, 659.25, 739.99,
    880.00, 739.99, 659.25, 587.33, 493.88, 440.00, 587.33, 587.33,
    659.25, 739.99, 880.00, 739.99, 659.25, 587.33, 493.88, 440.00,
    369.99, 440.00, 493.88, 659.25, 587.33, 493.88, 440.00, 440.00,
]
chords_home = [293.66, 246.94, 196.00, 220.00, 293.66, 246.94, 196.00, 220.00]
home_parts = []
for idx, f in enumerate(melody_home):
    t0 = idx * beat
    home_parts.append((t0, pluck_koto(f, beat * 1.8, 0.95) * 0.55))
    if idx % 2 == 0:
        home_parts.append((t0, pluck_koto(f * 0.5, beat * 2.2, 0.6) * 0.28))
    if idx % 4 == 0:
        home_parts.append((t0 + beat * 0.5, crystal_bell(f * 2.0, beat * 1.6) * 0.16))
for ci, cf in enumerate(chords_home):
    home_parts.append((ci * beat * 4.0, warm_pad(cf, beat * 4.2) * 0.34))
save_ogg(OUT_BGM, "home_sakura", mix_mono(*home_parts), 0.62, stereo_reverb=True, q="4")

# BGM 2: battle_storm.ogg 《绯樱战阵 · 破阵乐》（手杀经典疾速战鼓 + 琵琶/古筝轮指）
b_beat = 0.24  # 疾速十六分/八分律动
# E小调古风战曲：E4=329.63, G4=392.00, A4=440.00, B4=493.88, D5=587.33, E5=659.25, G5=783.99, A5=880.00
riff_battle = [
    659.25, 659.25, 783.99, 659.25, 587.33, 493.88, 440.00, 493.88,
    659.25, 783.99, 880.00, 783.99, 659.25, 587.33, 493.88, 493.88,
    587.33, 659.25, 783.99, 659.25, 587.33, 493.88, 440.00, 392.00,
    440.00, 493.88, 587.33, 493.88, 440.00, 392.00, 329.63, 329.63,
] * 2
bat_parts = []
for idx, f in enumerate(riff_battle):
    t0 = idx * b_beat
    bat_parts.append((t0, pluck_koto(f, b_beat * 1.6, 1.25) * 0.58))
    # 战鼓律动（强拍重鼓、弱拍轻击）
    if idx % 4 == 0:
        bat_parts.append((t0, taiko_hit(0.20, 92.0) * 0.65))
        bat_parts.append((t0, warm_pad(164.81 if (idx // 8) % 2 == 0 else 146.83, b_beat * 4.0) * 0.32))
    elif idx % 4 == 2:
        bat_parts.append((t0, taiko_hit(0.14, 135.0) * 0.38))
    elif idx % 8 == 7:
        bat_parts.append((t0, taiko_hit(0.12, 150.0) * 0.35))
save_ogg(OUT_BGM, "battle_storm", mix_mono(*bat_parts), 0.66, stereo_reverb=True, q="4")

# BGM 3: tense_climax.ogg 《宿命决战 · 残月》（手杀残局/濒死急促三连音战鼓 + 高压弦乐）
t_beat = 0.20
riff_tense = [
    659.25, 698.46, 659.25, 587.33, 659.25, 880.00, 783.99, 698.46,
    659.25, 587.33, 493.88, 523.25, 493.88, 440.00, 392.00, 493.88,
    659.25, 698.46, 783.99, 880.00, 987.77, 880.00, 783.99, 698.46,
    659.25, 587.33, 493.88, 440.00, 392.00, 329.63, 493.88, 329.63,
] * 2
ten_parts = []
for idx, f in enumerate(riff_tense):
    t0 = idx * t_beat
    ten_parts.append((t0, pluck_koto(f, t_beat * 1.5, 1.35) * 0.56))
    if idx % 2 == 0:
        ten_parts.append((t0, taiko_hit(0.16, 86.0) * 0.68))
    elif idx % 4 == 3:
        ten_parts.append((t0, taiko_hit(0.11, 145.0) * 0.45))
    if idx % 8 == 0:
        ten_parts.append((t0, warm_pad(164.81, t_beat * 8.0) * 0.36 + crystal_bell(f, t_beat * 8.0) * 0.22))
save_ogg(OUT_BGM, "tense_climax", mix_mono(*ten_parts), 0.68, stereo_reverb=True, q="4")

print("BGM_GENERATED:", sorted([f for f in os.listdir(OUT_BGM) if f.endswith(".ogg")]))
