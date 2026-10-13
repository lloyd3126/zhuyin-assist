#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_root/scripts/build.sh" --universal
app_path="$project_root/dist/GeminiParagraphCorrection.app"
version="$(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf '版本格式不正確。\n' >&2; exit 1; }
asset_name="zhuyin-assist-${version}-macOS-universal.zip"
archive="$project_root/dist/$asset_name"
checksum="$archive.sha256"
for output in "$archive" "$checksum"; do
    if [[ -e "$output" || -L "$output" ]]; then
        printf '發佈檔案已存在，請先確認後移走：%s\n' "$output" >&2
        exit 1
    fi
done

codesign --verify --deep --strict "$app_path"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
(cd "$project_root/dist" && shasum -a 256 "$asset_name" > "$asset_name.sha256")
printf '發佈檔案：%s\n校驗檔案：%s\n' "$archive" "$checksum"
