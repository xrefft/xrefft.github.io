Windows、macOS、Linux 本机 HTTPS 测速执行器。提供 x64 / ARM64，安装入口：https://xrefft.github.io/cloudflare/ 。

执行器仅监听 127.0.0.1:38479。连接指定 Cloudflare IPv4，同时校验 speed.cloudflare.com 的 TLS 证书。指标为 HTTP 请求失败率、完整 HTTPS 请求耗时及实际下载速率，不是 ICMP ping，也不保证特定代理协议可用。

下载对应系统/架构的压缩包，使用 SHA256SUMS 校验，解压后运行 cf-speed --open；或使用网站安装脚本注册 cfspeed:// 启动链接。无需管理员权限。此版本未做 Apple 公证或 Windows 代码签名，系统可能提示未知开发者。

iOS 不运行这些桌面二进制。网站另提供 a-Shell + 快捷指令脚本和配置说明；iOS 实机验证尚未完成。
