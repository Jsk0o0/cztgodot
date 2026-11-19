"""对白配音响度拉齐: <源目录>/*.ogg → <目标目录>/*.ogg (make voice-pod 打包前用; 源文件不动)

TTS 出来的语音偏小 (说话段 RMS 约 -24 dB), 背景音乐会盖过它。每句按「说话段」(去掉静音) 的 RMS 拉到 TARGET_RMS,
超过 KNEE 的峰值软压到 PEAK 以内; 目标文件比源文件新就跳过 (可反复跑)。要 soundfile ≥ 0.13 (CosyVoice 虚拟环境里有)。
用法: python tools/voice_norm.py extracted_voice/sichuan out/voice_mod/voice
"""
import os
import sys

import numpy as np
import soundfile as sf

TARGET_RMS = -14.0   # dBFS, 说话段 (用户: -18 还不够大声)
PEAK = -1.0          # dBFS, 软限幅的上限
KNEE = -6.0          # dBFS, 超过这个开始软压
OGG_LEVEL = 0.5      # 和 gen_voice.py 一样


def db(x):
    return 20 * np.log10(max(x, 1e-9))


def gain_of(w, sr):
    """说话段 RMS → 增益 (线性); 20ms 一帧, 比最响帧低 40dB 以上的算静音"""
    n = max(1, sr // 50)
    frames = w[:len(w) // n * n].reshape(-1, n) if len(w) >= n else w.reshape(1, -1)
    rms = np.sqrt((frames ** 2).mean(axis=1))
    act = rms[rms > rms.max() * 0.01]
    speech = np.sqrt((act ** 2).mean()) if len(act) else 0.0
    peak = np.abs(w).max()
    if speech <= 0 or peak <= 0:
        return 1.0
    return 10 ** ((TARGET_RMS - db(speech)) / 20)


def limit(w):
    """软限幅: KNEE 以下原样, 以上用 tanh 压到不超过 PEAK (拉响之后少数峰值不破音)"""
    k, p = 10 ** (KNEE / 20), 10 ** (PEAK / 20)
    a = np.abs(w)
    over = a > k
    out = w.copy()
    out[over] = np.sign(w[over]) * (k + (p - k) * np.tanh((a[over] - k) / (p - k)))
    return out


def main(src, dst):
    os.makedirs(dst, exist_ok=True)
    done = 0
    for f in sorted(os.listdir(src)):
        if not f.endswith('.ogg'):
            continue
        a, b = os.path.join(src, f), os.path.join(dst, f)
        if os.path.exists(b) and os.path.getmtime(b) >= os.path.getmtime(a):
            continue
        w, sr = sf.read(a, dtype='float32')
        if w.ndim > 1:
            w = w.mean(axis=1)
        w = limit(w * gain_of(w, sr))
        sf.write(b + '.part', w, sr, format='OGG', subtype='VORBIS', compression_level=OGG_LEVEL)
        os.replace(b + '.part', b)
        done += 1
    print('响度拉齐 %d 句 → %s' % (done, dst))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
