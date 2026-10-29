#!/bin/sh
set -eu
[ "$(uname -s)" = Linux ] || { echo '请在 Linux 运行此脚本。' >&2; exit 1; }
case "$(uname -m)" in aarch64|arm64) arch=arm64 ;; x86_64|amd64) arch=amd64 ;; *) echo '不支持此处理器架构。' >&2; exit 1 ;; esac
for tool in curl tar sha256sum xdg-mime xdg-open; do command -v "$tool" >/dev/null 2>&1 || { echo "请先安装 $tool（桌面支持来自 xdg-utils）。" >&2; exit 1; }; done
version=v0.1.0
base="https://github.com/xrefft/xrefft.github.io/releases/download/cf-speed-$version"
asset="cf-speed-linux-$arch.tar.gz"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
curl --fail --location --proto '=https' --tlsv1.2 "$base/$asset" -o "$tmp_dir/$asset"
curl --fail --location --proto '=https' --tlsv1.2 "$base/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"
expected=$(awk -v file="$asset" '$2 == file {print $1}' "$tmp_dir/SHA256SUMS")
actual=$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo 'SHA-256 校验失败，安装已停止。' >&2; exit 1; }
tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
install_dir="$HOME/.local/share/cf-speed"
if [ -e "$install_dir" ]; then echo '安装目录已存在。请先退出执行器并移走旧目录，再安装。' >&2; exit 1; fi
mkdir -p "$install_dir" "$HOME/.local/share/applications"
cp "$tmp_dir/cf-speed" "$install_dir/cf-speed"
chmod 755 "$install_dir/cf-speed"
# Desktop Entry quoted arguments must escape backslash, double quote, backtick and dollar.
desktop_exec=$(printf '%s' "$install_dir/cf-speed" | sed 's/[\\"`$]/\\&/g; s/%/%%/g')
cat > "$HOME/.local/share/applications/cf-speed.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Cloudflare IP Test
Exec="$desktop_exec" --open
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/cfspeed;
EOF
xdg-mime default cf-speed.desktop x-scheme-handler/cfspeed
echo "安装完成：$install_dir"
echo '可从网页点击“打开本机测速”。卸载时退出进程，删除安装目录和 cf-speed.desktop。'
"$install_dir/cf-speed" --open > "$install_dir/runtime.log" 2>&1 < /dev/null &
