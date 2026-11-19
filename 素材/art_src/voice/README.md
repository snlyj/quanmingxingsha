# 角色语音

游戏内字幕和离线合成都读取同一份中文台词。每名角色有自己的预设音色和说话习惯，每类事件有单独的情绪提示、语速和音量。例如，受创以短促的惊讶开口，回血先松一口气，濒死会放慢并降低音量。[台词表](../../../game/data/voice_lines.gd) · [音色和情绪配置](gen_voices.py)

## 重新生成

在单独的 Python 3.11 环境中安装 FFmpeg、CPU 版 PyTorch 2.5.1、Transformers 4.45.2、NumPy 1.26.4、SciPy、Numba 0.61.2、YACS、Jieba、pypinyin 和 pypinyin-dict。FFmpeg 需要包含 libvorbis 编码器。

准备 EmotiVoice 源码（本次使用 `59f0f36`），将官方预训练模型（`d1332ad`）放进其 `outputs/`。把 SimBERT 的 `config.json` 和 `vocab.txt` 放在同目录下的 `WangZeJun/simbert-base-chinese/`。脚本从预训练的风格编码器载入完整 BERT 权重。[EmotiVoice](https://github.com/netease-youdao/EmotiVoice) · [预训练权重与许可](https://modelscope.cn/models/syq163/outputs) · [SimBERT 词表和配置](https://huggingface.co/WangZeJun/simbert-base-chinese)

从游戏仓库根目录执行以下命令。输入为文字，推理在本地 CPU 完成。输出是游戏可直接播放的 16 kHz 单声道 OGG 文件。Godot 导入资源后即可在图鉴或对局中试听。

```bash
python 素材/art_src/voice/gen_voices.py --emotivoice /path/to/EmotiVoice
godot --headless --path game --import
```

单独修改一句时可指定角色和事件，例如 `--character sena --event hurt`。使用 `--output` 可以先输出到试听目录。角色音量保存在 Voice 总线设置中，背景音乐会在台词播放期间衰减 2.8 dB。
