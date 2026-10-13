# zhuyin-assist

輕量的 macOS 注音輸入輔助工具。使用 Gemini 校正繁體中文錯字，連按兩下**右側 Option**，就能直接替換選取文字或游標所在段落。

沿用你原有的輸入法，針對「選自」→「選字」這類注音同音誤選提供校正。介面只有選單列，App 目前顯示名稱為「Gemini 段落校正」。

## 功能

- 使用自己的 Gemini API Key，模型固定為 `gemini-flash-lite-latest`。
- 選取文字時校正選取內容；沒有選取時，僅在同一輸入欄位打字後 **2 秒內**校正目前段落。
- 只有焦點在可編輯文字欄位時才觸發，左側 Option 不會觸發。
- 保留原有語氣、空白與換行，只修正語境明確的錯字。
- 同一個選單列位置依序顯示 **校 → spinner → ✓ → 校**。完成提示約 1 秒；失敗時顯示驚嘆號，點開選單查看原因。
- 等待時繼續操作會取消本次校正；替換後可按 `⌘Z` 復原。
- 金鑰欄位支援「貼上」按鈕與 `⌘V`，重新開啟 App 會保留設定。

## 安裝

需要 macOS、Xcode Command Line Tools（Swift 5.9 以上）及 Python 3。專案最低系統版本設定為 macOS 13；目前已在 Apple Silicon、macOS 26.5 上驗證，其他環境仍需實測。

第一次安裝開發工具：

```bash
xcode-select --install
```

從原始碼建置並安裝：

```bash
git clone https://github.com/lloyd3126/zhuyin-assist.git
cd zhuyin-assist
./scripts/install.sh
```

App 會安裝到 `~/Applications/GeminiParagraphCorrection.app` 並啟動。已有舊版時，請先在「校」選單點「結束」，再執行安裝。

第一次使用：

1. 從 [Google AI Studio](https://aistudio.google.com/apikey) 取得 Gemini API Key。
2. 點選單列「校」→「設定 Gemini 金鑰…」，貼上後儲存。
3. 點「允許校正與快捷鍵…」，在系統設定的「隱私權與安全性 → 輔助使用」開啟「Gemini 段落校正」。
4. 回到「校」選單，必要時點「重新啟用快捷鍵」。

詳細步驟與更新後的權限處理，見 [安裝說明](docs/INSTALL.md)；操作方式與測試範例，見 [使用說明](docs/USAGE.md)。

## 金鑰與隱私

校正文字會傳送到 Google Gemini API，金鑰透過請求標頭用於驗證。費用與配額依你的 Gemini API 帳號計算。

金鑰**未加密**，保存在：

```text
~/Library/Application Support/GeminiParagraphCorrection/Private/settings.json
```

App 將資料夾權限設為 `700`、設定檔設為 `600`，並移除額外的存取權限，僅允許目前 Mac 帳號讀寫。同帳號下的其他程式仍可能讀取設定檔。金鑰不會寫進原始碼或診斷紀錄。

設定資料放在 App 外，因此更新 App 會保留金鑰。本 repo 不包含任何個人設定、金鑰或已編譯 App。

## 開發與驗證

```bash
# 建置本機架構的 App bundle
./scripts/build.sh

# 建置並執行離線測試
./scripts/test.sh
```

建置結果位於 `dist/GeminiParagraphCorrection.app`，不會提交到 Git。建置使用本機 ad-hoc 簽章，適合自行編譯安裝；更新後 macOS 可能需要重新允許輔助使用。

測試涵蓋段落與選取範圍、Gemini 回應解析、快捷鍵條件、替換與取消邏輯、設定檔權限、貼上操作，以及選單列動畫與完成／失敗狀態。測試使用假資料，不讀取真正的金鑰或剪貼簿，也不呼叫 Gemini API。動畫測試需要已登入的 macOS 桌面環境。

實際 App 的輸入欄位相容性、替換與復原，請依 [使用說明中的測試步驟](docs/USAGE.md#測試方式) 驗證。

## 專案結構

```text
Sources/ZhuyinAssist/main.swift   App、校正流程與離線測試
Resources/Info.plist             App 名稱、版本與識別設定
scripts/build.sh                建置與封裝 App
scripts/install.sh              安裝或更新 App
scripts/test.sh                 執行離線測試
docs/INSTALL.md                 安裝、更新、移除與權限處理
docs/USAGE.md                   操作方式與測試範例
```

來源為已驗證的 2.1.5 版本。為沿用既有安裝與金鑰路徑，保留 `GeminiParagraphCorrection` 的執行檔名稱、設定位置與 App 識別碼。
