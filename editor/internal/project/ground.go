package project

// 模型「脚底」高度: 待机动画第一帧 (没有就用绑定姿势) 蒙皮后所有顶点的最低 y, 模型自己的单位。
// 游戏和编辑器显示时把模型往上抬 -ground, 让脚踩在地面上 —— 有些导出的带骨骼模型原点在腰上
// (例: 飞天 monsters_animated 的 mon440_0 最低点在 y=-0.485, 总高 2.31, 原样放会埋进地里两成)。
// 算法按 glTF 2.0 规范: 节点 TRS / matrix 层级, 关节矩阵 = 关节世界矩阵 × 逆绑定矩阵, JOINTS_0 / WEIGHTS_0 加权。

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"math"
)

type gNode struct {
	Children    []int     `json:"children"`
	Matrix      []float64 `json:"matrix"`
	Translation []float64 `json:"translation"`
	Rotation    []float64 `json:"rotation"`
	Scale       []float64 `json:"scale"`
	Mesh        *int      `json:"mesh"`
	Skin        *int      `json:"skin"`
}

type gDoc struct {
	Nodes     []gNode `json:"nodes"`
	Accessors []struct {
		BufferView    *int   `json:"bufferView"`
		ByteOffset    int    `json:"byteOffset"`
		ComponentType int    `json:"componentType"`
		Normalized    bool   `json:"normalized"`
		Count         int    `json:"count"`
		Type          string `json:"type"`
	} `json:"accessors"`
	BufferViews []struct {
		ByteOffset int `json:"byteOffset"`
		ByteStride int `json:"byteStride"`
	} `json:"bufferViews"`
	Meshes []struct {
		Primitives []struct {
			Attributes map[string]int `json:"attributes"`
		} `json:"primitives"`
	} `json:"meshes"`
	Skins []struct {
		InverseBindMatrices *int  `json:"inverseBindMatrices"`
		Joints              []int `json:"joints"`
	} `json:"skins"`
	Animations []struct {
		Name     string `json:"name"`
		Channels []struct {
			Sampler int `json:"sampler"`
			Target  struct {
				Node *int   `json:"node"`
				Path string `json:"path"`
			} `json:"target"`
		} `json:"channels"`
		Samplers []struct {
			Output int `json:"output"`
		} `json:"samplers"`
	} `json:"animations"`
}

type mat4 [16]float64 // 列主序, 同 glTF

func ident() mat4 { return mat4{1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1} }

func (a mat4) mul(b mat4) mat4 {
	var r mat4
	for c := 0; c < 4; c++ {
		for rr := 0; rr < 4; rr++ {
			var s float64
			for k := 0; k < 4; k++ {
				s += a[k*4+rr] * b[c*4+k]
			}
			r[c*4+rr] = s
		}
	}
	return r
}

func (a mat4) apply(x, y, z float64) [3]float64 {
	return [3]float64{a[0]*x + a[4]*y + a[8]*z + a[12], a[1]*x + a[5]*y + a[9]*z + a[13], a[2]*x + a[6]*y + a[10]*z + a[14]}
}

func trs(t, r, s []float64) mat4 {
	x, y, z, w := r[0], r[1], r[2], r[3]
	if n := math.Sqrt(x*x + y*y + z*z + w*w); n > 0 {
		x, y, z, w = x/n, y/n, z/n, w/n
	}
	m := mat4{
		1 - 2*(y*y+z*z), 2 * (x*y + z*w), 2 * (x*z - y*w), 0,
		2 * (x*y - z*w), 1 - 2*(x*x+z*z), 2 * (y*z + x*w), 0,
		2 * (x*z + y*w), 2 * (y*z - x*w), 1 - 2*(x*x+y*y), 0,
		t[0], t[1], t[2], 1,
	}
	for c := 0; c < 3; c++ {
		for rr := 0; rr < 3; rr++ {
			m[c*4+rr] *= s[c]
		}
	}
	return m
}

var compSize = map[int]int{5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
var typeN = map[string]int{"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

// readAcc: 读成 float64 (整数按 normalized 归一化, 否则原值)
func (d *gDoc) readAcc(bin []byte, i int) ([][]float64, error) {
	if i < 0 || i >= len(d.Accessors) {
		return nil, errors.New("accessor 越界")
	}
	a := d.Accessors[i]
	n, cs := typeN[a.Type], compSize[a.ComponentType]
	if n == 0 || cs == 0 || a.BufferView == nil || *a.BufferView >= len(d.BufferViews) {
		return nil, errors.New("accessor 不支持")
	}
	bv := d.BufferViews[*a.BufferView]
	stride := bv.ByteStride
	if stride == 0 {
		stride = cs * n
	}
	base := bv.ByteOffset + a.ByteOffset
	out := make([][]float64, a.Count)
	for k := 0; k < a.Count; k++ {
		row := make([]float64, n)
		for c := 0; c < n; c++ {
			o := base + k*stride + c*cs
			if o+cs > len(bin) {
				return nil, errors.New("数据越界")
			}
			var v float64
			switch a.ComponentType {
			case 5126:
				v = float64(math.Float32frombits(binary.LittleEndian.Uint32(bin[o:])))
			case 5121:
				v = float64(bin[o])
				if a.Normalized {
					v /= 255
				}
			case 5120:
				v = float64(int8(bin[o]))
				if a.Normalized {
					v = math.Max(v/127, -1)
				}
			case 5123:
				v = float64(binary.LittleEndian.Uint16(bin[o:]))
				if a.Normalized {
					v /= 65535
				}
			case 5122:
				v = float64(int16(binary.LittleEndian.Uint16(bin[o:])))
				if a.Normalized {
					v = math.Max(v/32767, -1)
				}
			case 5125:
				v = float64(binary.LittleEndian.Uint32(bin[o:]))
			}
			row[c] = v
		}
		out[k] = row
	}
	return out, nil
}

// GroundY: 见文件头。idle = 待机动画名 (空 = 绑定姿势)
func GroundY(data []byte, idle string) (float64, error) {
	if len(data) < 20 || string(data[:4]) != "glTF" {
		return 0, errors.New("不是 .glb")
	}
	jl := int(binary.LittleEndian.Uint32(data[12:]))
	if 20+jl > len(data) {
		return 0, errors.New("glb 结构不对")
	}
	var d gDoc
	if err := json.Unmarshal(data[20:20+jl], &d); err != nil {
		return 0, err
	}
	var bin []byte
	if p := 20 + jl; p+8 <= len(data) {
		bin = data[p+8:]
	}
	// 待机动画第一帧覆盖节点的 TRS
	pose := map[int]map[string][]float64{}
	for _, an := range d.Animations {
		if idle == "" || an.Name != idle {
			continue
		}
		for _, ch := range an.Channels {
			if ch.Target.Node == nil || ch.Sampler >= len(an.Samplers) {
				continue
			}
			v, err := d.readAcc(bin, an.Samplers[ch.Sampler].Output)
			if err != nil || len(v) == 0 {
				continue
			}
			if pose[*ch.Target.Node] == nil {
				pose[*ch.Target.Node] = map[string][]float64{}
			}
			pose[*ch.Target.Node][ch.Target.Path] = v[0]
		}
	}
	parent := map[int]int{}
	for i, n := range d.Nodes {
		for _, c := range n.Children {
			parent[c] = i
		}
	}
	local := func(i int) mat4 {
		n := d.Nodes[i]
		if len(n.Matrix) == 16 {
			var m mat4
			copy(m[:], n.Matrix)
			return m
		}
		t, r, s := []float64{0, 0, 0}, []float64{0, 0, 0, 1}, []float64{1, 1, 1}
		if len(n.Translation) == 3 {
			t = n.Translation
		}
		if len(n.Rotation) == 4 {
			r = n.Rotation
		}
		if len(n.Scale) == 3 {
			s = n.Scale
		}
		if p := pose[i]; p != nil {
			if v := p["translation"]; len(v) == 3 {
				t = v
			}
			if v := p["rotation"]; len(v) == 4 {
				r = v
			}
			if v := p["scale"]; len(v) == 3 {
				s = v
			}
		}
		return trs(t, r, s)
	}
	worldCache := map[int]mat4{}
	var world func(i int) mat4
	world = func(i int) mat4 {
		if m, ok := worldCache[i]; ok {
			return m
		}
		m := local(i)
		if p, ok := parent[i]; ok {
			m = world(p).mul(m)
		}
		worldCache[i] = m
		return m
	}
	minY, found := math.Inf(1), false
	for ni, n := range d.Nodes {
		if n.Mesh == nil || *n.Mesh >= len(d.Meshes) {
			continue
		}
		var joints []mat4
		if n.Skin != nil && *n.Skin < len(d.Skins) {
			sk := d.Skins[*n.Skin]
			var ibm [][]float64
			if sk.InverseBindMatrices != nil {
				var err error
				if ibm, err = d.readAcc(bin, *sk.InverseBindMatrices); err != nil {
					return 0, err
				}
			}
			for k, jt := range sk.Joints {
				ib := ident()
				if k < len(ibm) {
					copy(ib[:], ibm[k])
				}
				joints = append(joints, world(jt).mul(ib))
			}
		}
		for _, pr := range d.Meshes[*n.Mesh].Primitives {
			pi, ok := pr.Attributes["POSITION"]
			if !ok {
				continue
			}
			P, err := d.readAcc(bin, pi)
			if err != nil {
				return 0, err
			}
			if joints == nil {
				w := world(ni)
				for _, v := range P {
					if y := w.apply(v[0], v[1], v[2])[1]; y < minY {
						minY = y
					}
					found = true
				}
				continue
			}
			ji, ok1 := pr.Attributes["JOINTS_0"]
			wi, ok2 := pr.Attributes["WEIGHTS_0"]
			if !ok1 || !ok2 {
				continue
			}
			J, err := d.readAcc(bin, ji)
			if err != nil {
				return 0, err
			}
			W, err := d.readAcc(bin, wi)
			if err != nil {
				return 0, err
			}
			for k, v := range P {
				var y, ws float64
				for c := 0; c < 4; c++ {
					wt := W[k][c]
					jx := int(J[k][c])
					if wt == 0 || jx >= len(joints) {
						continue
					}
					y += wt * joints[jx].apply(v[0], v[1], v[2])[1]
					ws += wt
				}
				if ws > 0 {
					y /= ws
					if y < minY {
						minY = y
					}
					found = true
				}
			}
		}
	}
	if !found {
		return 0, errors.New("没有网格")
	}
	return minY, nil
}
