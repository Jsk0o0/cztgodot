# 在 Windows 上打包素材提取程序 → czt_extract.zip (发布到 CNB: 在 mac 上 tools/release.py publish --extractor-zip czt_extract.zip)
# 用法: 双击 build.bat (或 powershell -ExecutionPolicy Bypass -File build.ps1)
# 需要: Python 3.12 (python.org 安装版, 勾选 Add to PATH); 联网 (pip 依赖 + ffmpeg)
# 步骤同 .github/workflows/extractor.yml: PyInstaller → 带 libtheora 的 ffmpeg → 自检 → 中文路径测试 → 替换程序测试 → 打包
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # PowerShell 5.1 的下载进度条会让大文件下载慢到像卡住
Set-Location $PSScriptRoot
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$env:PYTHONUTF8 = '1'

# 下载: 优先 Windows 自带的 curl.exe (有进度、快), 没有再用 Invoke-WebRequest
function Get-File($url, $out) {
  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    curl.exe -L --fail --retry 3 -o $out $url
    if ($LASTEXITCODE -ne 0) { throw "下载失败: $url" }
  } else {
    Invoke-WebRequest $url -OutFile $out -UseBasicParsing
  }
}

Write-Host '== 1/6 依赖'
python -m pip install --disable-pip-version-check -q pyinstaller==6.22.3 pillow==13.0.0 numpy==2.5.4 opencc-python-reimplemented==0.1.7 pefile==2024.8.26 capstone==5.0.9 onnxruntime-directml==1.24.4
if ($LASTEXITCODE -ne 0) { throw 'pip 安装失败' }

Write-Host '== 2/6 PyInstaller 打包'
Remove-Item -Recurse -Force dist, build -ErrorAction SilentlyContinue
python -m PyInstaller --noconfirm --distpath dist --workpath build tools\extractor.spec
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller 失败' }

Write-Host '== 3/6 ffmpeg (gyan.dev; essentials 没有 libtheora 时换 full)'
if (-not (Test-Path ffmpeg\ffmpeg.exe)) {
  Remove-Item -Recurse -Force ff, ff.zip, ff.7z -ErrorAction SilentlyContinue
  Write-Host '下载 ffmpeg essentials (约 110MB)…'
  Get-File https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip ff.zip
  Expand-Archive ff.zip -DestinationPath ff
  $bin = (Get-ChildItem ff -Recurse -Filter ffmpeg.exe | Select-Object -First 1).DirectoryName
  if (-not ((& "$bin\ffmpeg.exe" -hide_banner -encoders) -match ' libtheora ')) {
    Write-Host 'essentials 没有 libtheora, 改用 full (需要 7-Zip: 7z 在 PATH 里)'
    Remove-Item -Recurse -Force ff
    Get-File https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full.7z ff.7z
    7z x ff.7z -off | Out-Null
    $bin = (Get-ChildItem ff -Recurse -Filter ffmpeg.exe | Select-Object -First 1).DirectoryName
  }
  New-Item -ItemType Directory -Force ffmpeg\licenses | Out-Null   # 下好的放在 ffmpeg\, 下次直接用 (也可以手动放 ffmpeg.exe / ffprobe.exe)
  Copy-Item "$bin\ffmpeg.exe", "$bin\ffprobe.exe" ffmpeg\
  Get-ChildItem (Split-Path $bin -Parent) -File | Copy-Item -Destination ffmpeg\licenses\
  Remove-Item -Recurse -Force ff, ff.zip, ff.7z -ErrorAction SilentlyContinue
}
Copy-Item ffmpeg\ffmpeg.exe, ffmpeg\ffprobe.exe dist\czt_extract\
New-Item -ItemType Directory -Force dist\czt_extract\licenses\ffmpeg | Out-Null
Copy-Item ffmpeg\licenses\* dist\czt_extract\licenses\ffmpeg\
Set-Content -Encoding UTF8 dist\czt_extract\licenses\ffmpeg\SOURCE.txt 'ffmpeg 来自 https://www.gyan.dev/ffmpeg/builds/ (GPLv3), 源码见 https://github.com/FFmpeg/FFmpeg'

Write-Host '== 4/6 自检 (模块、数据文件、UTF-8 模式、Theora 实际编码)'
$out = & dist\czt_extract\czt_extract.exe --selftest
$out
if ($LASTEXITCODE -ne 0 -or -not ($out -match 'SELFTEST OK') -or -not ($out -match 'libtheora')) { throw '自检没通过' }

Write-Host '== 5/6 中文路径 + 非正版目录 (应报 FAIL check)'
$t = Join-Path $env:TEMP '提取测试 目录'
New-Item -ItemType Directory -Force $t | Out-Null
$out = & dist\czt_extract\czt_extract.exe --game $t --out (Join-Path $env:TEMP '提取测试输出')
if ($LASTEXITCODE -ne 1 -or -not ($out -match '^FAIL check')) { $out; throw '中文路径测试没通过' }
Write-Host '替换程序测试 (提取程序在安装目录里把自己换掉)'
python tools\test_apply_update.py dist\czt_extract\czt_extract.exe
if ($LASTEXITCODE -ne 0) { throw '替换程序测试没通过' }

Write-Host '== 6/6 打包 czt_extract.zip (zip 根目录直接是 czt_extract.exe)'
Remove-Item -Force czt_extract.zip -ErrorAction SilentlyContinue
python -c "import os,zipfile;r='dist/czt_extract';z=zipfile.ZipFile('czt_extract.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9);[z.write(os.path.join(d,f),os.path.relpath(os.path.join(d,f),r).replace(os.sep,'/')) for d,_,fs in os.walk(r) for f in fs];z.close()"
if ($LASTEXITCODE -ne 0) { throw '打包失败' }
$mb = [math]::Round((Get-Item czt_extract.zip).Length / 1MB, 1)
Write-Host "完成: $PSScriptRoot\czt_extract.zip ($mb MB)"
