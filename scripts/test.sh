#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$project_root/scripts/build.sh"
executable="$project_root/dist/GeminiParagraphCorrection.app/Contents/MacOS/GeminiParagraphCorrection"

"$executable" --self-test
"$executable" --settings-test
"$executable" --paste-test
"$executable" --indicator-test
printf '所有測試通過。測試未使用真正的金鑰、剪貼簿或 Gemini API。\n'
