# iOS 本机测速脚本

此脚本需要先安装 [a-Shell](https://apps.apple.com/us/app/a-shell/id1473805438)，不能直接在 Safari 中执行。它使用 Python 标准库直连候选 IP，并以 `speed.cloudflare.com` 进行 TLS SNI 和证书验证；不会修改代理、DNS 或系统配置。

## 首次配置

1. 从 App Store 安装并打开 a-Shell。
2. 下载本目录的 `cf_probe.py`，在“文件”中移到“我的 iPhone / a-Shell”目录。该目录是 a-Shell 的 Documents；如果系统自动增加了 `.txt` 后缀，请恢复 `.py` 后缀。
3. 在 a-Shell 手动运行：

   ```sh
   cd ~/Documents
   python3 cf_probe.py --defaults
   ```

   如提示文件不存在，先用“文件”确认文件实际位置，再在 a-Shell 输入 `pwd`、`ls` 核对。不同版本的文件提供器显示可能不同。

4. 等待完成，结果位于当前目录的 `cf-results.json`。回到测速网页，选择“导入结果”，从“文件 / a-Shell”选中该 JSON。

默认测试 8 个示例 IP。每个 IP 做 3 轮，每轮分别进行一个零字节 HTTPS 请求和一次 1 MB 下载，共 6 个独立请求；`attempts` 为 6，`successes` 是有效请求数，`failureRate` 是失败请求数除以 6。证书、HTTP 状态或下载字节数不符都会记为失败；下载失败不会丢弃已经成功的延迟样本。每个请求最多 5 秒，默认下载最多约 24 MB，请留意移动流量。延迟是零字节完整 HTTPS 请求耗时的中位数，下载速度是有效下载样本的中位数，均不是 ICMP ping 指标。

## 从网页启动

在 Apple“快捷指令”中新建快捷指令，名称必须为 `Cloudflare IP Test`，添加 a-Shell 的 `Execute command` 动作，命令填写：

```sh
cd ~/Documents
python3 ~/Documents/cf_probe.py --defaults
```

先在快捷指令内运行一次，按照系统提示授予运行权限。网页通过以下官方 URL scheme 启动已保存的快捷指令：

```text
shortcuts://run-shortcut?name=Cloudflare%20IP%20Test
```

网页不会自动安装 App 或快捷指令。此处没有伪装成安装包的文件，也没有预先签名的 `.shortcut`。首次配置后，点击网页按钮会切换到快捷指令或 a-Shell；测速时请保持应用在前台，完成后手动回网页导入结果。Safari 不能保证在 iOS 后台持续访问另一个 App 的本地服务，因此没有假设自动回传成功。

## 自选 IP

在 a-Shell 手动运行交互模式，按提示粘贴最多 32 个 IP（空格或逗号分隔）：

```sh
cd ~/Documents
python3 cf_probe.py --interactive
```

也可运行 `python3 cf_probe.py --ips '104.16.0.1,104.17.0.1'`。脚本只允许固定的 [Cloudflare IPv4 网段](https://www.cloudflare.com/ips-v4/)，不接收任意域名、URL 或 shell 命令。它使用本机网络直接连接，不读取系统 HTTP 代理环境变量；VPN 路由仍可能影响实际线路。

结果使用网页和桌面测速工具相同的 JSON 字段，`latencyMs` 与 `downloadMbps` 在没有成功样本时为 `null`。

## 验证范围

Python 网络路径可在 macOS 真实网络验证。iOS a-Shell、文件导入和快捷指令尚未经过 iOS 实机验证，不应宣称已经验证通过。a-Shell 的 Python 和 Shortcuts 能力分别见 [App Store 说明](https://apps.apple.com/us/app/a-shell/id1473805438)、[官方更新说明](https://holzschu.github.io/a-Shell_iOS/changelog/)；启动格式见 [Apple 官方说明](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/ios)。
