#!/bin/bash
# 久坐提醒 · 构建脚本（通用二进制：Apple Silicon + Intel）
# 用法：cd 到本目录后执行 ./build.sh
set -e
cd "$(dirname "$0")"

APP="久坐提醒.app/Contents"
rm -rf "久坐提醒.app"
echo "生成图标..."
mkdir -p Assets/AppIcon.iconset
for spec in "16:16" "32:16x16@2x" "32:32" "64:32x32@2x" "128:128" "256:128x128@2x" "256:256" "512:256x256@2x" "512:512"; do
  size="${spec%%:*}"; name="${spec##*:}"
  sips -z "$size" "$size" Assets/AppIcon-trimmed.png --out "Assets/AppIcon.iconset/icon_${name}.png" >/dev/null
done
cp Assets/AppIcon-trimmed.png Assets/AppIcon.iconset/icon_512x512@2x.png
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns

echo "编译 arm64..."
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift \
  -o /tmp/UsageReminder-arm64 -framework Cocoa -framework IOKit

echo "编译 x86_64..."
swiftc -O -swift-version 5 -target x86_64-apple-macos14.0 Sources/*.swift \
  -o /tmp/UsageReminder-x86_64 -framework Cocoa -framework IOKit

echo "合并通用二进制并打包..."
mkdir -p "$APP/MacOS" "$APP/Resources"
lipo -create /tmp/UsageReminder-arm64 /tmp/UsageReminder-x86_64 \
  -output "$APP/MacOS/UsageReminder"
cp Info.plist "$APP/Info.plist"
cp Assets/AppIcon.icns "$APP/Resources/AppIcon.icns"

echo "临时签名（ad-hoc）..."
# 经无属性中转目录签名，规避 provenance/FinderInfo 残留导致的 detritus 报错
rm -rf /tmp/ur-sign.app
ditto --norsrc --noextattr "久坐提醒.app" /tmp/ur-sign.app
codesign --force --deep --sign - /tmp/ur-sign.app
rm -rf "久坐提醒.app" && mv /tmp/ur-sign.app "久坐提醒.app"

echo "完成：久坐提醒.app（装到 /Applications 后，数据在 ~/Library/Application Support/UsageReminder/）"
file "$APP/MacOS/UsageReminder"
