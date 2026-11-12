extends RefCounted
## 自动更新清单 (latest.json) 的验签公钥: 作者密钥 ~/.config/czt-pod/author.pem 的公钥部分 (RSA 2048, 公开无妨)
## 换密钥时: openssl rsa -in <新私钥> -pubout 替换下面的 PEM; 旧版本游戏只认旧公钥, 要先用旧密钥发一版带新公钥的更新
const PEM := """-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2WYu5XBBgOmFEUnH1KpA
VFVM4nBHaPBpYRGW8b9+vIHtID2WuMkRj9s6xz3cWcYFO+AUM3pu4xrDyD4xFGBj
Ar0RKAAZ6X5fuClFt80zsH4KZ7qM5VbM8S7izWgs0Ae+Nbhn6kYUqeYO1luHIMfK
r5x98X7mZdsWe+B5YLHbH8IAio3K3Bs5KbZ38BgGfAq3SbZ7yytpV7HV34cRPSpt
QCSYkeMj+z9frtW1Reh0K3zeUyb1PWQDg32zKu4lXq/0kONaM4xCA+h0fFZB3drh
C4qhKVRGaEOCfMHmMtbVeifcKHmj3sQkTkrvnV5C1ISjfwmohfyruupKGFyvxUpD
sQIDAQAB
-----END PUBLIC KEY-----
"""
