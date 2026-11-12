"""高清放大程序包: 在 Real-ESRGAN ncnn Vulkan Windows 包 (realesrgan-ncnn-vulkan.exe + 模型 + LICENSE) 里加上同一模型的 ONNX 版
(Windows 提取程序用 onnxruntime DirectML 放大, 见 hd_assets._upscale_onnx)
用法: python make_esrgan_zip.py <旧包.zip> <realesr-animevideov3-x2.onnx> <新包.zip>
ONNX 用 tools/ncnn2onnx.py 从包里的 models/realesr-animevideov3-x2.param/.bin 转 (要 pip install onnx)"""
import sys
import zipfile

NOTE = ('\nmodels/realesr-animevideov3-x2.onnx: the same realesr-animevideov3 x2 weights converted from the ncnn .param/.bin '
        'to ONNX (tools/ncnn2onnx.py of the czt fan remake), used with onnxruntime DirectML. BSD-3-Clause, see LICENSE.\n')


def main(src, onnx, dst):
    with zipfile.ZipFile(src) as zi, zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zo:
        for i in zi.infolist():
            if i.filename == 'models/realesr-animevideov3-x2.onnx':
                continue
            data = zi.read(i)
            if i.filename == 'SOURCE.txt' and b'onnx' not in data:
                data = data.rstrip(b'\n') + b'\n' + NOTE.encode()
            zo.writestr(i, data)
        zo.write(onnx, 'models/realesr-animevideov3-x2.onnx')
    print('ok', dst)


if __name__ == '__main__':
    main(*sys.argv[1:4])
