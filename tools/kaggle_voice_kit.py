"""打 Kaggle 配音任务包: out/kaggle_voice/dataset/ (上传成 Kaggle 私有数据集) + out/kaggle_voice/czt_voice.ipynb

dataset/: todo_<方言>.json (还没生成的句子: key + TTS 文本 + 音色; 含原版台词, 数据集必须设成私有)、
          refs/*.wav (参考音色, 和本机同一组)、kaggle_voice_run.py
四川话清单倒序 (从剧情后面往前), 和本机正在顺序生成的错开, 两边不重复。
用法: python3 tools/kaggle_voice_kit.py [--langs sichuan,minnan]
"""
import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_voice  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'out', 'kaggle_voice')
COSY_COMMIT = '074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc'   # 本机 ~/tts/CosyVoice 的版本
MODEL_REPO = 'FunAudioLLM/Fun-CosyVoice3-0.5B-2512'


def todo(lang, events, items, reverse):
    have = os.path.join(ROOT, 'extracted_voice', lang)
    out = []
    for raw, who, line in gen_voice.lines(events, None):
        k = gen_voice.key(raw)
        if os.path.exists(os.path.join(have, k + '.ogg')):
            continue
        out.append({'key': k, 'who': who, 'voice': gen_voice.voice_of(who), 'text': gen_voice.tts_text(line, items)})
    if reverse:
        out.reverse()
    return {'lang': lang, 'instruct': gen_voice.INSTRUCT[lang], 'ogg_level': gen_voice.OGG_LEVEL, 'lines': out}


NB_SETUP = r'''# 1) 依赖 (Kaggle 自带 torch / CUDA, 不重装)
import subprocess, sys
pkgs = ["conformer==0.3.2", "diffusers==0.29.0", "hydra-core==1.3.2", "HyperPyYAML==1.2.3", "omegaconf==2.3.0",
        "inflect==7.3.1", "transformers==4.51.3", "x-transformers==2.11.24", "wetext==0.0.4", "lightning",
        "librosa", "soundfile==0.13.1", "onnxruntime-gpu", "openai-whisper", "modelscope", "einops", "rootutils",
        "tiktoken", "unidecode", "rich", "gdown", "wget", "pyworld"]
subprocess.run([sys.executable, "-m", "pip", "install", "-q"] + pkgs, check=True)
subprocess.run("git clone -q https://github.com/FunAudioLLM/CosyVoice.git /kaggle/tmp/CosyVoice && cd /kaggle/tmp/CosyVoice && "
               "git checkout -q %s && git submodule update --init --recursive -q", shell=True, check=True)
from huggingface_hub import snapshot_download
snapshot_download("%s", local_dir="/kaggle/tmp/model",
                  allow_patterns=["*.yaml", "*.json", "llm.pt", "flow.pt", "hift.pt", "campplus.onnx",
                                  "speech_tokenizer_v3.onnx", "CosyVoice-BlankEN/*", "asset/*"])
print("准备好了")
'''


NB_RUN = r'''# 2) 生成 (每块 GPU 一个进程; 到点自动停, 已生成的保存在 Output 里)
import glob, os, subprocess, sys, time, torch
src = os.path.dirname(glob.glob("/kaggle/input/**/todo_%s.json" % LANG, recursive=True)[0])
out = "/kaggle/working/" + LANG
n = max(1, torch.cuda.device_count())
deadline = time.time() + HOURS * 3600
procs = []
for i in range(n):
    env = dict(os.environ, CUDA_VISIBLE_DEVICES=str(i))
    log = open("/kaggle/working/log_%s_%d.txt" % (LANG, i), "w")
    procs.append(subprocess.Popen([sys.executable, src + "/kaggle_voice_run.py", "--cosy", "/kaggle/tmp/CosyVoice",
        "--model", "/kaggle/tmp/model", "--todo", src + "/todo_%s.json" % LANG, "--refs", src + "/refs",
        "--out", out, "--shard", "%d/%d" % (i, n), "--deadline", str(deadline)], env=env, stdout=log, stderr=subprocess.STDOUT))
while any(p.poll() is None for p in procs):
    time.sleep(300)
    print(time.strftime("%H:%M"), "已生成", len(glob.glob(out + "/*.ogg")), "句", flush=True)
print("退出码", [p.returncode for p in procs])
'''

NB_ZIP = r'''# 3) 打包下载: Output 里的 voice_<方言>.zip
import shutil
print(shutil.make_archive("/kaggle/working/voice_" + LANG, "zip", "/kaggle/working/" + LANG))
'''


def notebook(path):
    cell = lambda src: {'cell_type': 'code', 'metadata': {}, 'execution_count': None, 'outputs': [],
                        'source': src.splitlines(True)}
    md = {'cell_type': 'markdown', 'metadata': {}, 'source': [
        '# 苍之涛 对白配音 (CosyVoice3)\n',
        '右侧 Settings: Accelerator 选 **GPU T4 x2**, Internet 打开; Add Input 加上私有数据集。\n',
        '改第一格的 LANG, 然后右上角 **Save Version → Save & Run All (Commit)**, 关掉网页也会跑完。\n']}
    nb = {'nbformat': 4, 'nbformat_minor': 5,
          'metadata': {'kernelspec': {'name': 'python3', 'display_name': 'Python 3', 'language': 'python'}},
          'cells': [md, cell('LANG = "sichuan"   # 或 "minnan" (台湾话 / 闽南话)\nHOURS = 11         # Kaggle 单次最多 12 小时, 留 1 小时装环境和打包\n'),
                    cell(NB_SETUP % (COSY_COMMIT, MODEL_REPO)), cell(NB_RUN), cell(NB_ZIP)]}
    json.dump(nb, open(path, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--langs', default='sichuan,minnan')
    ap.add_argument('--events', default=os.path.join(ROOT, 'extracted', 'game', 'events'))
    a = ap.parse_args()
    ds = os.path.join(OUT, 'dataset')
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(os.path.join(ds, 'refs'))
    items = gen_voice.names_of(a.events).get('items', {})
    for lang in a.langs.split(','):
        t = todo(lang, a.events, items, reverse=(lang == 'sichuan'))
        json.dump(t, open(os.path.join(ds, 'todo_%s.json' % lang), 'w', encoding='utf-8'), ensure_ascii=False)
        print('%s: %d 句' % (lang, len(t['lines'])))
    for f in os.listdir(os.path.join(ROOT, 'extracted_voice', 'sichuan', '_ref')):
        shutil.copy(os.path.join(ROOT, 'extracted_voice', 'sichuan', '_ref', f), os.path.join(ds, 'refs', f))
    shutil.copy(os.path.join(ROOT, 'tools', 'kaggle_voice_run.py'), ds)
    notebook(os.path.join(OUT, 'czt_voice.ipynb'))
    shutil.make_archive(os.path.join(OUT, 'czt-voice-data'), 'zip', ds)
    print('→', OUT)


if __name__ == '__main__':
    main()
