"""在 Kaggle (免费 GPU) 上跑对白配音: tools/kaggle_voice_kit.py 打好的任务清单 → <out>/<key>.ogg

和本机 tools/gen_voice.py 用同一个模型 (Fun-CosyVoice3-0.5B, fp32)、同一组参考音色、同一条方言指令,
只是不需要游戏数据: 清单里已经是 TTS 文本 + 音色。每块 GPU 一个进程 (--shard i/n), 已有的跳过。
python kaggle_voice_run.py --cosy <CosyVoice> --model <模型目录> --todo todo_sichuan.json --refs refs --out out/sichuan --shard 0/2
"""
import argparse
import json
import os
import sys
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--cosy', required=True)
    ap.add_argument('--model', required=True)
    ap.add_argument('--todo', required=True)
    ap.add_argument('--refs', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--shard', default='0/1')
    ap.add_argument('--deadline', type=float, default=0, help='到这个 unix 时间就停 (Kaggle 单次最多 12 小时)')
    a = ap.parse_args()
    sys.path[:0] = [a.cosy, os.path.join(a.cosy, 'third_party', 'Matcha-TTS')]
    import soundfile as sf
    from cosyvoice.cli.cosyvoice import AutoModel
    t = json.load(open(a.todo, encoding='utf-8'))
    si, sn = (int(x) for x in a.shard.split('/'))
    items = t['lines'][si::sn]
    os.makedirs(a.out, exist_ok=True)
    cv = AutoModel(model_dir=a.model)
    t0 = time.time()
    done = 0
    for i, it in enumerate(items, 1):
        if a.deadline and time.time() > a.deadline:
            print('到时间了, 停在 %d/%d' % (i, len(items)), flush=True)
            break
        out = os.path.join(a.out, it['key'] + '.ogg')
        if os.path.exists(out):
            continue
        w = next(cv.inference_instruct2(it['text'], t['instruct'], os.path.join(a.refs, it['voice'] + '.wav'), stream=False))['tts_speech']
        sf.write(out + '.part', w.squeeze(0).cpu().numpy(), cv.sample_rate, format='OGG', subtype='VORBIS',
                 compression_level=t.get('ogg_level', 0.5))
        os.replace(out + '.part', out)
        done += 1
        if done % 20 == 0:
            el = time.time() - t0
            print('[%d/%d] %.1f 句/分钟' % (i, len(items), done / el * 60), flush=True)
    print('完成 %d 句' % done, flush=True)


if __name__ == '__main__':
    main()
