class_name ExtractRunner
extends Node
## 发行版首次运行: 调用素材提取程序 (tools/extractor.py 打包的 extractor/czt_extract.exe), 从玩家的正版目录提取到本机
## 进度协议见 tools/extractor.py (stdout 每行一条: STEP / DONE / SKIP / FAIL / ALL_DONE); stderr 是各工具的日志, 写到 <提取目录>/extract.log
## 两个管道各用一个线程阻塞读 (stderr 不读的话管道写满, 提取程序会卡住)

signal step(k: int, n: int, name: String, desc: String)
signal finished(ok: bool, message: String)

var pid := -1
var log_path := ""
var _out_thread: Thread
var _err_thread: Thread
var _fail := ""
var _all_done := false
var _done := false


## exe: 提取程序; game: 正版目录; out: 提取目录。返回 "" 表示已启动, 否则为原因
func start(exe: String, game: String, out: String) -> String:
	DirAccess.make_dir_recursive_absolute(out)
	log_path = out.path_join("extract.log")
	var args := PackedStringArray(["--game", game, "--out", out])
	var p := OS.execute_with_pipe(exe, args, true)
	if p.is_empty():
		return "无法启动提取程序：" + exe
	pid = int(p.pid)
	_out_thread = Thread.new()
	_out_thread.start(_read_out.bind(p.stdio))
	_err_thread = Thread.new()
	_err_thread.start(_read_err.bind(p.stderr))
	return ""


func cancel() -> void:
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)


func _exit_tree() -> void:
	cancel()   # 关游戏时不留提取程序在后台跑 (下次启动从中断的那一步继续)
	for t in [_out_thread, _err_thread]:
		if t and t.is_started():
			t.wait_to_finish()


func _read_out(f: FileAccess) -> void:
	while true:
		var line := f.get_line()
		if line == "" and f.get_error() != OK:
			break
		if line != "":
			_on_line.call_deferred(line.strip_edges())
		elif not OS.is_process_running(pid):
			break
	_on_exit.call_deferred()


func _read_err(f: FileAccess) -> void:
	var lf := FileAccess.open(log_path, FileAccess.WRITE)
	while true:
		var line := f.get_line()
		if line == "" and f.get_error() != OK:
			break
		if lf:
			lf.store_line(line)
			lf.flush()
		if line == "" and not OS.is_process_running(pid):
			break


func _on_line(line: String) -> void:
	var w := line.split(" ", false, 4)
	if w.is_empty():
		return
	match w[0]:
		"STEP":
			if w.size() >= 5:
				step.emit(int(w[1]), int(w[2]), w[3], w[4])
		"FAIL":
			_fail = line.substr(5)
		"ALL_DONE":
			_all_done = true


func _on_exit() -> void:
	if _done:
		return
	_done = true
	var code := -1
	for i in 50:   # 管道关了进程不一定已退出, 等一下拿退出码
		if not OS.is_process_running(pid):
			break
		await get_tree().create_timer(0.1).timeout
	code = OS.get_process_exit_code(pid)
	if _all_done and code == 0:
		finished.emit(true, "")
	elif _fail != "":
		finished.emit(false, _fail)
	else:
		finished.emit(false, "提取程序意外退出（退出码 %d）" % code)
