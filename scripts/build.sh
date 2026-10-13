#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

swift_build_arguments=(--configuration release)
if [[ -n "${ZHUYIN_ASSIST_BUILD_SYSTEM:-}" ]]; then
    swift_build_arguments+=(--build-system "$ZHUYIN_ASSIST_BUILD_SYSTEM")
fi

universal=false
case "${1:-}" in
    --universal) universal=true; shift ;;
    --help)
        printf '用法：%s [--universal]\n' "$0"
        exit 0 ;;
esac
[[ $# -eq 0 ]] || { printf '未知選項：%s\n' "$1" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf '請在 macOS 上建置這個 App。\n' >&2
    exit 1
fi
for generated in .build dist; do
    if [[ -L "$project_root/$generated" ]]; then
        printf '建置資料夾 %s 是連結，請先確認目的地。\n' "$generated" >&2
        exit 1
    fi
done

if [[ "$universal" == true ]]; then
    for architecture in arm64 x86_64; do
        if [[ -L "$project_root/.build/release-$architecture" ]]; then
            printf '架構建置資料夾是連結，請先確認目的地。\n' >&2
            exit 1
        fi
    done
    xcrun swift build "${swift_build_arguments[@]}" --scratch-path .build/release-arm64 --triple arm64-apple-macosx13.0
    arm_binary_dir="$(xcrun swift build "${swift_build_arguments[@]}" --scratch-path .build/release-arm64 --triple arm64-apple-macosx13.0 --show-bin-path)"
    xcrun swift build "${swift_build_arguments[@]}" --scratch-path .build/release-x86_64 --triple x86_64-apple-macosx13.0
    intel_binary_dir="$(xcrun swift build "${swift_build_arguments[@]}" --scratch-path .build/release-x86_64 --triple x86_64-apple-macosx13.0 --show-bin-path)"
else
    xcrun swift build "${swift_build_arguments[@]}"
    binary_dir="$(xcrun swift build "${swift_build_arguments[@]}" --show-bin-path)"
fi
app_path="$project_root/dist/GeminiParagraphCorrection.app"
mkdir -p "$project_root/dist"

# Recreate only this generated bundle; saved user settings live outside it.
if [[ -L "$app_path" ]]; then
    printf '建置目的地是連結，請先移除 dist 中的 App 連結。\n' >&2
    exit 1
fi
if [[ -e "$app_path" ]]; then
    identifier="$(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
    executable="$(plutil -extract CFBundleExecutable raw "$app_path/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$identifier" != "local.chenchungnien.gemini-paragraph-correction" || "$executable" != "GeminiParagraphCorrection" ]]; then
        printf '建置目的地已有其他檔案或 App，未刪除任何內容。\n' >&2
        exit 1
    fi
fi
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "$universal" == true ]]; then
    xcrun lipo -create "$arm_binary_dir/GeminiParagraphCorrection" "$intel_binary_dir/GeminiParagraphCorrection" -output "$app_path/Contents/MacOS/GeminiParagraphCorrection"
    for architecture in arm64 x86_64; do
        xcrun lipo "$app_path/Contents/MacOS/GeminiParagraphCorrection" -verify_arch "$architecture"
    done
else
    cp "$binary_dir/GeminiParagraphCorrection" "$app_path/Contents/MacOS/GeminiParagraphCorrection"
fi
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_root/Resources/AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
cp -R "$project_root/docs" "$app_path/Contents/Resources/docs"
cp "$project_root/README.md" "$app_path/Contents/Resources/README.md"
cp "$project_root/docs/USAGE.md" "$app_path/Contents/Resources/docs/使用說明.md"
chmod 755 "$app_path/Contents/MacOS/GeminiParagraphCorrection"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
printf '建置完成：%s\n' "$app_path"
