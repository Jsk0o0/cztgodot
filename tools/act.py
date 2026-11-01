"""轩辕剑苍之涛 ACT/*.act 动作表

文件: u16 0xF001, u16 ?, u16 ?, 之后是 3000 个槽的稠密索引: 第 n 槽在文件偏移 12n-2 处, (u32 长度, u32 偏移, u32 ACT 号)
  (exe 0x41cd27 → 0x41d039)。ACT 号 = 类别×3000 + 槽号, 类别 = 文件 (0 all_char, 1 all_item, 2 all_magic, 3 all_sys, 4/5 all_map1/2)。
3D 角色 (all_char.act) 的一个 ACT = 一个角色, 战斗单位的 ACT 号 = ObjDATA 编号 + 1 (车芸 1, 嬴诗 2, 桓远之 3, 云狐 11);
特效 (例 8101) 也是 ACT: 8101 → all_magic.act 第 2101 槽, 由 tools/effects.py 处理。 数据: u16 动作数, 动作数×(u32 偏移, u16 长度), 每个动作是一串双字母指令:
  PT u8? / AT u16 帧数 / XB 8×f32 包围盒 / FR u16 模型编号, 之后是逐帧播放表:
  AP u16 = 这一帧显示 PLY 第 n 帧 (AP 个数 = AT; 游戏 35 帧/秒, 见事件指令 0x88), DE = 帧结束, VW u16 = 在这一帧播放音效 n
  结尾 VO = 回到开头循环, 2O = 动作结束 (停在末帧)
  (例: 嬴诗第 56 号动作只播 PLY 的第 23–79 帧, 第 67 号从 107 帧里挑 90 帧)
  单字节记号: g\0 = 施术者标志 (ATK 0x76 wait_caster_flag 等它, 之后放特效), e\0 / d\0 = 命中结算的时刻
  (例: 断意诀第 67 号动作 g 在第 10/37/52/69 帧, e 在 43/58/75 帧 —— 三次火花与三次命中)
模型编号 → 文件: 类别 = 编号 // 3000 (0 CHR, 1 ITM, 2 MGC, 3 SYS, 4 MAP (场景 .WLD), 5 OTH), 文件 = 前缀 + (编号 % 3000) 五位数
  (地图物件 all_map2.act 的 FR 多为 15000+ → OTH: 例 出入口箭头 16005 → OTH00038, 宝箱 16002 → OTH00039)
  (exe 0x42ee74 / 0x41efc2 都按 3000 分类; 例: 嬴诗第 67 号动作 FR=4890 → ITM01890, 90 帧, 与 AT 一致)
事件脚本 / ATK 脚本里的「姿势编号」(set_pose) 就是这里的动作下标。
"""
import struct

PREFIX = ['CHR', 'ITM', 'MGC', 'SYS', 'MAP', 'OTH']
ACT_FILES = ['all_char.act', 'all_item.act', 'all_magic.act', 'all_sys.act', 'all_map1.act', 'all_map2.act']


def model_file(fr):
    return '%s%05d' % (PREFIX[fr // 3000], fr % 3000)


def read_index(data):
    """{槽号: (偏移, 长度)}, 只含非空槽"""
    out = {}
    for n in range(1, 3000):
        if 12 * n + 10 > len(data):
            break
        size, off, _ = struct.unpack_from('<3I', data, 12 * n - 2)
        if size and off:
            out[n] = (off, size)
    return out


# ACT 指令操作数 (同 tools/effects.py OPS)
ACT_OPS = {b'PT': 'B', b'AT': 'H', b'XB': '8f', b'FR': 'H', b'AP': 'H', b'OC': '4H', b'CS': '3f', b'TR': '3H',
           b'VW': 'H', b'XF': 'I', b'PL': '3H', b'DS': 'H', b'IS': '6H', b'PS': 'H', b'XT': 'I3H', b'XV': '',
           b'PD': '3f', b'PC': '3f', b'AC': '3fB', b'DC': '3fB', b'DE': '', b'VO': '', b'2O': ''}


def actions(data, act_id):
    """返回 {动作下标: {'model': 文件名, 'frames': 帧数, 'fr': 原始编号}}"""
    off, size = read_index(data)[act_id % 3000]
    d = data[off:off + size]
    cnt = struct.unpack_from('<H', d, 0)[0]
    res = {}
    for q in range(cnt):
        o, ln = struct.unpack_from('<IH', d, 2 + 6 * q)
        if not ln:
            continue
        s = d[o:o + ln]
        p_fr, p_at = s.find(b'FR'), s.find(b'AT')
        if p_fr < 0:
            continue
        fr = struct.unpack_from('<H', s, p_fr + 2)[0]
        at = struct.unpack_from('<H', s, p_at + 2)[0] if p_at >= 0 else 0
        aps, sounds, marks, i = [], [], [], p_fr + 4
        # 一个动作可以有多段 FR (例: 车芸第 99 号动作 FR 452/453/454, 帧号各段都从 0 起): 每个 AP 属于它前面最近的 FR
        apf, fr_cur = [], fr
        # 每帧变换 (原版 ACT 播放器 0x41d1e3): AP 起新的一帧时 CS 缩放复位为 1、OC 颜色复位为 0xFFFFFFFF;
        # PD 位移 / TR 旋转 / XF 混合方式不复位。绘制 (0x495255 + 0x414758):
        #   顶点 = Rz(TR.z)·Ry(TR.y + 朝向)·Rx(TR.x) · (CS × v + PD × CS) + 单位位置; 颜色 = OC (ARGB), 混合 = XF & 0xF (0 不透明 / 1 加法 / 2 半透明)
        # 以前只认 AP / VW / 记号, 其余每次跳 2 字节, 会把浮点数据误读成指令; PD 没解析 → 嬴诗 穿迷雾 (动作 61) 冲过敌人的位移丢了
        cur = {'s': [1.0, 1.0, 1.0], 'o': [0.0, 0.0, 0.0], 'r': [0, 0, 0], 'c': [255, 255, 255, 255], 'x': 0}
        frames_x = []
        while i + 2 <= len(s):
            t = s[i:i + 2]
            if t == b'ER':   # 变长: u16 个数 n + n × 3 个 u16 (0x41d736)
                n_er = struct.unpack_from('<H', s, i + 2)[0]
                i += 4 + 6 * n_er
                continue
            if t in ACT_OPS:
                fmt = '<' + ACT_OPS[t]
                v = struct.unpack_from(fmt, s, i + 2) if ACT_OPS[t] else ()
                i += 2 + struct.calcsize(fmt)
                if t == b'AP':  # 每个 AP 一帧 (个数 = AT)
                    if aps:
                        frames_x.append(dict(cur))
                    aps.append(v[0])
                    apf.append(fr_cur)
                    cur = dict(cur, s=[1.0, 1.0, 1.0], c=[255, 255, 255, 255])
                elif t == b'FR':
                    fr_cur = v[0]
                elif t == b'VW':  # 音效挂在当前帧
                    sounds.append((max(len(aps) - 1, 0), v[0]))
                elif t == b'CS':
                    cur['s'] = [round(x, 4) for x in v]
                elif t == b'PD':
                    cur['o'] = [round(x, 3) for x in v]
                elif t == b'TR':
                    cur['r'] = list(v)
                elif t == b'OC':
                    cur['c'] = [x & 0xFF for x in v]   # 每个分量 2 字节, 取低字节 (0x41d500)
                elif t == b'XF':
                    cur['x'] = v[0]
                elif t == b'ER':
                    pass
            elif t in (b'g\0', b'e\0', b'd\0'):  # 记号: g = 施术者标志 (ATK 0x76 等它), e/d = 命中结算
                marks.append((max(len(aps) - 1, 0), t[:1].decode()))
                i += 2
            else:
                i += 2
        if aps:
            frames_x.append(dict(cur))
        # 只在有非默认值时输出: [[帧, sx, sy, sz, ox, oy, oz, rx, ry, rz, a, r, g, b, xf]], 与上一帧相同的省略
        xform, last = [], None
        if any(f['s'] != [1.0, 1.0, 1.0] or f['o'] != [0.0, 0.0, 0.0] or f['r'] != [0, 0, 0] or f['c'] != [255, 255, 255, 255]
               or f['x'] for f in frames_x):
            for k, f in enumerate(frames_x):
                row = f['s'] + f['o'] + f['r'] + f['c'] + [f['x']]
                if row != last:
                    xform.append([k] + row)
                    last = row
        # XB (动作头部, 8 个 f32): 包围盒 min xyz, _, max xyz, _ (exe 0x431960: 单位包围盒 = XB + 位置, 召唤找空位时用)
        p_xb = s.find(b'XB', 0, p_fr)
        bbox = [round(x, 2) for x in struct.unpack_from('<8f', s, p_xb + 2)] if p_xb >= 0 else None
        res[q] = {'model': model_file(fr), 'frames': at, 'fr': fr, 'aps': aps, 'apf': apf, 'sounds': sounds, 'marks': marks, 'xform': xform,
                  'bbox': [bbox[0], bbox[1], bbox[2], bbox[4], bbox[5], bbox[6]] if bbox else None,
                  'loop': b'VO' in s}
    return res
