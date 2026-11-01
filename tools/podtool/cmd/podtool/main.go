// podtool: .pod 打包工具 (编辑器以后直接复用 pod.go)
//
//	podtool keygen [密钥文件]            生成作者 RSA-2048 私钥 (默认 ~/.config/czt-pod/author.pem)
//	podtool pack <mod 目录> <输出.pod> [密钥文件]
//	podtool info <文件.pod>              校验并列出内容
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"czt/podtool/pod"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"os"
	"path/filepath"
)

func defaultKey() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".config", "czt-pod", "author.pem")
}

func loadKey(path string) (*rsa.PrivateKey, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("读不到作者密钥 %s (先运行 podtool keygen)", path)
	}
	blk, _ := pem.Decode(b)
	if blk == nil {
		return nil, errors.New("作者密钥不是 PEM")
	}
	return x509.ParsePKCS1PrivateKey(blk.Bytes)
}

func arg(i int, def string) string {
	if len(os.Args) > i {
		return os.Args[i]
	}
	return def
}

func run() error {
	switch arg(1, "") {
	case "keygen":
		path := arg(2, defaultKey())
		if _, err := os.Stat(path); err == nil {
			return fmt.Errorf("%s 已存在, 不覆盖", path)
		}
		k, err := rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			return err
		}
		os.MkdirAll(filepath.Dir(path), 0o700)
		pemBytes := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(k)})
		return os.WriteFile(path, pemBytes, 0o600)
	case "pack":
		dir, out := arg(2, ""), arg(3, "")
		if dir == "" || out == "" {
			return errors.New("用法: podtool pack <mod 目录> <输出.pod> [密钥文件]")
		}
		var man struct {
			ID string `json:"id"`
		}
		mb, err := os.ReadFile(filepath.Join(dir, "mod.json"))
		if err != nil {
			return errors.New("目录里没有 mod.json")
		}
		if json.Unmarshal(mb, &man) != nil || man.ID == "" {
			return errors.New("mod.json 缺少 id")
		}
		k, err := loadKey(arg(4, defaultKey()))
		if err != nil {
			return err
		}
		data, err := pod.Pack(dir, man.ID, k)
		if err != nil {
			return err
		}
		u, err := pod.Unpack(data) // 自检
		if err != nil {
			return fmt.Errorf("打包后自检失败: %w", err)
		}
		if err := os.WriteFile(out, data, 0o644); err != nil {
			return err
		}
		fmt.Printf("已打包 %s → %s (%d 字节, %d 个文件, 作者指纹 %s)\n", man.ID, out, len(data), len(u.Files), u.Fingerprint)
		return nil
	case "info":
		data, err := os.ReadFile(arg(2, ""))
		if err != nil {
			return err
		}
		u, err := pod.Unpack(data)
		if err != nil {
			return err
		}
		fmt.Printf("%s  作者指纹 %s\n", u.ID, u.Fingerprint)
		for p, b := range u.Files {
			fmt.Printf("  %-30s %d\n", p, len(b))
		}
		return nil
	}
	return errors.New("用法: podtool keygen | pack <目录> <输出.pod> | info <文件.pod>")
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "错误:", err)
		os.Exit(1)
	}
}
