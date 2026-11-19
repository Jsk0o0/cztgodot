"""对白配音 (同人新增, 原版没有对白语音): 剧本里的对白 → CosyVoice3 方言 TTS → <输出>/<key>.ogg

用法 (在 CosyVoice 的虚拟环境里跑, 不在游戏发行包里):
  <CosyVoice>/.venv/bin/python tools/gen_voice.py --cosy <CosyVoice 目录> --events extracted/game/events \\
      --out extracted_voice/sichuan [--only talks1-1:10,12] [--limit N] [--shard i/n --threads N]
key = 剧本 text 指令原文 (含 %C %N 等控制码, UTF-8) 的 md5 前 16 位, 和 Game.voice_key 一致; 已有的跳过 (可中断续跑)。
只配有说话人前缀「名字：」的对白; 旁白字幕 (%S5 年代字幕等) 和「任务更新」这类系统提示不配。
音色: 不克隆真人, 参考音频用 CosyVoice-300M-SFT 的预设音色 (中文女 / 中文男) 合成, 可降调做老人;
  方言用 CosyVoice3 instruct2 固定指令「请用四川话表达。」(只有 cosyvoice/utils/common.py 里列出的指令有效)。
台词用原文, 只换口音 (试点时比较过改写成川话说法, 用户选了原文)。几个进程同时跑: --shard 0/4 … 3/4, 参考音色先单独生成好 (make_refs)。
打包成创意工坊 mod: make voice-pod → out/四川话配音.pod
"""
import argparse
import hashlib
import json
import os
import re
import sys

# 要 soundfile ≥ 0.13 (写 Vorbis 带压缩级别)
INSTRUCT = {'sichuan': 'You are a helpful assistant. 请用四川话表达。<|endofprompt|>',
            'minnan': 'You are a helpful assistant. 请用闽南话表达。<|endofprompt|>'}   # 台湾话 = 闽南话 (CosyVoice3 没有单独的台湾话指令)
REF_TEXT = '今天天气很好，我们一起去山上看看风景吧。'
# 参考音色: SFT 预设音色 + 变调 (半音)
VOICES = {
    'girl': ('中文女', 1.0),     # 车芸
    'woman': ('中文女', 0),      # 慕容诗、一般女性
    'lady': ('中文女', -1.5),    # 嬴诗
    'young': ('中文男', 1.0),    # 桓远之
    'man': ('中文男', 0),
    'old': ('中文男', -3.0),     # 老人
    'oldwoman': ('中文女', -3.0),
}
CAST = {
    '车芸': 'girl', '慕容诗': 'woman', '嬴诗': 'lady', '桓远之': 'young',
    '端木老人': 'old', '墨衡': 'old', '晋文公': 'old', '百里奚': 'old', '老者': 'old', '老人': 'old', '樵叟': 'old',
    '女子': 'woman', '水曜使者': 'woman', '木曜使者': 'woman', '慕舆柔': 'woman', '赢诗': 'lady',
    # 普通 NPC: 名字里看不出男女、但人名表里的名字明显是女性的
    '卡娜': 'woman', '水琳': 'woman', '齐姜': 'woman', '关美': 'woman', '娥氏': 'woman', '小娥': 'girl',
    '金铃': 'girl', '银铃': 'girl', '小雪': 'girl', '美美': 'girl', '牵牵': 'girl', '林香': 'woman',
    '李眉': 'woman', '赛妙': 'woman', '可儿': 'girl', '琳儿': 'girl', '张伶': 'woman', '小花': 'girl',
}
DEFAULT_VOICE = {'女': 'girl', '男': 'man'}
SKIP = {'任务更新'}
_CODE = re.compile(r'%[SCD]\d|%[NOAB]')
_OPTS = re.compile(r'%B[^.]*\.?')   # 选项 (%B标签.): 不念


def key(raw):
    return hashlib.md5(raw.encode('utf-8')).hexdigest()[:16]


def parse(raw):
    """→ (说话人, 台词) ; 不是「名字：」开头的对白返回 None"""
    s = _CODE.sub('', _OPTS.sub('', raw)).strip()
    m = re.match(r'^([^：\s]{1,8})：(.+)$', s, re.S)
    if not m:
        return None
    name, line = m.group(1), m.group(2).strip()
    if line in SKIP or not re.search(r'[一-鿿]', line):
        return None
    return name, line


def parse_plain(raw, who):
    """没有「名字：」前缀的台词 (说话人另外查到) → (说话人, 台词); 系统提示 (【得到…】等) 返回 None"""
    s = _CODE.sub('', _OPTS.sub('', raw)).strip()
    if not s or s.startswith('【') or '得到' in s[:4] or s in SKIP or not re.search(r'[一-鿿]', s):
        return None
    return who, s


def tts_text(line, items=None):
    """给 TTS 的文本: 全角空格去掉, ∼ 换成 ～, ── 换成 ……"""
    t = re.sub(r'%T(\d+)\.?', lambda m: str((items or {}).get(m.group(1), '')), line)   # 物品名
    t = t.replace('∼', '～').replace('　', '')
    t = re.sub(r'─+', '……', t)
    return re.sub(r'\s+', '', t)


SYS_ACTORS = {0, 255, 0xff01}   # 提示框 / 地名字幕 / 选项框, 不是人说话


def names_of(events_dir):
    """names.json (提取出来的人名表 people: 人物号 → 名字, 物品表 items 给 %T 用)"""
    p = os.path.join(os.path.dirname(os.path.normpath(events_dir)), 'names.json')
    return json.load(open(p, encoding='utf-8')) if os.path.exists(p) else {'people': {}, 'items': {}}


def lines(events_dir, only):
    """按剧本顺序给出 (原文, 说话人, 台词); only = {文件名: {事件号}} 或 None
    说话人: 台词自带「名字：」前缀 > 前一条 set_caption 的人物号 (对话框上的名字) > text 的角色号 (角色号就是人物号,
    例 1 = 车芸) ; 都没有或是系统框 (SYS_ACTORS) 的不配 —— 名字都查提取出来的人名表, 不猜"""
    people = names_of(events_dir)['people']
    seen = set()
    for fn in sorted(os.listdir(events_dir)):
        if not fn.endswith('.json'):
            continue
        name = fn[:-5]
        if only is not None and name not in only:
            continue
        d = json.load(open(os.path.join(events_dir, fn), encoding='utf-8'))
        for eid, ck in sorted(d['events'].items(), key=lambda x: int(x[0])):
            if only is not None and only[name] and int(eid) not in only[name]:
                continue
            cap = None
            for ins in d['codes'][ck]:
                if ins[1] == 'set_caption':
                    cap = int(ins[2])
                if ins[1] != 'text':
                    continue
                c0, cap = cap, None   # 标题只管下一条 text (EventVM: 显示后清空)
                raw = str(ins[12]) if len(ins) > 12 else ''   # [位置, 'text', 角色, 参数 ×9, 原文] (EventVM 的 a[10])
                if raw in seen:
                    continue
                p = parse(raw)
                if p is None:
                    who = people.get(str(c0)) if c0 is not None else (
                        None if int(ins[2]) in SYS_ACTORS else people.get(str(int(ins[2]))))
                    p = parse_plain(raw, who) if who else None
                if p:
                    seen.add(raw)
                    yield raw, p[0], p[1]


OGG_LEVEL = 0.5   # libsndfile Vorbis 压缩级别 (0 最好 – 1 最小); 单声道 24kHz (CosyVoice 原样) 约 5KB/秒


def to_ogg(wav, sr, out):
    """float 张量 → 单声道 Ogg Vorbis (Godot AudioStreamOggVorbis 能读; 打进 .pod 要小)"""
    import soundfile as sf
    w = wav.squeeze(0).numpy() if hasattr(wav, 'numpy') else wav
    sf.write(out + '.part', w, sr, format='OGG', subtype='VORBIS', compression_level=OGG_LEVEL)
    os.replace(out + '.part', out)


def make_refs(cosy, d):
    """SFT 预设音色合成参考音频 (变调用 librosa)"""
    import soundfile as sf
    need = [v for v in VOICES if not os.path.exists(os.path.join(d, v + '.wav'))]
    if not need:
        return
    from cosyvoice.cli.cosyvoice import AutoModel
    sft = AutoModel(model_dir=os.path.join(cosy, 'pretrained_models', 'CosyVoice-300M-SFT'))
    for v in need:
        spk, semi = VOICES[v]
        w = next(sft.inference_sft(REF_TEXT, spk, stream=False))['tts_speech'].squeeze(0).numpy()
        if semi:
            import librosa
            w = librosa.effects.pitch_shift(w, sr=sft.sample_rate, n_steps=semi)
        sf.write(os.path.join(d, v + '.wav'), w, sft.sample_rate)
    del sft


def voice_of(name):
    if name in CAST:
        return CAST[name]
    if '．' in name:   # 「称号．本名」: 两段都查 CAST, 再按称号判断 (晋文公．姬重耳 不能因为「姬」算女声)
        a, b = name.split('．', 1)
        return CAST.get(b) or voice_of(a)
    if re.search(r'婆|妪', name):
        return 'oldwoman'
    if re.search(r'翁|叟|老', name):
        return 'old'
    return 'woman' if re.search(r'女|娘|姑|妃|姬|姐|妹|妇|婶|姨|嫂|夫人|丫环', name) else 'man'


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument('--cosy', required=True)
    ap.add_argument('--events', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--lang', default='sichuan', choices=sorted(INSTRUCT))
    ap.add_argument('--only', help='文件名:事件号,事件号 (多个用 ; 分隔), 例 talks1-1:10,12')
    ap.add_argument('--limit', type=int, default=0)
    ap.add_argument('--shard', default='0/1', help='i/n: 只做第 i 份 (共 n 份, 按顺序轮流分), 几个进程同时跑')
    ap.add_argument('--threads', type=int, default=0, help='torch 线程数 (几个进程同时跑时调小)')
    a = ap.parse_args(argv)
    sys.path[:0] = [a.cosy, os.path.join(a.cosy, 'third_party', 'Matcha-TTS')]
    only = None
    if a.only:
        only = {}
        for part in a.only.split(';'):
            f, _, ids = part.partition(':')
            only[f] = {int(x) for x in ids.split(',') if x}
    todo = list(lines(a.events, only))
    if a.limit:
        todo = todo[:a.limit]
    si, sn = (int(x) for x in a.shard.split('/'))
    todo = todo[si::sn]
    if a.threads:
        import torch
        torch.set_num_threads(a.threads)
    os.makedirs(a.out, exist_ok=True)
    refs = os.path.join(a.out, '_ref')
    os.makedirs(refs, exist_ok=True)
    make_refs(a.cosy, refs)
    from cosyvoice.cli.cosyvoice import AutoModel
    cv = AutoModel(model_dir=os.path.join(a.cosy, 'pretrained_models', 'Fun-CosyVoice3-0.5B'))
    inst = INSTRUCT[a.lang]

    items = names_of(a.events).get('items', {})

    def say(text, voice, out):
        w = next(cv.inference_instruct2(tts_text(text, items), inst, os.path.join(refs, voice + '.wav'), stream=False))['tts_speech']
        to_ogg(w, cv.sample_rate, out)

    index = {}
    ip = os.path.join(a.out, 'index.json' if sn == 1 else 'index.%d.json' % si)
    if os.path.exists(ip):
        index = json.load(open(ip, encoding='utf-8'))
    for i, (raw, name, line) in enumerate(todo, 1):
        k = key(raw)
        out = os.path.join(a.out, k + '.ogg')
        index[k] = {'who': name, 'text': line}
        if not os.path.exists(out):
            say(line, voice_of(name), out)
        print('[%d/%d] %s %s：%s' % (i, len(todo), k, name, line), flush=True)
        if i % 20 == 0:
            with open(ip, 'w', encoding='utf-8') as f:
                json.dump(index, f, ensure_ascii=False, indent=1)
    with open(ip, 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False, indent=1)


if __name__ == '__main__':
    main()
