"""生成 .pod 主密钥的两份本地副本 (make pod-key)。两个文件都在 .gitignore 里, 不进仓库。

  tools/podtool/pod/masterkey.go   打包端 (podtool、工坊编辑器)
  godot/scripts/pod_key.gd         游戏端 (pod.gd 运行时加载, 没有它时只是读不了 .pod)

已有 masterkey.go 时沿用其中的密钥, 只补游戏端, 这样已打好的 .pod 仍然能读。
注意: 两端密钥必须相同; 换密钥后, 旧密钥打的 .pod 全部读不了。
"""
import os
import re
import secrets

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
GO = os.path.join(ROOT, 'tools', 'podtool', 'pod', 'masterkey.go')
GD = os.path.join(ROOT, 'godot', 'scripts', 'pod_key.gd')

GO_TMPL = '''package pod

import "encoding/hex"

// 本地生成 (tools/gen_pod_key.py), 不进仓库。游戏端 godot/scripts/pod_key.gd 存同一把。
// 主密钥只用来包一层每个 pod 随机生成的内容密钥。
// 本地加密的上限: 有心人反编译游戏能拿到它 —— 目的只是防普通玩家拆包和改包 (见 format.go)。
var masterKey, _ = hex.DecodeString("%s")
'''

GD_TMPL = '''extends RefCounted
## 本地生成 (tools/gen_pod_key.py), 不进仓库。主密钥分段存放, 拼接顺序见 pod.gd 的 _master()。
const K := ["%s", "%s", "%s", "%s"]
'''


def main():
    if os.path.exists(GO):
        src = open(GO, encoding='utf-8').read()
        key = re.search(r'DecodeString\("([0-9a-fA-F]{64})"\)', src).group(1).lower()
    else:
        key = secrets.token_hex(32)
        with open(GO, 'w', encoding='utf-8') as f:
            f.write(GO_TMPL % key)
        print('已生成新主密钥:', os.path.relpath(GO, ROOT))
    # pod.gd 按 K[3] + K[1] + K[2] + K[0] 拼接
    a, b, c, d = key[:16], key[16:32], key[32:48], key[48:]
    with open(GD, 'w', encoding='utf-8') as f:
        f.write(GD_TMPL % (d, b, c, a))
    print('已写入:', os.path.relpath(GD, ROOT))


if __name__ == '__main__':
    main()
