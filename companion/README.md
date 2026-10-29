# Cloudflare IP Test

网页入口：<https://xrefft.github.io/cloudflare/>。

本次根据 olixu/cloudflare-ip-ping 的候选探测和排序思路重新实现。原程序是 Windows Python ICMP ping；这里使用 Go 标准库，直接 TCP 连接选定 IP:443，保持 speed.cloudflare.com 的 TLS SNI、Host 和证书验证。明确禁用系统 HTTP 代理、重定向和连接复用，不使用 InsecureSkipVerify。

## 运行

下载 Release 对应平台包及 SHA256SUMS，校验解压，运行 `cf-speed --open`；Windows 文件名是 `cf-speed.exe`。网站提供每用户安装脚本，可注册 `cfspeed://open`。直接运行二进制不会注册协议。

本地页面在 `http://127.0.0.1:38479/`。只接受 Cloudflare 公布的 IPv4 段，每次最多64个候选、4并发；每请求5秒上限。每个延迟样本建立新的TCP/TLS连接；下载为额外请求，所有实际HTTP请求计入失败率。不能接受测速域名的IP会保留错误原因，不能据此判断所有域名/代理服务不可用。并发下载分享带宽，仅供初筛。

服务仅绑定 loopback，校验 Host、Origin、随机每会话 token，不开放 CORS。远端 GitHub Pages 只启动应用，不读取本地 API。结果可导出 JSON 后在网站导入，不上传到服务器。关闭服务请结束 cf-speed 进程。

## 开发与验证

```sh
GO111MODULE=off go build -o /tmp/cf-speed ./companion
python3 companion/smoke.py /tmp/cf-speed
```

smoke 会启动真实服务，验证跨站/token/候选限制并执行真实1MB下载；没有有效下载则失败。GitHub Actions 分别在 Windows、macOS、Linux 运行本机测试后发布6个二进制包。ARM64交叉编译不等同于每种架构实机验证。

版本更新需同步 workflow 的 version、Release tag 和三个安装脚本的 version；发布包固定版本，不能覆盖既有 Release。如当前源码与既有 tag 不同，发布任务会报错，要求显式升级版本。普通网页改动不重新发布执行器。

## 卸载

先退出执行器。macOS 删除 `~/Applications/Cloudflare IP Test.app`；Linux 删除 `~/.local/share/cf-speed` 与 `~/.local/share/applications/cf-speed.desktop`，并在桌面设置中移除失效协议关联；Windows 删除 `%LOCALAPPDATA%\CloudflareIPTest` 和 `HKCU\Software\Classes\cfspeed` 注册项。安装脚本不覆盖既有安装目录。

来源和许可见 `cloudflare/NOTICE.txt` 与 Apache-2.0 文本。iOS 脚本见 `cloudflare/mobile/README.md`。
