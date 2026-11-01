extends RefCounted
## 原版文字: Big5 解码 + 繁转简, 结果和 Python 工具 (bytes.decode('big5', 'replace') + opencc-python-reimplemented 't2s') 一致
## big5.bin: Python big5 解码器逐对记录 —— 下标 (首字节 − 0x80) × 256 + 次字节, 值 = 字符 (u16); 0xFFFF = 这一对不成字,
##   只吃掉首字节输出 U+FFFD, 次字节另行解码 (tools 生成时逐对断言过); 首字节 < 0x80 = ASCII
## 繁转简 (OpenCC t2s, 词典 TSPhrases + TSCharacters 同组, Apache-2.0, 见 data/text/OPENCC_NOTICE.txt):
##   先按标点 / 空白切段 (分隔符原样保留), 每段建一棵树: 对每本词典, 待处理的段从长到短、从左到右找第一个在词典里的子串,
##   换成译文 (多个译文取第一个), 左右剩下的部分以「本次长度」为上限继续找; 一本词典里换过的部分不再给下一本

const DIR := "res://data/text/"

static var _b5: PackedByteArray
static var _dicts: Array = []   # [[最长, 最短, {繁: 简}], ...] 依次 TSPhrases, TSCharacters
static var _sep := {}


static func _init_tables() -> void:
	if not _b5.is_empty():
		return
	_b5 = FileAccess.get_file_as_bytes(DIR + "big5.bin")
	for fn in ["TSPhrases.txt", "TSCharacters.txt"]:
		var d := {}
		var mx := 1
		var mn := 1000
		for line in FileAccess.get_file_as_string(DIR + fn).split("\n"):
			line = line.strip_edges()
			if line == "":
				continue
			var kv := line.split("\t")
			d[kv[0]] = kv[1]
			mx = maxi(mx, kv[0].length())
			mn = mini(mn, kv[0].length())
		_dicts.append([mx, mn, d])
	# 分隔符: 同 opencc.py split_chars_re (Python 的 \s 是 Unicode 空白)
	for c in "-,.?!*　，。、；：？！…“”‘’『』「」﹁﹂—－（）《》〈〉～．／＼︒︑︔︓︿﹀︹︺︙︐［﹇］﹈︕︖︰︳︴︽︾︵︶｛︷｝︸﹃﹄【︻】︼":
		_sep[c.unicode_at(0)] = true
	for cp in [9, 10, 11, 12, 13, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x85, 0xa0, 0x1680, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000]:
		_sep[cp] = true
	for cp in range(0x2000, 0x200b):
		_sep[cp] = true


## bytes.decode('big5', 'replace')
static func big5(b: PackedByteArray) -> String:
	_init_tables()
	var s := PackedInt32Array()
	var i := 0
	var n := b.size()
	while i < n:
		var c := b[i]
		if c < 0x80:
			s.append(c)
			i += 1
			continue
		if i + 1 < n:
			var v := _b5.decode_u16(((c - 0x80) * 256 + b[i + 1]) * 2)
			if v != 0xFFFF:
				s.append(v)
				i += 2
				continue
		s.append(0xFFFD)
		i += 1
	var out := ""
	for cp in s:
		out += char(cp)
	return out


## 到第一个 0 字节为止的 Big5 字符串 (b.split(b'\0')[0].decode)
static func big5z(b: PackedByteArray) -> String:
	var z := b.find(0)
	return big5(b.slice(0, z) if z >= 0 else b)


## OpenCC t2s
static func t2s(s: String) -> String:
	_init_tables()
	var out := ""
	var seg := ""
	for i in s.length():
		var ch := s[i]
		if _sep.has(ch.unicode_at(0)):
			if seg != "":
				out += _convert(seg)
				seg = ""
			out += ch
		else:
			seg += ch
	if seg != "":
		out += _convert(seg)
	return out


## 一段的转换: 节点 = [值, 左子, 右子, 长度上限]; 子节点为 -1 表示没有
static func _convert(s: String) -> String:
	var nodes: Array = [[s, -1, -1, 0]]
	var work: Array = [0]
	var unmatched: Array = []
	for td in _dicts:
		while not work.is_empty():
			var k: int = work.pop_back()
			var nd: Array = nodes[k]
			var r := _find(nd[0], td, nd[3])
			if r.is_empty():
				unmatched.append(k)
				nd[3] = 0
				continue
			nd[0] = r[0]
			nd[3] = 0
			if r[1] != "":
				nodes.append([r[1], -1, -1, r[3]])
				nd[1] = nodes.size() - 1
				work.append(nd[1])
			if r[2] != "":
				nodes.append([r[2], -1, -1, r[3]])
				nd[2] = nodes.size() - 1
				work.append(nd[2])
		var t := work
		work = unmatched
		unmatched = t
	# 中序遍历
	var res := ""
	var stack: Array = []
	var cur := 0
	while true:
		while cur >= 0:
			stack.append(cur)
			cur = nodes[cur][1]
		if stack.is_empty():
			break
		cur = stack.pop_back()
		res += nodes[cur][0]
		cur = nodes[cur][2]
	return res


## 返回 [译文, 左边, 右边, 本次长度]; 没找到返回 []
static func _find(s: String, td: Array, hint: int) -> Array:
	var n := s.length()
	var tl := mini(n, int(td[0]))
	if hint:
		tl = mini(tl, hint)
	var d: Dictionary = td[2]
	while tl >= int(td[1]):
		for i in n - tl + 1:
			var sub := s.substr(i, tl)
			if d.has(sub):
				var v: String = d[sub]
				return [v.split(" ")[0], s.substr(0, i), s.substr(i + tl), tl]
		tl -= 1
	return []
