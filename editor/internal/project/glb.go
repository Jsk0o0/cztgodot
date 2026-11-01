package project

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"os"
	"path/filepath"
	"regexp"
	"strings"
)

// 自定义模型的限制 (游戏端 mod_manager.gd 也拒绝超过 20 MB 的)
const (
	MaxGLBBytes    = 20 << 20
	WarnTriangles  = 30000
	MaxTriangles   = 100000
	MaxTextureSide = 2048
)

type Anim struct {
	Name    string  `json:"name"`
	Seconds float64 `json:"seconds"`
}

// GLBInfo: 导入前的检查结果
type GLBInfo struct {
	Size      int      `json:"size"`
	Triangles int      `json:"triangles"`
	Anims     []Anim   `json:"anims"`
	Textures  int      `json:"textures"`
	Warnings  []string `json:"warnings"`
}

type gltfDoc struct {
	Asset struct {
		Version string `json:"version"`
	} `json:"asset"`
	Buffers []struct {
		URI string `json:"uri"`
	} `json:"buffers"`
	BufferViews []struct {
		ByteOffset int `json:"byteOffset"`
		ByteLength int `json:"byteLength"`
	} `json:"bufferViews"`
	Accessors []struct {
		Count int       `json:"count"`
		Max   []float64 `json:"max"`
	} `json:"accessors"`
	Images []struct {
		URI        string `json:"uri"`
		BufferView *int   `json:"bufferView"`
	} `json:"images"`
	Meshes []struct {
		Primitives []struct {
			Indices    *int           `json:"indices"`
			Attributes map[string]int `json:"attributes"`
			Mode       *int           `json:"mode"`
		} `json:"primitives"`
	} `json:"meshes"`
	Animations []struct {
		Name     string `json:"name"`
		Samplers []struct {
			Input int `json:"input"`
		} `json:"samplers"`
	} `json:"animations"`
	ExtensionsRequired []string `json:"extensionsRequired"`
}

// InspectGLB: 读 .glb, 只接受自包含的二进制 glTF 2.0 (贴图和数据都在文件里), 检查大小、面数、贴图尺寸, 列出动画
func InspectGLB(data []byte) (*GLBInfo, error) {
	if len(data) > MaxGLBBytes {
		return nil, fmt.Errorf("文件太大（%.1f MB），上限 20 MB", float64(len(data))/(1<<20))
	}
	if len(data) < 20 || string(data[:4]) != "glTF" {
		return nil, errors.New("不是 .glb 文件（只支持二进制 glTF 2.0）")
	}
	if binary.LittleEndian.Uint32(data[4:]) != 2 {
		return nil, errors.New("只支持 glTF 2.0")
	}
	jl := int(binary.LittleEndian.Uint32(data[12:]))
	if string(data[16:20]) != "JSON" || 20+jl > len(data) {
		return nil, errors.New("glb 文件结构不对")
	}
	var doc gltfDoc
	if err := json.Unmarshal(data[20:20+jl], &doc); err != nil {
		return nil, fmt.Errorf("glb 里的 JSON 不对: %w", err)
	}
	var bin []byte
	if p := 20 + jl; p+8 <= len(data) && string(data[p+4:p+8]) == "BIN\x00" {
		bl := int(binary.LittleEndian.Uint32(data[p:]))
		if p+8+bl <= len(data) {
			bin = data[p+8 : p+8+bl]
		}
	}
	for _, b := range doc.Buffers {
		if b.URI != "" {
			return nil, errors.New("模型引用了外部文件，请导出成单个 .glb（贴图嵌入）")
		}
	}
	for _, e := range doc.ExtensionsRequired {
		if e == "KHR_draco_mesh_compression" || e == "EXT_meshopt_compression" {
			return nil, fmt.Errorf("游戏不支持压缩扩展 %s，导出时请关闭压缩", e)
		}
	}
	info := &GLBInfo{Size: len(data), Anims: []Anim{}, Warnings: []string{}}
	for _, m := range doc.Meshes {
		for _, pr := range m.Primitives {
			if pr.Mode != nil && *pr.Mode != 4 {
				continue
			}
			n := 0
			if pr.Indices != nil && *pr.Indices < len(doc.Accessors) {
				n = doc.Accessors[*pr.Indices].Count
			} else if a, ok := pr.Attributes["POSITION"]; ok && a < len(doc.Accessors) {
				n = doc.Accessors[a].Count
			}
			info.Triangles += n / 3
		}
	}
	if info.Triangles == 0 {
		return nil, errors.New("模型里没有三角形网格")
	}
	if info.Triangles > MaxTriangles {
		return nil, fmt.Errorf("面数太多（%d），上限 %d", info.Triangles, MaxTriangles)
	}
	if info.Triangles > WarnTriangles {
		info.Warnings = append(info.Warnings, fmt.Sprintf("面数 %d 偏多，原版人物大约 1–3 千面，可能影响帧数", info.Triangles))
	}
	for _, im := range doc.Images {
		if im.URI != "" && !strings.HasPrefix(im.URI, "data:") {
			return nil, errors.New("贴图是外部文件，请导出成单个 .glb（贴图嵌入）")
		}
		info.Textures++
		if im.BufferView != nil && *im.BufferView < len(doc.BufferViews) && bin != nil {
			v := doc.BufferViews[*im.BufferView]
			if v.ByteOffset+v.ByteLength <= len(bin) {
				if cfg, _, err := image.DecodeConfig(bytes.NewReader(bin[v.ByteOffset : v.ByteOffset+v.ByteLength])); err == nil {
					if cfg.Width > MaxTextureSide || cfg.Height > MaxTextureSide {
						return nil, fmt.Errorf("贴图 %d×%d 太大，最大 %d×%d", cfg.Width, cfg.Height, MaxTextureSide, MaxTextureSide)
					}
				}
			}
		}
	}
	for i, a := range doc.Animations {
		name := a.Name
		if name == "" {
			name = fmt.Sprintf("动画 %d", i+1)
		}
		sec := 0.0
		for _, s := range a.Samplers {
			if s.Input < len(doc.Accessors) && len(doc.Accessors[s.Input].Max) > 0 && doc.Accessors[s.Input].Max[0] > sec {
				sec = doc.Accessors[s.Input].Max[0]
			}
		}
		info.Anims = append(info.Anims, Anim{Name: name, Seconds: sec})
	}
	if len(info.Anims) == 0 {
		info.Warnings = append(info.Warnings, "没有动画，人物会一直保持静止的姿势")
	}
	return info, nil
}

var slugRe = regexp.MustCompile(`[^a-z0-9_-]+`)

// ImportModel: 检查后复制进工程的 models/ 目录, 返回新模型 (编号取下一个空号, 待机动画取名字像 idle 的那个)
func (p *Project) ImportModel(src string) (*Model, *GLBInfo, error) {
	data, info, err := readGLB(src)
	if err != nil {
		return nil, nil, err
	}
	local := 1
	for _, m := range p.Models {
		if m.Local >= local {
			local = m.Local + 1
		}
	}
	if local >= 64 {
		return nil, nil, errors.New("一个 mod 最多 63 个模型")
	}
	file, err := p.copyGLB(src, data)
	if err != nil {
		return nil, nil, err
	}
	m := &Model{Local: local, Name: strings.TrimSuffix(filepath.Base(src), filepath.Ext(src)), File: file, Scale: 1}
	m.setInfo(info)
	m.Ground, _ = GroundY(data, m.Idle)
	return m, info, nil
}

// ReplaceModel: 给已有模型换一个 .glb 文件 (编号、名字、缩放、朝向不变, 用到它的 NPC 不用改);
// 原来选的待机 / 行走动画新文件里还有就保留, 没有就重新按名字猜
func (p *Project) ReplaceModel(local int, src string) (*Model, *GLBInfo, error) {
	var old *Model
	for i := range p.Models {
		if p.Models[i].Local == local {
			old = &p.Models[i]
		}
	}
	if old == nil {
		return nil, nil, fmt.Errorf("没有模型 #%d", local)
	}
	data, info, err := readGLB(src)
	if err != nil {
		return nil, nil, err
	}
	file, err := p.copyGLB(src, data)
	if err != nil {
		return nil, nil, err
	}
	m := *old
	idle, walk := m.Idle, m.Walk
	m.File = file
	m.setInfo(info)
	has := func(n string) bool {
		for _, a := range info.Anims {
			if a.Name == n {
				return true
			}
		}
		return false
	}
	if idle != "" && has(idle) {
		m.Idle = idle
	}
	if walk != "" && has(walk) {
		m.Walk = walk
	}
	m.Ground, _ = GroundY(data, m.Idle)
	// 旧文件没有别的模型用就删掉 (工程目录里的拷贝, 不是用户的原文件)
	shared := false
	for _, o := range p.Models {
		if o.Local != local && o.File == old.File {
			shared = true
		}
	}
	if !shared && old.File != file && strings.HasPrefix(old.File, "models/") {
		os.Remove(filepath.Join(p.Dir, old.File))
	}
	return &m, info, nil
}

func readGLB(src string) ([]byte, *GLBInfo, error) {
	data, err := os.ReadFile(src)
	if err != nil {
		return nil, nil, err
	}
	info, err := InspectGLB(data)
	if err != nil {
		return nil, nil, err
	}
	return data, info, nil
}

// copyGLB: 复制进工程 models/ (文件名取原名, 重名加 -2 -3 …), 返回工程内相对路径
func (p *Project) copyGLB(src string, data []byte) (string, error) {
	base := slugRe.ReplaceAllString(strings.ToLower(strings.TrimSuffix(filepath.Base(src), filepath.Ext(src))), "-")
	if base == "" || base == "-" {
		base = "model"
	}
	file := fmt.Sprintf("models/%s.glb", base)
	for i := 2; fileExists(filepath.Join(p.Dir, file)); i++ {
		file = fmt.Sprintf("models/%s-%d.glb", base, i)
	}
	if err := os.MkdirAll(filepath.Join(p.Dir, "models"), 0o755); err != nil {
		return "", err
	}
	if err := os.WriteFile(filepath.Join(p.Dir, file), data, 0o644); err != nil {
		return "", err
	}
	return file, nil
}

// setInfo: 写入文件信息, 按名字猜待机 / 行走
func (m *Model) setInfo(info *GLBInfo) {
	m.Anims, m.Triangles, m.Size = info.Anims, info.Triangles, info.Size
	// 按名字猜待机 / 行走; 关键词按优先级逐个找 (同时有 walk 和 run 时选 walk, 不看动画排列顺序)
	pick := func(keys ...string) string {
		for _, k := range keys {
			for _, a := range info.Anims {
				if strings.Contains(strings.ToLower(a.Name), k) {
					return a.Name
				}
			}
		}
		return ""
	}
	m.Idle = pick("idle", "stand", "待机")
	m.Walk = pick("walk", "走", "run", "跑")
	if m.Idle == "" && len(info.Anims) > 0 {
		m.Idle = info.Anims[0].Name
	}
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
