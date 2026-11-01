// 用官方 glTF Validator 检查 GLB: node validate.mjs <目录或文件>...
// 逐个打印有问题的文件, 最后汇总; 有错误时退出码为 1
import fs from 'fs';
import path from 'path';
import v from 'gltf-validator';

const files = [];
const walk = (p) => fs.statSync(p).isDirectory()
  ? fs.readdirSync(p).forEach((f) => walk(path.join(p, f)))
  : p.endsWith('.glb') && files.push(p);
process.argv.slice(2).forEach(walk);

let errors = 0, warnings = 0, bad = 0;
for (const f of files) {
  const r = await v.validateBytes(new Uint8Array(fs.readFileSync(f)));
  errors += r.issues.numErrors;
  warnings += r.issues.numWarnings;
  if (r.issues.numErrors) {
    bad++;
    console.log(f, 'errors', r.issues.numErrors);
    for (const m of r.issues.messages.filter((m) => m.severity === 0).slice(0, 5)) console.log('  ', m.code, m.message, m.pointer);
  }
}
console.log(`${files.length} 个 GLB, 错误 ${errors} (${bad} 个文件), 警告 ${warnings}`);
process.exit(errors ? 1 : 0);
