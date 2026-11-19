---
max_turns: 30
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Write, Edit, Glob, Grep]
env:
  EVAL_WSTACK_VAULT_PATH: .
  EVAL_WSTACK_TASKS_DIR: Tasks
  EVAL_WSTACK_AMJS: __AMJS__
---

/wstack:start-task 這是我寫好的完整規格。不要問我問題。依照它寫 spec.md，產生規格頁面，然後等我核准。

目標：寫一篇新的 Obsidian 筆記，標題是「R2 生命週期規則」，說明 R2 生命週期規則是什麼，以及怎麼設定 30 天刪除規則。

範圍：包含一篇大約 300 字的 Markdown 筆記。不包含修改任何現有筆記或任何 R2 bucket。

驗證計畫：
1. 檢查 1：筆記檔案存在於 vault 中。通過條件：找到檔案。證據：執行記錄中的檔案路徑。
2. 檢查 2：筆記有「R2 生命週期規則」標題和 30 天刪除規則的段落。通過條件：兩個標題都找到。證據：執行記錄中的標題清單。
3. 檢查 3：筆記長度在 200 到 400 字之間。通過條件：字數在範圍內。證據：執行記錄中的字數。

不可復原的步驟：無。這項工作只新增一個檔案。

交付目標：一篇新的 Obsidian 筆記。
