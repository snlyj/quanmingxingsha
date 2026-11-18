import asyncio, os, subprocess
import edge_tts

OUT_DIR = "/opt/quanmingxingsha/work/全明星杀_V0.31.0_交接包/game/assets/voice"
os.makedirs(OUT_DIR, exist_ok=True)

VOICES = {
    "hina": ("zh-CN-XiaoyiNeural", "+16Hz", "+4%", {
        "skill": "把心愿，交给樱花吧！",
        "attack": "花瓣啊，听我的心愿！",
        "hurt": "呜，没关系的，还能坚持！",
        "dying": "花签，还没许完愿呢……",
        "touch": "诶？摸头的话会害羞啦，不过感觉暖洋洋的呢～",
    }),
    "rena": ("zh-CN-XiaoyiNeural", "+22Hz", "+10%", {
        "skill": "风纪委员，立即执行！",
        "attack": "站住！违反校规，不许动！",
        "hurt": "好痛！我才不会退让呢！",
        "dying": "下课铃声，明明还没停……",
        "touch": "笨蛋！乱碰哪里呢！违反风纪要扣分的哦！",
    }),
    "kaori": ("zh-CN-XiaoyiNeural", "+25Hz", "+12%", {
        "skill": "你的心跳，我全部听见啦！",
        "attack": "听我的歌吧！麦克风全开！",
        "hurt": "呜哇！歌声绝对不能停！",
        "dying": "最后，再让我唱一首吧……",
        "touch": "嘿嘿，是粉丝福利时间吗？最喜欢你的应援啦！",
    }),
    "chinatsu": ("zh-CN-XiaoxiaoNeural", "+18Hz", "+14%", {
        "skill": "元气补给，能量满格！",
        "attack": "全速冲刺！看我的起跑！",
        "hurt": "摔一跤而已，再来一次！",
        "dying": "终点线，明明就在前面……",
        "touch": "哇！别突然戳我啦，刚跑完步身上还热乎乎的呢！",
    }),
    "shizuha": ("zh-CN-XiaoyiNeural", "+12Hz", "-10%", {
        "skill": "呼啊，我去看星星了哦……",
        "attack": "呜，茶都要凉了啦……",
        "hurt": "好困，被你打醒了啦……",
        "dying": "今夜的星星，好远啊……",
        "touch": "嗯，再让我靠在你肩上睡五分钟嘛，暖呼呼的……",
    }),
    "hibiki": ("zh-CN-XiaoyiNeural", "+20Hz", "+8%", {
        "skill": "吵死了，全都给我安静听琴！",
        "attack": "听好了，练习曲开始！",
        "hurt": "笨蛋，下手轻一点啦！",
        "dying": "琴弦，要断掉了……",
        "touch": "哼，既然你这么诚心，本小姐就破例为你独奏一曲吧！",
    }),
    "koume": ("zh-CN-XiaoxiaoNeural", "+14Hz", "-2%", {
        "skill": "请让我用热茶来招待您吧。",
        "attack": "请恕小梅失礼了，这一杯请收下！",
        "hurt": "呜，围裙都要弄脏了……",
        "dying": "茶，还没有泡好呢……",
        "touch": "主人，今天也辛苦了，要尝尝小梅亲手做的樱花点心吗？",
    }),
    "sena": ("zh-CN-XiaoxiaoNeural", "+4Hz", "+2%", {
        "skill": "星辰轨迹，尽在我的掌握！",
        "attack": "按学生会章程，予以肃清！",
        "hurt": "唔，推算偏了一分吗？",
        "dying": "星轨，还没有走到尽头……",
        "touch": "在学生会室做这种事……咳，下不为例，只允许你一个人哦。",
    }),
    "reo": ("zh-CN-XiaoxiaoNeural", "-2Hz", "+8%", {
        "skill": "秘剑残月，一刀两断，斩！",
        "attack": "看剑！我的竹刀绝不迟疑！",
        "hurt": "好刀法，这点伤连热身都不算！",
        "dying": "剑道之巅，还没有登上去……",
        "touch": "喂！握剑的手可不是用来牵的……算了，偶尔放松一下也无妨。",
    }),
    "mahiru": ("zh-CN-XiaoyiNeural", "+10Hz", "-4%", {
        "skill": "昼夜轮转，阴阳易位！",
        "attack": "翻至阳之卷，星火燎原！",
        "hurt": "唔，把书页都弄乱了……",
        "dying": "合上书卷，晚安……",
        "touch": "嘘，在图书室靠这么近，心跳声会被别人听见的……",
    }),
    "aya": ("zh-CN-XiaoxiaoNeural", "+6Hz", "+5%", {
        "skill": "心眼开阖，神射无双！",
        "attack": "一矢中的，落樱百步，破！",
        "hurt": "弓弦未乱，还能再射！",
        "dying": "弓弦，要断了吗……",
        "touch": "想学射箭的话，手把手教你也可以……别一直盯着我看呀。",
    }),
    "nana": ("zh-CN-XiaoyiNeural", "+26Hz", "+12%", {
        "skill": "催化剂投入，连锁反应开始咯！",
        "attack": "尝尝特制星光试剂，砰！",
        "hurt": "哇啊！烧杯差点碎掉啦！",
        "dying": "实验报告，还没写完呢……",
        "touch": "嘿嘿，想喝这瓶粉色恋爱药水吗？保证甜到心里去哦～",
    }),
    "rin": ("zh-CN-XiaoyiNeural", "+14Hz", "+4%", {
        "skill": "妙算入神，一子定乾坤！",
        "attack": "这一手，将军！棋路早已算定！",
        "hurt": "嗯，弃子争先罢了。",
        "dying": "终盘，还没分出胜负……",
        "touch": "算尽了棋盘上的百步变化，却算不准你靠近时的心跳呢。",
    }),
    "yukine": ("zh-CN-XiaoxiaoNeural", "+8Hz", "+3%", {
        "skill": "精算无遗，凛霜反噬！",
        "attack": "违规预算，予以冻结！",
        "hurt": "寒霜，会记住这次冒犯。",
        "dying": "冰雪，终究会融化吗……",
        "touch": "手这么暖和，再握一会儿的话，我的冰霜可要被你融化了。",
    }),
    "lilia": ("zh-CN-XiaoxiaoNeural", "+10Hz", "+4%", {
        "skill": "展开吧，圣纹护盾！荣耀庇佑！",
        "attack": "以骑士团之名，荣耀之剑，突进！",
        "hurt": "圣盾尚在，休想越过我的防线！",
        "dying": "骑士的誓言，永不磨灭……",
        "touch": "向您献上骑士的忠诚……诶？摸头发可不在骑士礼仪里呀！",
    }),
    "sakuya": ("zh-CN-XiaoyiNeural", "+15Hz", "+0%", {
        "skill": "拨转星盘，逆写此刻的宿命！",
        "attack": "时针指处，即是终局。",
        "hurt": "时间，出现了裂隙吗……",
        "dying": "钟摆，快要停下了吗……",
        "touch": "如果能把时间停在这一刻，就能一直和你待在钟塔下了呢。",
    }),
    "sana": ("zh-CN-XiaoxiaoNeural", "+2Hz", "+9%", {
        "skill": "万羽归刃，破空连斩！",
        "attack": "黑羽所至，一闪即斩！",
        "hurt": "哼，这片影羽，我记下了！",
        "dying": "绯色的樱花，落尽了吗……",
        "touch": "我的围巾很暖和哦，想围在一起的话，再靠近一点吧。",
    }),
    "yuu": ("zh-CN-XiaoyiNeural", "+18Hz", "+2%", {
        "skill": "天命流转，由我改写此签！",
        "attack": "灵札指路，卦象说你躲不开哦～",
        "hurt": "呀，占卜没有算到这一着……",
        "dying": "命运的红线，到此为止了吗……",
        "touch": "今天抽到了上上签哦，签文上写着，命中注定的人就在眼前呢。",
    }),
    "mafuyu": ("zh-CN-XiaoxiaoNeural", "+5Hz", "+3%", {
        "skill": "霜封万里，万物皆寂，破！",
        "attack": "风纪肃清，连同呼吸一并冻结！",
        "hurt": "冷静，寒霜不会因此动摇。",
        "dying": "冬樱，要提前凋零了吗……",
        "touch": "明明是风纪巡查时间，被你这样温柔地碰触，怎么冷得下脸嘛。",
    }),
}

sem = asyncio.Semaphore(3)

async def gen_one(cid, cat, voice, pitch, rate, text):
    ogg_path = f"{OUT_DIR}/cv_{cid}_{cat}.ogg"
    if os.path.exists(ogg_path) and os.path.getsize(ogg_path) > 1000:
        return
    mp3_tmp = f"/tmp/cv_{cid}_{cat}.mp3"
    async with sem:
        for attempt in range(6):
            try:
                comm = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
                await comm.save(mp3_tmp)
                subprocess.run(
                    ["ffmpeg", "-loglevel", "error", "-nostdin", "-y", "-i", mp3_tmp,
                     "-af", "silenceremove=start_periods=1:start_silence=0.05:start_threshold=-45dB,volume=1.35",
                     "-ar", "24000", "-ac", "1", "-c:a", "libvorbis", "-q:a", "2", ogg_path],
                    check=True,
                )
                if os.path.exists(mp3_tmp):
                    os.remove(mp3_tmp)
                break
            except Exception as e:
                if attempt == 2:
                    raise e
                await asyncio.sleep(0.8)

async def main():
    tasks = []
    for cid, (voice, pitch, rate, lines) in VOICES.items():
        for cat, text in lines.items():
            tasks.append(gen_one(cid, cat, voice, pitch, rate, text))
    await asyncio.gather(*tasks)
    files = [f for f in os.listdir(OUT_DIR) if f.endswith(".ogg")]
    print("GENERATED_CV_FILES:", len(files))

asyncio.run(main())
