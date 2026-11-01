//go:build !devserver

package main

import (
	"embed"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	// Create an instance of the app structure
	app := NewApp()

	// Create application with options
	err := wails.Run(&options.App{
		Title:     "苍之涛 · 工坊编辑器",
		Width:     1440,
		Height:    900,
		MinWidth:  1100,
		MinHeight: 700,
		AssetServer: &assetserver.Options{
			Assets:  assets,
			Handler: app.assetHandler(), // /gamedata/: 本机游戏数据 (场景 / 模型 GLB)
		},
		BackgroundColour: &options.RGBA{R: 29, G: 26, B: 23, A: 1},
		// 拖 .glb 进窗口导入模型 (前端 OnFileDrop 拿到绝对路径); 关掉 WebView 自己的拖放, 免得把文件当网页打开
		DragAndDrop: &options.DragAndDrop{EnableFileDrop: true, DisableWebViewDrop: true},
		OnStartup:   app.startup,
		Bind: []interface{}{
			app,
		},
	})

	if err != nil {
		println("Error:", err.Error())
	}
}
