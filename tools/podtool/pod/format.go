// .pod v1 —— 创意工坊 mod 包 (防看防改: 本地加密 + 作者签名, 不是付费授权)
//
// 布局 (整数一律小端):
//
//	"POD1"            4  魔数
//	version   u16        1
//	flags     u16        0
//	idLen u16 + id       mod id (UTF-8, 明文, 列表里不解密就能显示)
//	pubLen u16 + pub     作者 RSA-2048 公钥 (PKIX DER)
//	wrapIV    16         主密钥加密内容密钥用的 IV
//	wrapped   48         AES-256-CBC(主密钥, wrapIV, 内容密钥 32 字节 + PKCS7 填充)
//	iv        16         正文 IV
//	bodyLen   u64
//	body      bodyLen    AES-256-CBC(内容密钥, iv, 归档 + PKCS7 填充)
//	mac       32         HMAC-SHA256(SHA256(内容密钥 ‖ "pod-mac"), 以上全部字节)
//	sigLen u16 + sig     RSA PKCS#1 v1.5 签名, 对 SHA256(以上全部字节, 含 mac) 签
//
// 归档 (解密后): "PODA" + count u32 + count × (pathLen u16, path, size u32, data)
// 游戏端 (godot/scripts/pod.gd) 校验顺序: 魔数 → 签名 → 解开内容密钥 → HMAC → 解密 → 解包, 任何一步失败都拒绝加载。
package pod

const (
	Magic        = "POD1"
	Version      = 1
	ArchiveMagic = "PODA"
)
