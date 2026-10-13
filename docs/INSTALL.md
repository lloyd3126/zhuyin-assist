# 安裝說明

## 下載版：不用編譯

1. 到 [最新 Release](https://github.com/lloyd3126/zhuyin-assist/releases/latest)，下載 `zhuyin-assist-版本-macOS-universal.zip`。GitHub 自動提供的「Source code」是原始碼，請下載上述 App ZIP。
2. 解壓縮，將 `GeminiParagraphCorrection.app` 拖到「應用程式」資料夾。
3. 開啟 App，完成下方的 Gemini 金鑰與輔助使用設定。

下載版包含 Apple Silicon 與 Intel 兩種架構。最低系統版本設定為 macOS 13；目前實際測試環境為 Apple Silicon、macOS 26.5，Intel 與較舊系統仍需實測。

### 首次開啟下載版

App 使用本機簽章，尚未取得 Apple 開發者認證與公證。若 macOS 提示無法驗證開發者或無法檢查是否包含惡意軟體：

1. 先嘗試開啟 App，關閉阻擋提示。
2. 前往「系統設定 → 隱私權與安全性」，找到這個 App 的提示，按「仍要打開」。
3. 依 macOS 提示確認開啟。

只允許從本 repo 下載、且你信任的 App。無需關閉整台 Mac 的安全保護。詳見 [Apple 的首次開啟說明](https://support.apple.com/102445)。受公司管理的 Mac 可能不允許這項操作。

Release 同時附上 `.zip.sha256` 校驗檔，可選擇驗證下載內容是否完整。在 ZIP 與校驗檔所在資料夾執行：

```bash
shasum -a 256 -c zhuyin-assist-2.1.5-macOS-universal.zip.sha256
```

### 更新下載版

先從「校」選單點「結束」，下載新版並以解壓縮後的 App 替換原 App。金鑰會保留。更新後若快捷鍵失效，依下方「更新」段落重新允許輔助使用。

## 準備

需要 macOS、Swift 5.9 以上與 Python 3。可安裝 Xcode Command Line Tools：

```bash
xcode-select --install
```

安裝完成後可確認：

```bash
xcrun swift --version
python3 --version
```

專案最低系統版本設定為 macOS 13。目前已驗證的環境為 Apple Silicon、macOS 26.5；建置只包含這台 Mac 的架構。

## 建置與安裝

```bash
git clone https://github.com/lloyd3126/zhuyin-assist.git
cd zhuyin-assist
./scripts/install.sh
```

預設安裝在：

```text
~/Applications/GeminiParagraphCorrection.app
```

系統中顯示的名稱是「Gemini 段落校正」。啟動後，選單列會出現「校」。

只建置，不安裝：

```bash
./scripts/build.sh
```

結果為 `dist/GeminiParagraphCorrection.app`。

指定安裝位置，或安裝後暫不啟動：

```bash
./scripts/install.sh --destination "$HOME/Applications" --no-launch
```

App 目前需要手動啟動，尚未設定登入時自動開啟。

## 設定 Gemini 金鑰

1. 從 [Google AI Studio](https://aistudio.google.com/apikey) 取得 Gemini API Key。
2. 複製金鑰，點「校」→「設定 Gemini 金鑰…」。
3. 按「貼上」或使用 `⌘V`，再按「儲存」。

欄位會隱藏金鑰內容。金鑰保存在本機未加密設定檔，限制目前 Mac 帳號讀寫；詳細位置與保護範圍見 [README](../README.md#金鑰與隱私)。

## 允許校正與快捷鍵

1. 點「校」→「允許校正與快捷鍵…」。
2. 在「系統設定 → 隱私權與安全性 → 輔助使用」開啟「Gemini 段落校正」。
3. 如果清單裡沒有它，按「＋」，選取已安裝的 `GeminiParagraphCorrection.app`。
4. 回到「校」選單，必要時點「重新啟用快捷鍵」；若仍未生效，結束並重新開啟 App。

「輔助使用」允許 App 讀取、替換輸入欄位文字及監聽快捷鍵。只有游標在可編輯欄位、且有選取文字或剛打完字時，才會進行校正。

## 更新

先從「校」選單點「結束」，再在 repo 內執行：

```bash
git pull --ff-only
./scripts/install.sh
```

安裝腳本只替換 App，已儲存的金鑰會保留。如果原 App 正在執行，腳本會停止安裝並請你先結束 App。

自行建置的簽章會隨程式版本改變，macOS 可能不沿用舊版授權。如果更新後快捷鍵失效：

1. 從輔助使用清單移除舊項目，按「＋」加入已更新的 App，再開啟權限。
2. 結束並重新開啟 App。
3. 回到「校」選單，點「重新啟用快捷鍵」。

若仍被舊版監聽記錄阻擋，可先結束 App，僅清除此 App 的舊監聽記錄，再重新啟動：

```bash
tccutil reset ListenEvent local.chenchungnien.gemini-paragraph-correction
open "$HOME/Applications/GeminiParagraphCorrection.app"
```

## 常見問題

**儲存金鑰失敗**：點開「校」查看訊息，確認目前 Mac 帳號可以存取設定位置。App 使用設定檔保存金鑰，無需登入鑰匙圈。

**快捷鍵沒有反應**：先在 TextEdit 選取一段文字，再快速按下、放開右側 Option 兩次；確認 App 已執行且有輔助使用權限。只有剛在同一欄位打字後 2 秒內，才可在未選取文字時觸發。

**出現驚嘆號**：點開「校」或「查看最近狀態…」讀取原因。可能是金鑰無效、配額不足、網路中斷或該 App 的文字欄位不支援直接替換。

**有動畫但後來取消**：等待時繼續打字、點擊、捲動、移動游標或切換 App，會取消本次校正。

## 移除

1. 點「校」→「結束」。
2. 將 `GeminiParagraphCorrection.app` 移到垃圾桶。
3. 若也要移除金鑰設定，可自行刪除 `~/Library/Application Support/GeminiParagraphCorrection/Private`。

刪除 App 本身會保留金鑰設定；第 3 步才會移除設定檔。
