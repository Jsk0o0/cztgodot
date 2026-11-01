extends RefCounted
## 原版 .TEX 贴图 → Image (同 tools/tex2png.py decode_tex)
## 解压后: u16 0xFFFF, u16 宽, u16 高, u16 flags (0x0010 不透明 / 0x8010 带透明)
##   逐行: u16 行头 = (0x8000 若行首为不透明段) | 行总字节数 (含行头); [若 0x8000: u16 n + n 个像素]
##         重复: u16 0xC000|透明跳过数, u16 n, n 个像素。像素 RGB555
## 有透明像素 (flags & 0x8000, 或行内有跳过段) 输出 RGBA8, 否则 RGB8; 分量 = v × 255 / 31 (取整同 numpy 整除)

const Lzo := preload("res://scripts/extract/lzo.gd")

static var _c5: PackedByteArray   # 5 位 → 8 位


static func _lut() -> void:
	if _c5.is_empty():
		_c5.resize(32)
		for v in 32:
			_c5[v] = v * 255 / 31


static func load_file(path: String) -> Image:
	var t := Lzo.load_file(path)
	return decode(t) if t.size() else null


## 数据不完整返回 null (Python 版此时抛异常, 记为解码失败)
static func decode(t: PackedByteArray) -> Image:
	_lut()
	var sz := t.size()
	if sz < 8 or t.decode_u16(0) != 0xFFFF:
		return null
	var w := t.decode_u16(2)
	var h := t.decode_u16(4)
	var flags := t.decode_u16(6)
	var rgba := PackedByteArray()
	rgba.resize(w * h * 4)   # 先按 RGBA 写, alpha 默认 0 (透明)
	var any_hole := false
	var p := 8
	for y in h:
		if p + 2 > sz:
			return null
		var head := t.decode_u16(p)
		var end := p + (head & 0x3FFF)
		var q := p + 2
		var x := 0
		var row := y * w * 4
		var first := (head & 0x8000) != 0
		while q < end:
			if q + 2 > sz:
				return null
			if not first:
				var tok := t.decode_u16(q)
				if tok & 0xC000 != 0xC000:
					break
				q += 2
				var skip := tok & 0x3FFF
				if skip:
					any_hole = true
				x += skip
			first = false
			if q + 2 > sz:
				return null
			var n := t.decode_u16(q)
			q += 2
			if q + 2 * n > sz or x + n > w:
				return null
			var o := row + x * 4
			for k in n:
				var v := t[q] | (t[q + 1] << 8)
				q += 2
				rgba[o] = _c5[(v >> 10) & 31]
				rgba[o + 1] = _c5[(v >> 5) & 31]
				rgba[o + 2] = _c5[v & 31]
				rgba[o + 3] = 255
				o += 4
			x += n
		if x < w:
			any_hole = true
		p = end
	if flags & 0x8000 or any_hole:
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
	img.convert(Image.FORMAT_RGB8)
	return img
