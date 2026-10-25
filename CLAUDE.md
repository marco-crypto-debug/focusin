# 🎯 FocusIn 專案 Agent 開工核心準則 (FocusIn Agent Directive)
> ⚠️ **所有 Agent (OpenCode / OMO / Claude / Cursor) 必讀核心約束：**
> 1. **每次開工前，優先從 shared memory 搜尋本 FocusIn 專案相關**：
>    - 🏛 **架構約束** (TeacherApp/StudentApp 邊界、Network.framework、零依賴架構)
>    - 🍎 **Swift 規範** (Swift 5/6、並發安全、MainActor、記憶體管理)
>    - 🎙 **AVAudioEngine 踩坑** (Audio engine reset、format mismatch、buffer overruns)
>    - 🚫 **過往失敗方案** (避免重複過去嘗試失敗的做法)
> 2. **每完成一輪重要決策、找到 bug 根因、確認一個架構選擇**：
>    - 自動寫入 shared memory / `AGENT_MEMORY.md`，標記來源 Agent（OpenCode / OMO）。
> 3. **長期高價值原則**：
>    - 不要記瑣碎對話，只存長期有用知識。


# 🧠 AGENT MEMORY MANDATORY INSTRUCTION
> **CRITICAL WORKFLOW RULE FOR ALL CODING AGENTS (OpenCode, Claude Code, Cursor, Windsurf, Copilot):**
> 1. **BEFORE executing tasks or generating code**: ALWAYS inspect and read `AGENT_MEMORY.md` in the project root.
>    Review what previous agents did, active architectural decisions, and known gotchas.
> 2. **AFTER completing tasks or making design choices**: Log your actions into the Episodic Action Timeline in `AGENT_MEMORY.md`.
