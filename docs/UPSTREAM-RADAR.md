# รายการตรวจสอบการอัปเดตจากต้นทาง (Upstream Radar & Update Checklist)

เอกสารนี้รวบรวมแหล่งอ้างอิงทั้งหมดที่ `devguard` นำแนวคิดและเครื่องมือมาใช้ พร้อมระบุ **สิ่งที่ดึงมาแล้ว**, **สิ่งที่ตั้งใจคัดออก (เพื่อไม่ให้เผลอนำกลับมาซ้ำ)**, **วิธีเช็คเวอร์ชันใหม่**, และ **เกณฑ์คัดกรอง 4 ข้อ** ก่อนเพิ่มสิ่งใหม่เข้าสู่ระบบ

---

## 1. เครื่องมือที่ติดตั้งในระบบ (Active Components Radar)

ควรตรวจเช็คทุก **2–3 เดือน** หรือเมื่อพบปัญหากับภาษา/IDE เวอร์ชันใหม่

| เครื่องมือ | เวอร์ชันที่ Pin ปัจจุบัน | ไฟล์ที่กำหนด | ต้นทาง (GitHub / Package) | เมื่อไหร่ควรอัปเดต |
|---|---|---|---|---|
| **CodeGraph** | `1.6.2` | `components/codegraph.sh` | https://github.com/colbymchenry/codegraph (`@colbymchenry/codegraph` บน npm) | เมื่อมีการปรับปรุง parser ของ Swift / ObjC หรือรองรับ Agent ตัวใหม่ |
| **ProjectMem** | `0.3.4` | `components/projectmem.sh` | https://github.com/riponcm/projectmem (`projectmem` บน PyPI) | เมื่อมีการปรับปรุง MCP schema หรือแก้บั๊กฐานข้อมูล SQLite |
| **RTK** | ตาม Homebrew (`1.1.0+`) | `components/rtk.sh` | https://github.com/rtk-ai/rtk (`rtk` บน Homebrew) | เมื่อมีการเพิ่ม filter สำหรับคำสั่งใหม่ (เช่น `xcodebuild`, `swift`) หรือรองรับ global hook ของ Antigravity โดยตรง |
| **Context-Mode** | `1.0.169` | `components/context-mode.sh` | https://github.com/mksglu/context-mode (`context-mode` บน npm) | เมื่อเปิดใช้งาน `context-mode` และต้องการอัปเดต sandbox |
| **xcbeautify** | ตาม Homebrew (`3.2.1+`) | `bootstrap.sh`, `bin/devguard` | https://github.com/cpisciotta/xcbeautify (`xcbeautify` บน Homebrew) | เมื่อ Xcode ออกเวอร์ชันใหญ่และเปลี่ยนรูปแบบ build/test log |
| **ast-grep** | ตาม Homebrew (`0.51.0+`) | `bootstrap.sh`, `bin/devguard` | https://github.com/ast-grep/ast-grep (`ast-grep` บน Homebrew) | เมื่อต้องการอัปเดต tree-sitter grammar สำหรับ Swift / TypeScript |

### คำสั่งเช็คเวอร์ชันล่าสุดจากต้นทางเทียบกับที่ใช้อยู่ (รันใน Terminal ได้ทันที)
```sh
printf "%-15s %-12s %-12s\n" "Component" "Installed" "Latest Upstream"
printf "%-15s %-12s %-12s\n" "codegraph" "$(codegraph --version 2>/dev/null || echo -)" "$(npm view @colbymchenry/codegraph version 2>/dev/null || echo -)"
printf "%-15s %-12s %-12s\n" "projectmem" "$(~/.local/share/agent-kit/projectmem-venv/bin/python -c 'import importlib.metadata as m; print(m.version("projectmem"))' 2>/dev/null || echo -)" "$(curl -fsSL https://pypi.org/pypi/projectmem/json 2>/dev/null | jq -r .info.version || echo -)"
printf "%-15s %-12s %-12s\n" "rtk" "$(rtk --version 2>/dev/null | awk '{print $2}' || echo -)" "$(brew info --json=v2 rtk 2>/dev/null | jq -r '.formulae[0].versions.stable' || echo -)"
printf "%-15s %-12s %-12s\n" "context-mode" "$(npm ls -g context-mode --depth=0 2>/dev/null | sed -n 's/.*context-mode@\([0-9.]*\).*/\1/p')" "$(npm view context-mode version 2>/dev/null || echo -)"
printf "%-15s %-12s %-12s\n" "xcbeautify" "$(xcbeautify --version 2>/dev/null || echo -)" "$(brew info --json=v2 xcbeautify 2>/dev/null | jq -r '.formulae[0].versions.stable' || echo -)"
printf "%-15s %-12s %-12s\n" "ast-grep" "$(ast-grep --version 2>/dev/null | awk '{print $2}' || echo -)" "$(brew info --json=v2 ast-grep 2>/dev/null | jq -r '.formulae[0].versions.stable' || echo -)"
```
*(หากต้องการอัปเกรด: แก้เลขเวอร์ชันใน `components/<ชื่อ>.sh` แล้วรัน `devguard update` หรือ `devguard doctor --fix`)*

---

## 2. ต้นแบบวิธีคิดและ Workflow (Methodology & Prompt Sources Radar)

ควรตรวจเช็คทุก **3–6 เดือน** หรือเมื่อมีโมเดลรุ่นใหม่ (เช่น Claude / Gemini รุ่นถัดไป) ออกมาแล้วพฤติกรรมเปลี่ยน

| แหล่งต้นทาง | URL อ้างอิง | สิ่งที่ดึงมาอยู่ใน `verified-dev` / `core.md` แล้ว | สิ่งที่ตั้งใจ **ไม่เอามา** (ห้ามนำกลับมา) | จุดที่ควรส่องเมื่อตรวจอัปเดต |
|---|---|---|---|---|
| **1. `pstack` (`poteto-mode`)** โดย Lauren Tan | https://github.com/cursor/plugins/tree/main/pstack (`skills/poteto-mode/SKILL.md`) | - Playbooks 6 ประเภท (`Investigation`, `Bug fix`, `Feature`, `Refactor`, `Perf`, `Prompt/LLM`)<br>- กฎ Read-only เมื่อถามคำถาม/คุยทางเลือก (`should we do X or Y`)<br>- การทวนเป้าหมายและสมมติฐาน 1 ประโยคตอนเริ่มงาน<br>- `Attack the premise`, `Explain the number`, `Terse is not an excuse to drop content` | - คำสั่งเฉพาะของทีมภายในที่ผูกกับ Cursor เพียงตัวเดียว | ดู commit ใหม่ใน `skills/poteto-mode/SKILL.md` ว่ามี Playbook ใหม่หรือวิธีจัดการ Subagent / Eval ที่ดีขึ้นหรือไม่ |
| **2. `Karpathy Guidelines`** | https://github.com/forrestchang/andrej-karpathy-skills | - `Think Before Coding`: หยุดถามเมื่อตีความได้หลายแบบแทนการเดาเงียบๆ<br>- `Simplicity First`: ห้ามสร้าง abstraction ถ้ายังไม่มีผู้เรียกใช้จุดที่ 2<br>- `Surgical Changes`: ลบโค้ดกำพร้าที่เกิดจากการแก้ของตัวเอง แต่ถ้าเจอ dead code เดิมให้แจ้งโดยไม่แอบแก้ปนใน diff<br>- `Goal-Driven Execution`: แปลงงานเป็นขั้นที่ verify ได้ | - การแยกไฟล์ Skill อีกชุดออกมาต่างหาก (เพราะทำให้ซ้ำซ้อนกับ `verified-dev`) | ดูว่ามีหลักการใหม่สำหรับ Agentic Coding เพิ่มเติมจาก 4 ข้อเดิมหรือไม่ |
| **3. `Ponytail`** โดย Dietrich Gebert | https://github.com/DietrichGebert/ponytail | - **Reuse Ladder**: ใช้ helper ในโปรเจกต์ -> stdlib -> native API ก่อนเขียนใหม่<br>- **Sibling-Caller Check**: เช็คทุก caller (`codegraph_explore` / grep) เมื่อแก้ฟังก์ชันที่ใช้ร่วมกัน<br>- **Adjacent Bugs & Ceilings**: แจ้งบั๊กข้างเคียงและเพดานข้อจำกัดท้ายคำตอบ | - ระบบโหมด 4 ระดับ (`default`, `explain`, `plan`, `off`) และ Hook ที่ฉีดเข้าทุกเทิร์น (เพราะซ้ำซ้อนและเปลือง Input Tokens) | ดูเฉพาะกฎด้านความสะอาดของโค้ดและการป้องกันการแก้ซ้ำหลายรอบใน `skills/ponytail/SKILL.md` |
| **4. `Caveman` & `Cavecrew`** โดย Julius Brussee | - https://github.com/JuliusBrussee/caveman<br>- https://github.com/JuliusBrussee/cavecrew | - สัญญาผลลัพธ์ของ Subagent แบบบรรทัดเดียว (`path:line — symbol — note`)<br>- ฟอร์แมต Code Review กระชับ (`path:line: 🔴 bug \| 🟡 risk \| 🔵 nit \| ❓ q: <problem>. <fix>.`) | - **โหมดภาษามนุษย์ถ้ำ (`caveman-speak`)** ที่กิน Input Tokens เพิ่ม ~1–1.5k ต่อเทิร์นและทำให้คำอธิบายแผนงานห้วนเกินไป<br>- **`caveman-stats`** ที่ใช้ตัวคูณคงที่ `0.65` แทนการวัดจริง | ดูเฉพาะเทคนิคการส่งต่องานระหว่าง Subagents ใน `cavecrew` ที่ช่วยลดการส่ง Context ก้อนใหญ่ |
| **5. `tokless`** | โปรเจกต์ต้นแบบด้านการรวม CLI ประหยัด Token | - แนวคิดเมนู Interactive (`devguard`, `devguard select`, `devguard status`, `devguard stats`)<br>- การผูก `codegraph` + `projectmem` + `rtk` เข้ากับทุก Agent ในคำสั่งเดียว | - **`headroom` proxy (`127.0.0.1:8787`)** เพราะทำให้ Claude Code ต่อเน็ตหลุดเมื่อ proxy ค้าง และไปตัดทอนหลักฐานการทดสอบที่ `verified-dev` ต้องใช้ | ดูว่ามีเครื่องมือ MCP หรือ CLI ใหม่ๆ ที่ช่วยประหยัด Token จากฝั่ง Tool Output โดยไม่ต้องพึ่ง Proxy หรือไม่ |
| **6. ระบบของ Agent แต่ละตัว** (Claude Code, Antigravity, VS Code) | - คู่มือในตัว Antigravity (`agy-customizations`)<br>- Claude Code Changelog | - การผูก `CLAUDE.md`, `GEMINI.md`, `copilot-instructions.md`<br>- การผูก MCP ที่ `~/.claude.json`, `mcp.json`, `~/.gemini/config/mcp_config.json` | - | ดูว่า Antigravity และ VS Code เปิดให้ใช้ Lifecycle Hooks (`SessionStart` / `PreToolUse`) แบบเสถียรหรือยัง เพื่อนำมาเชื่อม `remind.sh` และ `rtk` |

---

## 3. เกณฑ์คัดกรอง 4 ข้อก่อนเพิ่มสิ่งใหม่เข้า `devguard` (Gatekeeper Checklist)

ทุกครั้งที่เจอปลั๊กอิน กฎ หรือเครื่องมือใหม่ ต้องผ่านคำถามทั้ง 4 ข้อนี้ก่อนเสมอ:

1. **คุ้มค่า Token สุทธิจริงไหม (Net Token Positive)?**
   - กฎใน `rules/core.md` ถูกโหลดทุกเทิร์น จึงต้องสั้นที่สุด (ไม่เกิน 8–10 บรรทัดรวมกัน)
   - ห้ามลงปลั๊กอินที่ฉีด System Prompt ยาวหลายร้อยบรรทัดทุกเทิร์นเพื่อหวังลดคำตอบเพียงไม่กี่คำ ถ้าแนวคิดดี ให้สกัดเฉพาะแก่น 1–2 ประโยคใส่ใน `skills/verified-dev/SKILL.md` แทน
2. **เพิ่มภาระการคิดที่ไม่จำเป็นให้โมเดลไหม (Zero Unnecessary Cognitive Overhead)?**
   - กฎต้องช่วยลดความผิดพลาดจริง (เช่น ห้ามแก้โค้ดตอนถามคำถาม, เช็ค sibling callers, ยืนยันด้วย `agent-verify`) ไม่ใช่บังคับรูปแบบการพูดที่ฝืนธรรมชาติของโมเดล
3. **วัดผลได้จริงไหม (Explain the Number)?**
   - ห้ามเชื่อตัวเลขประหยัด Token ที่มาจากการคูณเปอร์เซ็นต์คงที่ ต้องวัดจากขนาด Output จริง (เช่น `rtk gain` หรือขนาดไฟล์ log จริง)
4. **ไม่ทำลายหลักฐานการตรวจสอบใช่ไหม (Evidence Integrity)?**
   - ห้ามใช้เครื่องมือที่ตัดทอนหรือซ่อนผลลัพธ์ของ `agent-verify` (`.verify/<name>.log`)

---

## 4. คำสั่งลัดสำหรับให้ AI ช่วยตรวจสอบอัปเดตในอนาคต

เมื่อต้องการตรวจสอบในอนาคต สามารถคัดลอกข้อความด้านล่างนี้สั่ง Agent ได้ทันที:

> **"ช่วยอ่านไฟล์ `docs/UPSTREAM-RADAR.md` แล้วรันเช็คเวอร์ชันล่าสุดของ Components ทั้ง 4 ตัว รวมถึงค้นหาว่าต้นทางในตารางที่ 2 มีการอัปเดตอะไรใหม่ที่ผ่านเกณฑ์ Gatekeeper ทั้ง 4 ข้อบ้าง (ให้อยู่ในโหมด Read-only และสรุปเป็นตารางเปรียบเทียบก่อน)"**
