package pod

import (
	"bytes"
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

func pkcs7Pad(b []byte) []byte {
	n := aes.BlockSize - len(b)%aes.BlockSize
	return append(b, bytes.Repeat([]byte{byte(n)}, n)...)
}

func pkcs7Unpad(b []byte) ([]byte, error) {
	if len(b) == 0 || len(b)%aes.BlockSize != 0 {
		return nil, errors.New("密文长度不对")
	}
	n := int(b[len(b)-1])
	if n == 0 || n > aes.BlockSize || n > len(b) {
		return nil, errors.New("填充不对")
	}
	for _, c := range b[len(b)-n:] {
		if int(c) != n {
			return nil, errors.New("填充不对")
		}
	}
	return b[:len(b)-n], nil
}

func cbc(key, iv, data []byte, enc bool) ([]byte, error) {
	blk, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	out := make([]byte, len(data))
	if enc {
		cipher.NewCBCEncrypter(blk, iv).CryptBlocks(out, data)
	} else {
		cipher.NewCBCDecrypter(blk, iv).CryptBlocks(out, data)
	}
	return out, nil
}

func macKey(contentKey []byte) []byte {
	h := sha256.Sum256(append(append([]byte{}, contentKey...), "pod-mac"...))
	return h[:]
}

// 打包: 目录下所有文件 (跳过隐藏文件) → 归档; 路径用 / 分隔、按字典序, 保证同样内容得到同样归档
func archive(dir string) ([]byte, error) {
	var paths []string
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if strings.HasPrefix(d.Name(), ".") && p != dir {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.IsDir() {
			rel, _ := filepath.Rel(dir, p)
			paths = append(paths, filepath.ToSlash(rel))
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Strings(paths)
	var b bytes.Buffer
	b.WriteString(ArchiveMagic)
	binary.Write(&b, binary.LittleEndian, uint32(len(paths)))
	for _, p := range paths {
		data, err := os.ReadFile(filepath.Join(dir, filepath.FromSlash(p)))
		if err != nil {
			return nil, err
		}
		binary.Write(&b, binary.LittleEndian, uint16(len(p)))
		b.WriteString(p)
		binary.Write(&b, binary.LittleEndian, uint32(len(data)))
		b.Write(data)
	}
	return b.Bytes(), nil
}

func Pack(dir, modID string, priv *rsa.PrivateKey) ([]byte, error) {
	arc, err := archive(dir)
	if err != nil {
		return nil, err
	}
	contentKey := make([]byte, 32)
	wrapIV := make([]byte, 16)
	iv := make([]byte, 16)
	for _, b := range [][]byte{contentKey, wrapIV, iv} {
		if _, err := rand.Read(b); err != nil {
			return nil, err
		}
	}
	wrapped, err := cbc(masterKey, wrapIV, pkcs7Pad(append([]byte{}, contentKey...)), true)
	if err != nil {
		return nil, err
	}
	body, err := cbc(contentKey, iv, pkcs7Pad(arc), true)
	if err != nil {
		return nil, err
	}
	pub, err := x509.MarshalPKIXPublicKey(&priv.PublicKey)
	if err != nil {
		return nil, err
	}
	var b bytes.Buffer
	b.WriteString(Magic)
	binary.Write(&b, binary.LittleEndian, uint16(Version))
	binary.Write(&b, binary.LittleEndian, uint16(0))
	binary.Write(&b, binary.LittleEndian, uint16(len(modID)))
	b.WriteString(modID)
	binary.Write(&b, binary.LittleEndian, uint16(len(pub)))
	b.Write(pub)
	b.Write(wrapIV)
	b.Write(wrapped)
	b.Write(iv)
	binary.Write(&b, binary.LittleEndian, uint64(len(body)))
	b.Write(body)
	m := hmac.New(sha256.New, macKey(contentKey))
	m.Write(b.Bytes())
	b.Write(m.Sum(nil))
	h := sha256.Sum256(b.Bytes())
	sig, err := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, h[:])
	if err != nil {
		return nil, err
	}
	binary.Write(&b, binary.LittleEndian, uint16(len(sig)))
	b.Write(sig)
	return b.Bytes(), nil
}

type Unpacked struct {
	ID          string
	Fingerprint string
	Files       map[string][]byte
}

// 和游戏端 pod.gd 同样的校验顺序 (打包后自检 / info 命令用)
func Unpack(data []byte) (*Unpacked, error) {
	r := bytes.NewReader(data)
	rd := func(n int) []byte {
		b := make([]byte, n)
		if _, err := r.Read(b); err != nil {
			return nil
		}
		return b
	}
	u16 := func() int { var v uint16; binary.Read(r, binary.LittleEndian, &v); return int(v) }
	if string(rd(4)) != Magic {
		return nil, errors.New("不是 .pod 文件")
	}
	if u16() != Version {
		return nil, errors.New("不支持的 .pod 版本")
	}
	u16()
	id := string(rd(u16()))
	pubDER := rd(u16())
	wrapIV, wrapped, iv := rd(16), rd(48), rd(16)
	var bodyLen uint64
	binary.Read(r, binary.LittleEndian, &bodyLen)
	if bodyLen > uint64(r.Len()) {
		return nil, errors.New("文件被截断")
	}
	body := rd(int(bodyLen))
	signedEnd := len(data) - r.Len() + 32
	mac := rd(32)
	sig := rd(u16())
	if mac == nil || sig == nil {
		return nil, errors.New("文件被截断")
	}
	pk, err := x509.ParsePKIXPublicKey(pubDER)
	if err != nil {
		return nil, errors.New("作者公钥无效")
	}
	pub, ok := pk.(*rsa.PublicKey)
	if !ok {
		return nil, errors.New("作者公钥不是 RSA")
	}
	h := sha256.Sum256(data[:signedEnd])
	if rsa.VerifyPKCS1v15(pub, crypto.SHA256, h[:], sig) != nil {
		return nil, errors.New("签名无效")
	}
	kp, err := cbc(masterKey, wrapIV, wrapped, false)
	if err != nil {
		return nil, err
	}
	contentKey, err := pkcs7Unpad(kp)
	if err != nil || len(contentKey) != 32 {
		return nil, errors.New("内容密钥无效")
	}
	m := hmac.New(sha256.New, macKey(contentKey))
	m.Write(data[:signedEnd-32])
	if !hmac.Equal(m.Sum(nil), mac) {
		return nil, errors.New("校验失败 (文件被改动)")
	}
	plain, err := cbc(contentKey, iv, body, false)
	if err != nil {
		return nil, err
	}
	arc, err := pkcs7Unpad(plain)
	if err != nil {
		return nil, err
	}
	files, err := parseArchive(arc)
	if err != nil {
		return nil, err
	}
	fp := sha256.Sum256(pubDER)
	return &Unpacked{ID: id, Fingerprint: fmt.Sprintf("%x", fp[:8]), Files: files}, nil
}

func parseArchive(a []byte) (map[string][]byte, error) {
	if len(a) < 8 || string(a[:4]) != ArchiveMagic {
		return nil, errors.New("归档格式不对")
	}
	n := int(binary.LittleEndian.Uint32(a[4:8]))
	p := 8
	out := map[string][]byte{}
	for i := 0; i < n; i++ {
		if p+2 > len(a) {
			return nil, errors.New("归档被截断")
		}
		l := int(binary.LittleEndian.Uint16(a[p:]))
		p += 2
		if p+l+4 > len(a) {
			return nil, errors.New("归档被截断")
		}
		name := string(a[p : p+l])
		p += l
		sz := int(binary.LittleEndian.Uint32(a[p:]))
		p += 4
		if p+sz > len(a) {
			return nil, errors.New("归档被截断")
		}
		if strings.Contains(name, "..") || strings.HasPrefix(name, "/") {
			return nil, fmt.Errorf("非法路径 %s", name)
		}
		out[name] = a[p : p+sz]
		p += sz
	}
	return out, nil
}
