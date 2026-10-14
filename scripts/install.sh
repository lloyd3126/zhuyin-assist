#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="/Applications"
launch_app=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --destination)
            [[ $# -ge 2 && -n "$2" ]] || { printf '請提供安裝資料夾。\n' >&2; exit 1; }
            destination="$2"; shift 2 ;;
        --no-launch) launch_app=false; shift ;;
        --help)
            printf '用法：%s [--destination 資料夾] [--no-launch]\n' "$0"
            exit 0 ;;
        *) printf '未知選項：%s\n' "$1" >&2; exit 1 ;;
    esac
done
destination="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).expanduser().resolve())' "$destination")"

"$project_root/scripts/build.sh"

python3 - "$project_root/dist/GeminiParagraphCorrection.app" "$destination" <<'PY'
from pathlib import Path
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
destination = Path(sys.argv[2]).expanduser().resolve()
destination.mkdir(parents=True, exist_ok=True)
target = destination / source.name
identifier = "local.chenchungnien.gemini-paragraph-correction"

if target.is_symlink():
    raise SystemExit("安裝位置是連結，請先確認目的地。")
if target.exists():
    try:
        info = plistlib.loads((target / "Contents/Info.plist").read_bytes())
    except (OSError, plistlib.InvalidFileException):
        raise SystemExit("安裝位置已有其他檔案，未覆蓋任何內容。")
    if info.get("CFBundleIdentifier") != identifier or info.get("CFBundleExecutable") != "GeminiParagraphCorrection":
        raise SystemExit("安裝位置已有其他 App，未覆蓋任何內容。")
    processes = subprocess.check_output(["/bin/ps", "-axww", "-o", "comm="], text=True)
    executable = str(target / "Contents/MacOS/GeminiParagraphCorrection")
    if executable in (line.strip() for line in processes.splitlines()):
        raise SystemExit("App 還在執行。請先從選單列「校」點選「結束」，再重新安裝。")

temporary = Path(tempfile.mkdtemp(prefix=".zhuyin-assist-install-", dir=destination))
incoming = temporary / source.name
previous = temporary / "previous.app"
cleanup = True
try:
    shutil.copytree(source, incoming)
    if target.exists():
        os.replace(target, previous)
    try:
        os.replace(incoming, target)
    except BaseException:
        if previous.exists():
            try:
                os.replace(previous, target)
            except OSError:
                cleanup = False
                raise SystemExit(f"無法復原原 App，已保留在：{previous}")
        raise
finally:
    if cleanup:
        shutil.rmtree(temporary)
print(f"安裝完成：{target}")
print("已保留原有金鑰設定。更新後若快捷鍵未生效，請重新允許輔助使用。")
PY

if [[ "$launch_app" == true ]]; then
    open "$destination/GeminiParagraphCorrection.app"
fi
