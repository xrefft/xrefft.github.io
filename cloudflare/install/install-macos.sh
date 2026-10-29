#!/bin/sh
set -eu
[ "$(uname -s)" = Darwin ] || { echo '请在 macOS 运行此脚本。' >&2; exit 1; }
case "$(uname -m)" in arm64) arch=arm64 ;; x86_64) arch=amd64 ;; *) echo '不支持此处理器架构。' >&2; exit 1 ;; esac
version=v0.1.0
base="https://github.com/xrefft/xrefft.github.io/releases/download/cf-speed-$version"
asset="cf-speed-darwin-$arch.tar.gz"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
curl --fail --location --proto '=https' --tlsv1.2 "$base/$asset" -o "$tmp_dir/$asset"
curl --fail --location --proto '=https' --tlsv1.2 "$base/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"
expected=$(awk -v file="$asset" '$2 == file {print $1}' "$tmp_dir/SHA256SUMS")
actual=$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo 'SHA-256 校验失败，安装已停止。' >&2; exit 1; }
tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
app_dir="$HOME/Applications/Cloudflare IP Test.app"
if [ -e "$app_dir" ]; then echo '该应用目录已存在。请先退出并移走旧应用，再安装。' >&2; exit 1; fi
mkdir -p "$app_dir/Contents/MacOS"
cp "$tmp_dir/cf-speed" "$app_dir/Contents/MacOS/cf-speed"
chmod 755 "$app_dir/Contents/MacOS/cf-speed"
cat > "$app_dir/Contents/MacOS/launch" <<'EOF'
#!/bin/sh
app_bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$HOME/Library/Logs"
nohup "$app_bin_dir/cf-speed" --open >> "$HOME/Library/Logs/cf-speed.log" 2>&1 < /dev/null &
EOF
chmod 755 "$app_dir/Contents/MacOS/launch"
cat > "$app_dir/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.xrefft.cf-speed</string>
<key>CFBundleName</key><string>Cloudflare IP Test</string>
<key>CFBundleExecutable</key><string>launch</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>Cloudflare IP Test</string><key>CFBundleURLSchemes</key><array><string>cfspeed</string></array></dict></array>
</dict></plist>
EOF
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
echo "安装完成：$app_dir"
echo '现在可从网页点击“打开本机测速”。卸载时退出执行器并删除此应用。'
open "$app_dir"
