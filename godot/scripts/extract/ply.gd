extends RefCounted
## .PLY 模型解析 (同 tools/ply.py; 格式说明见该文件)
## 返回 {bbox, segs: [[flags, vstart, vend, tstart, tend]], verts: PackedFloat32Array (nv × 10, 第 10 个是颜色的位模式),
##       colors: PackedInt64Array (u32 ARGB), indices: PackedInt32Array, groups: [[istart, iend, flags, tex, name]],
##       mats: PackedFloat32Array (帧 × 段 × 16, 行主序), nframes, morphs: [[偏移 PackedInt32Array, 顶点 PackedFloat32Array] 或 null]}

const Lzo := preload("res://scripts/extract/lzo.gd")
const Txt := preload("res://scripts/extract/text.gd")


static func parse(path: String) -> Dictionary:
	var p := Lzo.load_file(path)
	if p.is_empty():
		return {}
	return parse_bytes(p)


static func parse_bytes(p: PackedByteArray) -> Dictionary:
	var bbox := [p.decode_float(4), p.decode_float(8), p.decode_float(12), p.decode_float(20), p.decode_float(24), p.decode_float(28)]
	var n := p.decode_u32(0x38)
	var o := 0x3C
	var segs: Array = []
	for i in n:
		segs.append([p.decode_u32(o), p.decode_u32(o + 8), p.decode_u32(o + 12), p.decode_u32(o + 20), p.decode_u32(o + 24)])
		o += 28
	var nv := p.decode_u32(o)
	o += 4
	var verts := p.slice(o, o + 40 * nv).to_float32_array()
	var colors := PackedInt64Array()
	colors.resize(nv)
	for i in nv:
		colors[i] = p.decode_u32(o + 40 * i + 36)
	o += 40 * nv
	var nt := p.decode_u32(o)
	o += 4
	var idx := PackedInt32Array()
	idx.resize(nt * 3)
	for i in nt * 3:
		idx[i] = p.decode_u16(o + 2 * i)
	o += 6 * nt
	var ng := p.decode_u32(o)
	o += 4
	var groups: Array = []
	for g in ng:
		groups.append([p.decode_u32(o + 4), p.decode_u32(o + 8), p.decode_u32(o + 12), p.decode_s32(o + 16), Txt.big5z(p.slice(o + 20, o + 52))])
		o += 52
	var nt2 := p.decode_u32(o)
	o += 4 + 4 * nt2
	var nf := p.decode_u32(o)
	o += 4
	var mats := p.slice(o, o + nf * n * 64).to_float32_array()
	o += nf * n * 64
	var morphs: Array = []
	var nf2 := p.decode_u32(o)
	o += 4
	for f in nf2:
		var offs := p.slice(o, o + 4 * n).to_int32_array()
		o += 4 * n
		var cnt := p.decode_u32(o)
		o += 4
		var mv := p.slice(o, o + 40 * cnt).to_float32_array()
		o += 40 * cnt
		morphs.append([offs, mv] if cnt else null)
	if o != p.size():
		return {}
	return {"bbox": bbox, "segs": segs, "verts": verts, "colors": colors, "indices": idx, "groups": groups,
		"mats": mats, "nframes": nf, "morphs": morphs}


## 第 f 帧第 i 段的 4×4 矩阵 (行主序 16 个数)
static func mat(m: Dictionary, f: int, i: int) -> PackedFloat32Array:
	var nseg: int = m.segs.size()
	var o := (f * nseg + i) * 16
	return (m.mats as PackedFloat32Array).slice(o, o + 16)


static func vertex_segment(m: Dictionary) -> PackedInt32Array:
	var seg := PackedInt32Array()
	seg.resize((m.verts as PackedFloat32Array).size() / 10)
	for i in m.segs.size():
		for v in range(m.segs[i][1], m.segs[i][2]):
			seg[v] = i
	return seg
