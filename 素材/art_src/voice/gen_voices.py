"""Render the game's Mandarin voice lines offline with a local EmotiVoice checkout."""
import argparse
from functools import lru_cache
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import numpy as np
import torch
from transformers import AutoConfig, AutoModel, AutoTokenizer
from yacs import config as yaml

REPO = Path(__file__).resolve().parents[3]
LINES = REPO / "game/data/voice_lines.gd"
DESTINATION = REPO / "game/assets/voice"

# Preset speaker IDs belong to EmotiVoice. Each actor keeps the same timbre across scenes.
CAST = {
    "hina": ("1012", "天真轻快，温柔好奇"),
    "rena": ("1051", "语气利落，认真，有条理"),
    "kaori": ("1088", "开朗有舞台感，带着节拍"),
    "chinatsu": ("92", "元气十足，直率爽朗"),
    "shizuha": ("1093", "慵懒轻柔，像半梦半醒"),
    "hibiki": ("1066", "倔强，好胜，重音鲜明"),
    "koume": ("1168", "安静礼貌，句尾柔软"),
    "sena": ("1006", "笃定清晰，沉稳自信"),
    "reo": ("1084", "果断有力，干净利落"),
    "mahiru": ("8051", "娓娓道来，平和温暖"),
    "aya": ("1079", "专注清亮，呼吸平稳"),
    "nana": ("1052", "活泼好奇，情绪转折明显"),
    "rin": ("1171", "克制，不急不慢，带一点笑意"),
    "yukine": ("102", "冷静准确，咬字清楚"),
    "lilia": ("1069", "自信爽朗，像在鼓励同伴"),
    "sakuya": ("1152", "从容优雅，有节拍感"),
    "sana": ("1166", "沉着克制，动词干净利落"),
    "yuu": ("12787", "俏皮轻盈，像在分享秘密"),
    "mafuyu": ("1154", "清冷可靠，尾音柔和"),
}

# Text prompt, duration multiplier (larger = slower), target RMS in dBFS.
DIRECTION = {
    "attack": ("坚定，短促有力，重读最后的动作。", 0.97, -19.0),
    "skill": ("自信，先说清楚，再把动作说得有力量。", 1.00, -19.0),
    "hurt": ("惊讶，突然吃痛，后半句收住声音。", 0.97, -20.4),
    "dying": ("悲伤，虚弱而迟疑，停一拍再努力说完。", 1.10, -22.0),
    "touch": ("开心，像和熟人闲聊，带一点笑意。", 1.02, -20.2),
    "heal": ("先松一口气，再带着欣慰的笑意。", 1.03, -20.1),
    "dodge": ("反应迅速，先一惊，再带一点得意。", 0.94, -20.0),
    "death": ("遗憾，疲惫又平静，尾音轻轻落下。", 1.12, -22.6),
    "gift": ("惊喜，露出微笑，自然地道谢。", 1.00, -20.2),
    "head": ("开心又有点害羞，亲切放松。", 1.02, -20.4),
    "face": ("害羞，先惊讶一下，接着带一点笑意。", 1.01, -20.4),
    "body": ("温和，自然聊天，语气轻松。", 1.03, -20.4),
    "vow": ("温柔，真挚，郑重地许下约定。", 1.07, -21.0),
}


def spoken_text(caption):
    # The Chinese frontend recognises clause breaks. Map display-only punctuation
    # to a single break and avoid a synthetic hesitation before the first syllable.
    text = re.sub(r"[～~…—]+", "，", caption).translate(str.maketrans("", "", "『』「」"))
    return re.sub(r"[，。！？：、]{2,}", "，", text).lstrip("，")


def level(wave, rate, target_db):
    peak = np.abs(wave).max()
    if not np.isfinite(wave).all() or peak < 0.001:
        raise ValueError("Model returned invalid or silent audio")
    active = np.flatnonzero(np.abs(wave) >= max(0.0005, peak * 0.012))
    wave = wave[max(0, active[0] - int(rate * 0.045)): active[-1] + int(rate * 0.085) + 1].copy()
    rms = np.sqrt(np.mean(wave ** 2))
    wave *= min(10 ** (target_db / 20) / rms, 0.84 / peak, 3.0)
    for part, ms in ((wave, 12), (wave[::-1], 37)):
        length = min(int(rate * ms / 1000), len(part) // 3)
        part[:length] *= (1.0 - np.cos(np.linspace(0, np.pi, length))) / 2
    return wave


class Speech:
    def __init__(self, checkout):
        # Upstream Config resolves data, lexicon and model paths from the current directory.
        sys.path.insert(0, str(checkout))
        os.chdir(checkout)
        from config.joint.config import Config
        from frontend_cn import g2p_cn
        from models.prompt_tts_modified.jets import JETSGenerator

        cfg = Config()
        self.phonemes = g2p_cn
        self.rate = cfg.sampling_rate
        self.tokens = {token: i for i, token in enumerate(cfg.tokens)}
        self.speakers = {speaker: i for i, speaker in enumerate(cfg.speakers)}
        self.tokenizer = AutoTokenizer.from_pretrained(cfg.bert_path, local_files_only=True)
        self.encoder = AutoModel.from_config(AutoConfig.from_pretrained(cfg.bert_path, local_files_only=True))
        style = torch.load(cfg.style_encoder_ckpt, map_location="cpu", weights_only=True)["model"]
        bert = {k.split("bert.", 1)[1]: v for k, v in style.items() if k.removeprefix("module.").startswith("bert.")}
        # Transformers versions differ on whether the generated position index is persisted.
        if "embeddings.position_ids" not in self.encoder.state_dict():
            bert.pop("embeddings.position_ids", None)
        self.encoder.load_state_dict(bert, strict=True)
        del style, bert
        self.encoder.eval()
        with open(cfg.model_config_path, encoding="utf-8") as source:
            params = yaml.load_cfg(source)
        params.n_vocab, params.n_speaker = cfg.n_symbols, cfg.speaker_n_labels
        self.generator = JETSGenerator(params)
        model = Path(cfg.output_directory) / "prompt_tts_open_source_joint/ckpt/g_00140000"
        self.generator.load_state_dict(torch.load(model, map_location="cpu", weights_only=True)["generator"])
        self.generator.eval()

    @lru_cache(maxsize=256)
    def embed(self, text):
        return self.encoder(**self.tokenizer([text], return_tensors="pt")).pooler_output

    @torch.inference_mode()
    def synthesize(self, cid, category, caption):
        speaker, character = CAST[cid]
        mood, duration, target_db = DIRECTION[category]
        text = spoken_text(caption)
        tokens = self.phonemes(text).split()
        sequence = torch.tensor([[self.tokens[t] for t in tokens]], dtype=torch.long)
        prediction = self.generator(
            inputs_ling=sequence,
            input_lengths=torch.tensor([sequence.shape[1]]),
            inputs_speaker=torch.tensor([self.speakers[speaker]]),
            inputs_style_embedding=self.embed(mood + " 声线" + character + "。"),
            inputs_content_embedding=self.embed(text),
            alpha=duration,
        )
        wave = level(prediction["wav_predictions"].squeeze().numpy(), self.rate, target_db)
        seconds = len(wave) / self.rate
        if not (0.30 <= seconds <= 25.0):
            raise ValueError(f"{cid}/{category} has unexpected length {seconds:.2f}s")
        return wave


def save_ogg(destination, wave, rate):
    # Atomic replacement lets an interrupted render be repeated without corrupting a clip.
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False, suffix=".tmp") as temp:
        path = Path(temp.name)
    try:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(rate), "-ac", "1",
             "-i", "pipe:0", "-c:a", "libvorbis", "-q:a", "5", "-map_metadata", "-1",
             "-f", "ogg", str(path)],
            input=wave.astype("<f4").tobytes(), check=True,
        )
        os.replace(path, destination)
    finally:
        path.unlink(missing_ok=True)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--emotivoice", type=Path, required=True, help="Path to the local model checkout")
    cli.add_argument("--output", type=Path, default=DESTINATION)
    cli.add_argument("--character", nargs="+", choices=CAST, default=list(CAST))
    cli.add_argument("--event", nargs="+", choices=DIRECTION, default=list(DIRECTION))
    args = cli.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    lines = json.loads(LINES.read_text(encoding="utf-8").split("const LINES := ", 1)[1])
    if set(lines) != set(CAST) or any(set(row) != set(DIRECTION) for row in lines.values()):
        raise ValueError("The TTS cast, event directions and in-game dialogue must match")
    torch.manual_seed(42)
    cpus = len(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else (os.cpu_count() or 1)
    torch.set_num_threads(min(4, cpus))
    torch.set_num_interop_threads(1)
    speech = Speech(args.emotivoice.resolve())
    failures = []
    for cid in args.character:
        for category in args.event:
            name = f"cv_{cid}_{category}"
            try:
                wave = speech.synthesize(cid, category, lines[cid][category])
                save_ogg(output / (name + ".ogg"), wave, speech.rate)
                print(f"{name} {len(wave) / speech.rate:.2f}s", flush=True)
            except (ValueError, KeyError, IndexError, RuntimeError, subprocess.SubprocessError) as error:
                failures.append(name)
                print(f"Failed {name}: {error}", file=sys.stderr, flush=True)
    if failures:
        raise SystemExit("Failed clips: " + ", ".join(failures))


if __name__ == "__main__":
    main()
