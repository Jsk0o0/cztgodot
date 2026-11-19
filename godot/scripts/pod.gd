class_name Pod
extends RefCounted
## 读取创意工坊 .pod 包 (格式见 tools/podtool/format.go, 和 Go 的 Unpack 一一对应)。
## 校验顺序: 魔数 / 版本 → 作者签名 (RSA PKCS#1 v1.5, SHA256) → 主密钥解开内容密钥 → HMAC-SHA256 → AES-256-CBC 解密 → 解包。
## 全程在内存里完成, 不落盘明文。返回 {ok, error, id, fingerprint, files: {路径: PackedByteArray}}

# 主密钥分段存放在 pod_key.gd (不进仓库, make pod-key 生成)。本地加密的上限见 format.go: 防普通玩家拆包改包, 挡不住逆向
# 用 load 而不是 preload: 公开仓库没有这个文件, 缺它时只是读不了 .pod, 游戏其余部分照常
const KEY_SCRIPT := "res://scripts/pod_key.gd"


static func _master() -> PackedByteArray:
	var s: Script = load(KEY_SCRIPT) if ResourceLoader.exists(KEY_SCRIPT) else null
	if s == null:
		return PackedByteArray()
	var k: Array = s.get_script_constant_map().K
	return (k[3] + k[1] + k[2] + k[0]).hex_decode()


static func _fail(msg: String) -> Dictionary:
	return {"ok": false, "error": msg}


static func _sha256(b: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish()


const CHUNK := 4 << 20   # 大包 (配音包 300MB+) 分块处理, 不整份 slice 复制 (原来解一个 362MB 的包峰值内存 3GB)


## d[from, to) 分块喂给 HashingContext / HMACContext (都有 update)
static func _feed(ctx: Object, d: PackedByteArray, from: int, to: int) -> void:
	var p := from
	while p < to:
		var e := mini(p + CHUNK, to)
		ctx.update(d.slice(p, e))
		p = e


static func _sha256_range(d: PackedByteArray, from: int, to: int) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	_feed(h, d, from, to)
	return h.finish()


static func _cbc_decrypt(key: PackedByteArray, iv: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	if data.size() == 0 or data.size() % 16 != 0:
		return PackedByteArray()
	var a := AESContext.new()
	if a.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
		return PackedByteArray()
	var out := a.update(data)
	a.finish()
	return out


## PKCS#7 去填充; 不合法返回空
static func _unpad(b: PackedByteArray) -> PackedByteArray:
	if b.is_empty():
		return b
	var n := b[b.size() - 1]
	if n == 0 or n > 16 or n > b.size():
		return PackedByteArray()
	for i in range(b.size() - n, b.size()):
		if b[i] != n:
			return PackedByteArray()
	return b.slice(0, b.size() - n)


static func _pem(der: PackedByteArray) -> String:
	var b64 := Marshalls.raw_to_base64(der)
	var lines := []
	for i in range(0, b64.length(), 64):
		lines.append(b64.substr(i, 64))
	return "-----BEGIN PUBLIC KEY-----\n" + "\n".join(lines) + "\n-----END PUBLIC KEY-----\n"


static func read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("找不到文件")
	return read_bytes(FileAccess.get_file_as_bytes(path))


static func read_bytes(d: PackedByteArray) -> Dictionary:
	var p := 0
	if d.size() < 8 or d.slice(0, 4).get_string_from_ascii() != "POD1":
		return _fail("不是 .pod 文件")
	if d.decode_u16(4) != 1:
		return _fail("不支持的 .pod 版本")
	p = 8
	var id_len := d.decode_u16(p)
	var id := d.slice(p + 2, p + 2 + id_len).get_string_from_utf8()
	p += 2 + id_len
	if p + 2 > d.size():
		return _fail("文件被截断")
	var pub_len := d.decode_u16(p)
	var pub := d.slice(p + 2, p + 2 + pub_len)
	p += 2 + pub_len
	if p + 16 + 48 + 16 + 8 > d.size():
		return _fail("文件被截断")
	var wrap_iv := d.slice(p, p + 16)
	var wrapped := d.slice(p + 16, p + 64)
	var iv := d.slice(p + 64, p + 80)
	p += 80
	var body_len := d.decode_u64(p)
	p += 8
	if body_len < 0 or p + body_len + 32 + 2 > d.size():
		return _fail("文件被截断")
	var body_at := p
	p += body_len
	var signed_end := p + 32
	var mac := d.slice(p, signed_end)
	var sig_len := d.decode_u16(signed_end)
	if signed_end + 2 + sig_len > d.size():
		return _fail("文件被截断")
	var sig := d.slice(signed_end + 2, signed_end + 2 + sig_len)
	# 1. 作者签名
	var key := CryptoKey.new()
	if key.load_from_string(_pem(pub), true) != OK:
		return _fail("作者公钥无效")
	if not Crypto.new().verify(HashingContext.HASH_SHA256, _sha256_range(d, 0, signed_end), sig, key):
		return _fail("签名无效")
	# 2. 内容密钥
	var master := _master()
	if master.is_empty():
		return _fail("缺少主密钥 (先运行 make pod-key)")
	var ck := _unpad(_cbc_decrypt(master, wrap_iv, wrapped))
	if ck.size() != 32:
		return _fail("内容密钥无效")
	# 3. HMAC
	var mk_src := ck.duplicate()
	mk_src.append_array("pod-mac".to_utf8_buffer())
	var hm := HMACContext.new()
	hm.start(HashingContext.HASH_SHA256, _sha256(mk_src))
	_feed(hm, d, 0, signed_end - 32)
	if hm.finish() != mac:
		return _fail("校验失败（文件被改动）")
	# 4. 边解密边解包 (不拼出整份明文: 每解出一块就把完整的文件切出来)
	var u := _Unpacker.new()
	var err := u.run(ck, iv, d, body_at, body_len)
	if err != "":
		return _fail(err)
	var files := u.files
	return {"ok": true, "error": "", "id": id, "fingerprint": _sha256(pub).slice(0, 8).hex_encode(), "files": files}


## 流式解包: CBC 分块解密, 明文是 PODA 归档 ("PODA" + 文件数 u32 + [名字长 u16, 名字, 大小 u32, 内容]…) + PKCS#7 填充
class _Unpacker:
	var files := {}
	var _buf := PackedByteArray()
	var _off := 0

	func _need(n: int) -> bool:
		return _buf.size() - _off >= n

	func run(key: PackedByteArray, iv: PackedByteArray, d: PackedByteArray, from: int, n: int) -> String:
		if n == 0 or n % 16 != 0:
			return "归档格式不对"
		var a := AESContext.new()
		if a.start(AESContext.MODE_CBC_DECRYPT, key, iv) != OK:
			return "归档格式不对"
		var count := -1        # 还没读到头
		var got := 0
		var name := ""
		var size := -1         # -1: 下一步读名字; >= 0: 等内容
		var p := 0
		while p < n:
			var e := mini(p + CHUNK, n)
			if _off > 0:   # 丢掉已经用过的前缀 (每块一次)
				_buf = _buf.slice(_off)
				_off = 0
			_buf.append_array(a.update(d.slice(from + p, from + e)))
			p = e
			while true:
				if count < 0:
					if not _need(8):
						break
					if _buf.slice(0, 4).get_string_from_ascii() != "PODA":
						return "归档格式不对"
					count = _buf.decode_u32(4)
					_off = 8
				elif got >= count:
					break
				elif size < 0:
					if not _need(2):
						break
					var l := _buf.decode_u16(_off)
					if not _need(2 + l + 4):
						break
					name = _buf.slice(_off + 2, _off + 2 + l).get_string_from_utf8()
					size = _buf.decode_u32(_off + 2 + l)
					_off += 2 + l + 4
					if name.contains("..") or name.begins_with("/"):
						return "归档内容非法"
				else:
					if not _need(size):
						break
					files[name] = _buf.slice(_off, _off + size)
					_off += size
					got += 1
					size = -1
		a.finish()
		if count < 0 or got < count or size >= 0:
			return "归档被截断"
		# 剩下的应该正好是 PKCS#7 填充
		var rest := _buf.size() - _off
		if rest < 1 or rest > 16 or _buf[_buf.size() - 1] != rest:
			return "归档被截断"
		for i in range(_off, _buf.size()):
			if _buf[i] != rest:
				return "归档内容非法"
		return ""
