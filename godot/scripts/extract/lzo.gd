extends RefCounted
## LZO1X 解压 (同 tools/lzo1x.py); 原版 .TEX / .WLD / .tsw 等文件 = [u32 解压大小][u32 压缩大小][LZO1X 数据]
## 数据不完整 (读到输入末尾之外、回溯到输出开头之前) 返回空数组 —— Python 版此时抛 IndexError


## 读文件并解压; 失败返回空数组
static func load_file(path: String) -> PackedByteArray:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 8:
		return PackedByteArray()
	var u := b.decode_u32(0)
	var c := b.decode_u32(4)
	return decompress(b.slice(8, 8 + c), u)


static func decompress(src: PackedByteArray, out_size := 0) -> PackedByteArray:
	var n := src.size()
	var o := PackedByteArray()
	if out_size > 0:
		o.resize(out_size)
	var op := 0
	var ip := 0
	var state := 0
	if n == 0:
		return PackedByteArray()
	var t := src[ip]
	if t > 17:
		ip += 1
		t -= 17
		if ip + t > n:
			return PackedByteArray()
		op = _lit(o, op, src, ip, t)
		ip += t
		state = 4 if t >= 4 else t
	while true:
		if ip >= n:
			return PackedByteArray()
		t = src[ip]
		ip += 1
		var ref := 0
		var l := 0
		var st := 0
		if t < 16:
			if state == 0:
				if t == 0:
					while ip < n and src[ip] == 0:
						t += 255
						ip += 1
					if ip >= n:
						return PackedByteArray()
					t += 15 + src[ip]
					ip += 1
				t += 3
				if ip + t > n:
					return PackedByteArray()
				op = _lit(o, op, src, ip, t)
				ip += t
				state = 4
				continue
			if ip >= n:
				return PackedByteArray()
			if state == 4:
				ref = op - 1 - 0x800 - (t >> 2) - (src[ip] << 2)
				l = 3
			else:
				ref = op - 1 - (t >> 2) - (src[ip] << 2)
				l = 2
			ip += 1
			st = t & 3
		elif t >= 64:
			if ip >= n:
				return PackedByteArray()
			ref = op - 1 - ((t >> 2) & 7) - (src[ip] << 3)
			ip += 1
			l = (t >> 5) + 1
			st = t & 3
		elif t >= 32:
			l = t & 31
			if l == 0:
				while ip < n and src[ip] == 0:
					l += 255
					ip += 1
				if ip >= n:
					return PackedByteArray()
				l += 31 + src[ip]
				ip += 1
			if ip + 2 > n:
				return PackedByteArray()
			var d := src[ip] | (src[ip + 1] << 8)
			ip += 2
			ref = op - 1 - (d >> 2)
			l += 2
			st = d & 3
		else:
			l = t & 7
			if l == 0:
				while ip < n and src[ip] == 0:
					l += 255
					ip += 1
				if ip >= n:
					return PackedByteArray()
				l += 7 + src[ip]
				ip += 1
			if ip + 2 > n:
				return PackedByteArray()
			var d2 := src[ip] | (src[ip + 1] << 8)
			ip += 2
			var off := ((t & 8) << 11) + (d2 >> 2)
			if off == 0:
				if o.size() != op:
					o.resize(op)
				return o
			ref = op - off - 0x4000
			l += 2
			st = d2 & 3
		if ref < 0:
			return PackedByteArray()
		op = _copy(o, op, ref, l)
		if st:
			if ip + st > n:
				return PackedByteArray()
			op = _lit(o, op, src, ip, st)
			ip += st
		state = st
	return o


static func _ensure(o: PackedByteArray, n: int) -> void:
	if o.size() < n:
		o.resize(maxi(n, o.size() * 2))


static func _lit(o: PackedByteArray, op: int, src: PackedByteArray, ip: int, n: int) -> int:
	_ensure(o, op + n)
	for k in n:
		o[op + k] = src[ip + k]
	return op + n


static func _copy(o: PackedByteArray, op: int, ref: int, n: int) -> int:
	_ensure(o, op + n)
	for k in n:   # 回溯可能和输出重叠 (例 距离 1 = 重复一个字节), 只能逐字节
		o[op + k] = o[ref + k]
	return op + n
