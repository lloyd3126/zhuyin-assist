# zhuyin-assist

輕量的 macOS 注音輸入輔助工具。使用 Gemini 校正繁體中文錯字，或將注音按鍵、注音符號還原成繁體中文。原始碼版也支援補標點與排版。連按兩下**右側 Option**，就能直接替換選取文字或游標所在段落。

沿用你原有的輸入法，支援「選自」→「選字」這類注音同音誤選，以及忘記切換輸入法時的整句按鍵還原。App 目前顯示名稱為「Gemini 段落校正」，透過選單列操作；原始碼版會在校正文字旁顯示浮動提示。[v2.2.0 下載版](https://github.com/lloyd3126/zhuyin-assist/releases/tag/v2.2.0) 已包含三種用途；舊版 2.1.5 只支援中文錯字校正。

**版本差異：目前 `main` 原始碼包含浮動 spinner、補標點與排版；v2.2.0 下載版尚未包含這批功能。** 要使用這批功能，請依下方「從原始碼安裝」建置。

## 功能

- 使用自己的 Gemini API Key，模型固定為 `gemini-flash-lite-latest`。
- 選取文字時校正選取內容；沒有選取時，僅在同一輸入欄位打字後 **2 秒內**校正目前段落。
- 只有焦點在可編輯文字欄位時才觸發，左側 Option 不會觸發。
- 校正明確的中文錯字，保留原有語氣與換行。原始碼版會在語意明確時補標點，短標題、片語與條列項目不強制加句號。
- 原始碼版參考 [中文文案排版指北](https://github.com/sparanoid/chinese-copywriting-guidelines)，整理中英文、數字與常見單位間距，中文敘述的數字使用半形；`15%`、`90°` 保持相連。詳見 [補標點與排版](docs/USAGE.md#補標點與排版)。
- 網址、英文識別字、行內程式碼與 Markdown 連結等內容以佔位符保護；一般中文校正另比對數字序列，受保護內容或數值被改動時拒絕替換。程式碼應使用反引號或程式碼區塊明確標示。
- 標準注音鍵盤按鍵先在本機映射成注音，再交給 Gemini 依上下文選字；也支援直接輸入注音符號。範例見 [三種用途](docs/USAGE.md#三種用途)。
- 同一個選單列位置依序顯示 **校 → spinner → ✓ → 校**。完成提示約 1 秒；失敗時顯示驚嘆號，點開選單查看原因。
- 原始碼版另在文字末端旁顯示原生 **spinner ＋「校正中」**，不改動文件、不取得鍵盤焦點；完成、失敗或取消時自動移除。無法定位文字末端時改放輸入框右上角，仍無法定位則使用選單列提示。
- 等待時繼續操作會取消本次校正；替換後可按 `⌘Z` 復原。
- 金鑰欄位支援「貼上」按鈕與 `⌘V`，重新開啟 App 會保留設定。

## 安裝

### 直接下載 App

不需要安裝開發工具。到 [最新 Release](https://github.com/lloyd3126/zhuyin-assist/releases/latest) 下載 `zhuyin-assist-版本-macOS-universal.zip`，解壓縮後將 `GeminiParagraphCorrection.app` 拖到「應用程式」並開啟。

下載版包含 Apple Silicon 與 Intel 兩種架構，最低系統版本設定為 macOS 13；新版功能已在 Apple Silicon、macOS 27.0.1 上建置與試用，Intel 與較舊系統仍需實測。App 使用本機簽章，尚未取得 Apple 開發者認證與公證。首次開啟如果遭到阻擋，請依 [安裝說明](docs/INSTALL.md#首次開啟下載版) 在系統設定允許這個 App。

### 從原始碼安裝

需要 macOS、Xcode Command Line Tools（Swift 5.9 以上）及 Python 3。專案最低系統版本設定為 macOS 13；原版已在 Apple Silicon、macOS 26.5 上驗證，本次新增功能已在 Apple Silicon、macOS 27.0.1 上建置與試用，其他環境仍需實測。

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
3. 點「允許校正與快捷鍵…」，在「隱私權與安全性 → 輔助使用」開啟已安裝的 App；macOS 27.0.1 的頁面名稱為「裝置控制和資料取用」，清單可能顯示 `GeminiParagraphCorrection.app`。
4. 在「隱私權與安全性 → 輸入監控」也開啟這個 App，依提示重新啟動。回到「校」選單，必要時點「重新啟用快捷鍵」。

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

# 建置 Apple Silicon + Intel App，產生 ZIP 與 SHA-256 校驗檔
./scripts/package-release.sh
```

建置結果位於 `dist/GeminiParagraphCorrection.app`，不會提交到 Git。建置使用本機 ad-hoc 簽章，適合自行編譯安裝；更新後 macOS 可能需要重新允許輔助使用與輸入監控。即使設定開關仍顯示開啟，舊簽章的授權也可能未生效，處理方式見 [更新後重新授權](docs/INSTALL.md#更新)。

若目前的 SwiftPM 預設建置引擎無法使用，可在仍支援 `native` 引擎的工具鏈上指定：

```bash
ZHUYIN_ASSIST_BUILD_SYSTEM=native ./scripts/test.sh
# 同樣可用於 ./scripts/build.sh 或 ./scripts/install.sh
```

`native` 已被 SwiftPM 標為 deprecated；此選項用於相容現有工具鏈，並非未來版本的保證。

測試涵蓋段落與選取範圍、注音按鍵映射與保守辨識、Gemini 請求與回應解析、快捷鍵條件、替換與取消邏輯、設定檔權限、貼上操作，以及選單列動畫與完成／失敗狀態。測試使用假資料，不讀取真正的金鑰或剪貼簿，也不呼叫 Gemini API；模型選字品質須另行實測。動畫測試需要已登入的 macOS 桌面環境。

實際 App 的輸入欄位相容性、替換與復原，請依 [使用說明中的測試步驟](docs/USAGE.md#測試方式) 驗證。

### 本機驗證紀錄

2026-10-13，驗證新增三種用途的本機原始碼版本；這些功能收錄於 [v2.2.0 Release](https://github.com/lloyd3126/zhuyin-assist/releases/tag/v2.2.0)。

- Apple Silicon、macOS 27.0.1：透過 `native` 建置引擎完成建置，全部離線測試通過。
- Gemini 實測 8 項全部符合預期：中文錯字、完整注音按鍵、注音符號、另一句按鍵與注音、多行格式、短按鍵字串保留，以及英文／網址／程式碼保留。
- 新版已在本機安裝並完成手動試用，使用者回饋結果可接受；重新授權後，App 回報兩項權限與右側 Option 快捷鍵均已啟用。

上述結果涵蓋這次範例與環境，模型選字品質及其他 App 的輸入欄位相容性仍需持續實測。

同日後續更新的原始碼版新增浮動 spinner、補標點與排版：

- Apple Silicon、macOS 27.0.1：完成建置、簽章檢查、本機安裝與重新啟動，確認原有金鑰設定保留。
- 使用者先後回報浮動 spinner，以及補標點與排版的本機試用成功。
- 這批功能未新增或執行離線測試，也未進行新的 Gemini 自動實測；上述試用回饋不代表所有標點、排版與內容保護案例均已驗證。
- 本機更新使用 ad-hoc 簽章，更新後的兩項權限由使用者自行處理。這批功能尚未發布新的 Release。

## 專案結構

```text
Sources/ZhuyinAssist/main.swift   App、校正流程與離線測試
Sources/ZhuyinAssist/ProcessingHint.swift  浮動 spinner 與定位
Sources/ZhuyinAssist/CopywritingFormatting.swift  內容保護、排版與數字檢查
Resources/Info.plist             App 名稱、版本與識別設定
scripts/build.sh                建置與封裝 App
scripts/install.sh              安裝或更新 App
scripts/test.sh                 執行離線測試
scripts/package-release.sh      封裝供下載的雙架構 App
docs/INSTALL.md                 安裝、更新、移除與權限處理
docs/USAGE.md                   操作方式與測試範例
```

來源為已驗證的 2.1.5 版本。為沿用既有安裝與金鑰路徑，保留 `GeminiParagraphCorrection` 的執行檔名稱、設定位置與 App 識別碼。
