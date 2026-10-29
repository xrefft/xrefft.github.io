#!/bin/sh
set -eu
[ "$(uname -s)" = Darwin ] || { echo '请在 macOS 运行此脚本。' >&2; exit 1; }
case "$(uname -m)" in arm64) arch=arm64 ;; x86_64) arch=amd64 ;; *) echo '不支持此处理器架构。' >&2; exit 1 ;; esac
version=v0.1.0
base="https://github.com/xrefft/xrefft.github.io/releases/download/cf-speed-$version"
asset="cf-speed-darwin-$arch.tar.gz"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
echo '步骤 1/5：下载正式发布包与校验和…'
curl --connect-timeout 15 --max-time 180 --retry 2 --fail --location --proto '=https' --tlsv1.2 "$base/$asset" -o "$tmp_dir/$asset"
curl --connect-timeout 15 --max-time 180 --retry 2 --fail --location --proto '=https' --tlsv1.2 "$base/SHA256SUMS" -o "$tmp_dir/SHA256SUMS"
echo '步骤 2/5：校验下载文件…'
expected=$(awk -v file="$asset" '$2 == file {print $1}' "$tmp_dir/SHA256SUMS")
actual=$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')
[ -n "$expected" ] && [ "$expected" = "$actual" ] || { echo 'SHA-256 校验失败，安装已停止。' >&2; exit 1; }
tar -xzf "$tmp_dir/$asset" -C "$tmp_dir"
app_dir="$HOME/Applications/Cloudflare IP Test.app"
echo '步骤 3/5：安装或修复当前版本…'
for target in "$app_dir" "$app_dir/Contents" "$app_dir/Contents/MacOS" "$app_dir/Contents/MacOS/cf-speed" "$app_dir/Contents/MacOS/launch" "$app_dir/Contents/Info.plist"; do
  [ ! -L "$target" ] || { echo "安装路径包含符号链接，已保留：$target" >&2; exit 1; }
done
if [ -e "$app_dir" ]; then
  installed="$app_dir/Contents/MacOS/cf-speed"
  if [ ! -f "$installed" ]; then
    echo "该目录无法确认为本工具，已保留：$app_dir" >&2; exit 1
  fi
  current_hash=$(shasum -a 256 "$installed" | awk '{print $1}')
  downloaded_hash=$(shasum -a 256 "$tmp_dir/cf-speed" | awk '{print $1}')
  [ "$current_hash" = "$downloaded_hash" ] || { echo "已有文件与当前发布包不同，已保留。请退出旧工具并将应用移到其它位置后重试：$app_dir" >&2; exit 1; }
  echo '已确认同版本执行器，将修复启动入口。'
else
  mkdir -p "$app_dir/Contents/MacOS"
  cp "$tmp_dir/cf-speed" "$app_dir/Contents/MacOS/cf-speed"
fi
mkdir -p "$app_dir/Contents/MacOS"
chmod 755 "$app_dir/Contents/MacOS/cf-speed"
cat > "$app_dir/Contents/MacOS/launch" <<'EOF'
#!/bin/sh
app_bin_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$HOME/Library/Logs"
log_file="$HOME/Library/Logs/cf-speed.log"
[ ! -L "$log_file" ] || exit 1
if [ -e "$log_file" ] && [ ! -f "$log_file" ]; then exit 1; fi
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
echo '步骤 4/5：注册网页启动入口…'
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_dir"
echo '步骤 5/5：启动并检查本机服务…'
open "$app_dir" || { echo "无法打开应用。请手动运行：\"$app_dir/Contents/MacOS/cf-speed\" --open" >&2; exit 1; }
ready=0
attempt=0
while [ "$attempt" -lt 20 ]; do
  response=$(curl --fail --noproxy '*' --connect-timeout 1 --max-time 2 --silent http://127.0.0.1:38479/api/info || true)
  case "$response" in
    *'"app":"cf-speed"'*'"version":"v0.1.0"'*) ready=1; break ;;
  esac
  attempt=$((attempt + 1))
  sleep 1
done
if [ "$ready" -ne 1 ]; then
  echo "文件已安装，但测速服务未就绪。日志：$HOME/Library/Logs/cf-speed.log" >&2
  echo "请手动运行：\"$app_dir/Contents/MacOS/cf-speed\" --open" >&2
  exit 1
fi
echo "安装与启动验证成功：$app_dir"
echo '现在可打开 http://127.0.0.1:38479/ 或从网页点击“打开本机测速”。'
