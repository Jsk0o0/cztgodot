package main

import (
	"os"
	"path/filepath"
	"testing"
)

// 不用选目录: 从 .app 里的程序位置往上能找到复刻工程; 数据目录按游戏的 local_paths.cfg
func TestFindGameRootFromApp(t *testing.T) {
	root := t.TempDir()
	os.MkdirAll(filepath.Join(root, "godot"), 0o755)
	os.WriteFile(filepath.Join(root, "godot", "project.godot"), []byte("[application]\nconfig/name=\"测试工程\"\n"), 0o644)
	data := filepath.Join(t.TempDir(), "my_extracted")
	os.MkdirAll(filepath.Join(data, "game"), 0o755)
	os.WriteFile(filepath.Join(data, "game", "maps.json"), []byte("{}"), 0o644)
	if isGameRoot(root) {
		t.Fatal("没有 local_paths.cfg 时不该找到数据")
	}
	os.WriteFile(filepath.Join(root, "godot", "local_paths.cfg"), []byte("; 注释\n[paths]\nextracted_dir=\""+data+"\"\n"), 0o644)
	if got := extractedDir(root); got != data {
		t.Fatalf("extractedDir = %q, 要 %q", got, data)
	}
	if !isGameRoot(root) {
		t.Fatal("应该认出复刻工程")
	}
	app := filepath.Join(root, "editor", "build", "bin", "x.app", "Contents", "MacOS")
	os.MkdirAll(app, 0o755)
	wd, _ := os.Getwd()
	defer os.Chdir(wd)
	os.Chdir(app)
	if got := findGameRoot(); got == "" {
		t.Fatal("从 .app 里面往上没找到工程")
	}
}
