#!/bin/sh
set -eu
[ "$(uname -s)" = Linux ] || { echo '请在 Linux 运行此脚本。' >&2; exit 1; }
case "$(uname -m)" in aarch64|arm64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) echo '不支持此处理器架构。' >&2; exit 1 ;; esac
for tool in curl tar sha256sum awk grep nohup; do command -v "$tool" >/dev/null 2>&1 || { echo "请先安装 $tool。" >&2; exit 1; }; done
version=v0.1.0
base="https://github.com/xrefft/xrefft.github.io/releases/download/cf-speed-$version"
asset="cf-speed-linux-$arch.tar.gz"
install_dir="$HOME/.local/share/cf-speed"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
stage='准备'
trap 'echo "安装在 [$stage] 阶段停止。现有内容已保留，请复制终端错误以便排查。" >&2; exit 1' HUP INT TERM
fail() { echo "[$stage] $*" >&2; exit 1; }
# 每个文件最多三次尝试；连接最多 15 秒，每次下载最多 120 秒。
download() {
    attempt=1
    while ! curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 "$1" -o "$2"; do
        [ "$attempt" -lt 3 ] || fail "下载失败（3 次尝试）：$1"
        attempt=$((attempt + 1))
        echo "下载暂未成功，2 秒后重试（$attempt/3）……" >&2
        sleep 2
    done
}
stage='1/5 下载'; echo "[$stage] $asset"
download "$base/$asset" "$tmp_dir/$asset"
download "$base/SHA256SUMS" "$tmp_dir/SHA256SUMS"
stage='2/5 校验'; echo "[$stage] SHA-256"
expected=$(awk -v file="$asset" '$2 == file {print $1}' "$tmp_dir/SHA256SUMS")
actual=$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || fail 'SHA-256 校验失败，安装已停止。'
tar -xzf "$tmp_dir/$asset" -C "$tmp_dir" || fail '无法解压下载包。'
[ -f "$tmp_dir/cf-speed" ] || fail '下载包缺少 cf-speed。'
stage='3/5 安装'; echo "[$stage] $install_dir"
[ ! -L "$install_dir" ] || fail '安装目录是符号链接，未修改。'
if [ -e "$install_dir" ]; then
    [ -d "$install_dir" ] || fail '安装路径不是目录，未修改。'
    if [ -e "$install_dir/cf-speed" ] || [ -L "$install_dir/cf-speed" ]; then
        [ -f "$install_dir/cf-speed" ] && [ ! -L "$install_dir/cf-speed" ] || fail '已有 cf-speed 不是普通文件，未修改。'
        installed_hash=$(sha256sum "$install_dir/cf-speed" | awk '{print $1}')
        package_hash=$(sha256sum "$tmp_dir/cf-speed" | awk '{print $1}')
        [ "$installed_hash" = "$package_hash" ] || fail '已有程序与当前发布版本不一致。为保留现有内容，未覆盖；请先手动退出并移走旧目录。'
        echo '检测到相同版本，将保留二进制并修复启动注册。'
    else
        for entry in "$install_dir"/* "$install_dir"/.[!.]* "$install_dir"/..?*; do
            if [ -e "$entry" ] || [ -L "$entry" ]; then fail '目录非空且无法确认属于本工具，未修改。'; fi
        done
        cp "$tmp_dir/cf-speed" "$install_dir/cf-speed" || fail '复制程序失败；空目录可重新运行安装。'
    fi
else
    mkdir -p "$install_dir" || fail '无法创建安装目录。'
    cp "$tmp_dir/cf-speed" "$install_dir/cf-speed" || fail '复制程序失败；请重新运行安装。'
fi
chmod 755 "$install_dir/cf-speed" || fail '无法设置执行权限。'
stage='4/5 注册'; echo "[$stage] 桌面启动方式"
registered=false
if { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; } && command -v xdg-mime >/dev/null 2>&1 && command -v xdg-open >/dev/null 2>&1; then
    desktop_exec=$(printf '%s' "$install_dir/cf-speed" | sed 's/[\\"`$]/\\&/g; s/%/%%/g')
    desktop_file="$HOME/.local/share/applications/cf-speed.desktop"
    can_register=true
    if [ -e "$desktop_file" ] || [ -L "$desktop_file" ]; then
        if [ -L "$desktop_file" ] || ! grep -Fxq "Exec=\"$desktop_exec\" --open" "$desktop_file" || ! grep -Fxq 'MimeType=x-scheme-handler/cfspeed;' "$desktop_file"; then
            echo '已有同名 desktop 文件无法确认属于本工具，保留并跳过协议注册。' >&2
            can_register=false
        fi
    fi
    if [ "$can_register" = true ]; then
        mkdir -p "$HOME/.local/share/applications" || fail '无法创建桌面注册目录。'
        cat > "$desktop_file" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Cloudflare IP Test
Exec="$desktop_exec" --open
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/cfspeed;
DESKTOP
        if xdg-mime default cf-speed.desktop x-scheme-handler/cfspeed; then registered=true; else echo '协议注册失败；将继续启动本地服务。' >&2; fi
    fi
else
    echo '未检测到可用桌面会话及 xdg-utils：跳过 cfspeed:// 注册，仍安装和启动本地服务。'
fi
stage='5/5 启动'; echo "[$stage] 检查本地服务"
log_file="$install_dir/runtime.log"
if [ -L "$log_file" ]; then fail '日志路径是符号链接，未启动；请检查安装目录。'; fi
service_ready() {
    info=$(curl --noproxy '*' --fail --silent --connect-timeout 1 --max-time 2 --max-filesize 4096 http://127.0.0.1:38479/api/info 2>/dev/null || true)
    printf '%s' "$info" | grep -Eq '"app"[[:space:]]*:[[:space:]]*"cf-speed"' && printf '%s' "$info" | grep -Eq '"version"[[:space:]]*:[[:space:]]*"v0\.1\.0"'
}
if [ "$registered" = true ]; then
    nohup "$install_dir/cf-speed" --open >> "$log_file" 2>&1 < /dev/null &
elif service_ready; then
    echo '目标版本的本地服务已运行，将保留当前进程。'
else
    nohup "$install_dir/cf-speed" >> "$log_file" 2>&1 < /dev/null &
fi
attempt=0
while [ "$attempt" -lt 15 ]; do
    if service_ready; then
        echo "就绪：$version http://127.0.0.1:38479/"
        if [ "$registered" = true ]; then echo '现在可从网页点击“打开本机测速”。'; else echo '当前没有网页唤起功能，请在本机浏览器打开上述地址。远程机器需先用 SSH 转发本机端口 38479。'; fi
        echo "运行日志：$log_file"
        exit 0
    fi
    attempt=$((attempt + 1)); sleep 1
done
echo '程序已安装，但未确认目标版本服务就绪。没有报告安装成功。' >&2
echo "查看日志：$log_file" >&2
printf '手动启动："%s/cf-speed"\n' "$install_dir" >&2
fail '请检查端口占用、执行权限和日志后重试；现有进程未被终止。'
