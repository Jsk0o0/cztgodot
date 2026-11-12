"""realesr-animevideov3-x2 (ncnn param/bin) → ONNX; 输入 1x3xHxW float 0..1 (RGB), 输出 1x3x2Hx2W"""
import sys, struct, numpy as np, onnx
from onnx import helper, TensorProto, numpy_helper
param, binf, out = sys.argv[1:4]
lines = open(param).read().split('\n')[2:]
b = open(binf, 'rb').read(); pos = 0
def take_f32(n):
    global pos; a = np.frombuffer(b, '<f4', n, pos).copy(); pos += 4 * n; return a
def take_w(n):
    global pos; tag = struct.unpack_from('<I', b, pos)[0]; pos += 4
    assert tag == 0x01306B47, hex(tag)
    a = np.frombuffer(b, '<f2', n, pos).astype(np.float32); pos += 2 * n; return a
nodes, inits = [], []
def P(k, v): return dict(kv.split('=') for kv in k)[v]
cin = {'data': 3}
for ln in lines:
    t = ln.split()
    if not t: continue
    typ, name, ni, no = t[0], t[1], int(t[2]), int(t[3])
    ins, outs, kv = t[4:4 + ni], t[4 + ni:4 + ni + no], dict(x.split('=') for x in t[4 + ni + no:])
    ins = ['data' if i == 'data' else i for i in ins]
    if typ == 'Input':
        continue
    if typ == 'Split':
        for o in outs: nodes.append(helper.make_node('Identity', ins, [o]))
    elif typ == 'Convolution':
        oc, k, wn = int(kv['0']), int(kv['1']), int(kv['6'])
        ic = wn // (oc * k * k)
        w = take_w(wn).reshape(oc, ic, k, k); bias = take_f32(oc)
        inits += [numpy_helper.from_array(w, name + '_w'), numpy_helper.from_array(bias, name + '_b')]
        nodes.append(helper.make_node('Conv', [ins[0], name + '_w', name + '_b'], outs, pads=[1, 1, 1, 1], kernel_shape=[3, 3]))
    elif typ == 'PReLU':
        s = take_f32(int(kv['0'])).reshape(-1, 1, 1)
        inits.append(numpy_helper.from_array(s, name + '_s'))
        nodes.append(helper.make_node('PRelu', [ins[0], name + '_s'], outs))
    elif typ == 'PixelShuffle':
        nodes.append(helper.make_node('DepthToSpace', ins, outs, blocksize=int(kv['0']), mode='CRD'))
    elif typ == 'Interp':
        sc = float(kv['1'])
        inits.append(numpy_helper.from_array(np.array([1, 1, sc, sc], np.float32), name + '_sc'))
        if kv['0'] == '1':
            nodes.append(helper.make_node('Resize', [ins[0], '', name + '_sc'], outs, mode='nearest', coordinate_transformation_mode='asymmetric', nearest_mode='floor'))
        else:
            nodes.append(helper.make_node('Resize', [ins[0], '', name + '_sc'], outs, mode='cubic', cubic_coeff_a=-0.75, coordinate_transformation_mode='half_pixel'))
    elif typ == 'BinaryOp':
        nodes.append(helper.make_node('Add', ins, outs))
    else:
        raise SystemExit(typ)
assert pos == len(b), (pos, len(b))
g = helper.make_graph(nodes, 'animevideov3x2',
    [helper.make_tensor_value_info('data', TensorProto.FLOAT, [1, 3, 'h', 'w'])],
    [helper.make_tensor_value_info('output', TensorProto.FLOAT, [1, 3, 'H', 'W'])], inits)
m = helper.make_model(g, opset_imports=[helper.make_opsetid('', 13)]); m.ir_version = 8
onnx.checker.check_model(m); onnx.save(m, out); print('ok', out)
