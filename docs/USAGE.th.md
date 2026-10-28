# คู่มือใช้งาน agent-kit

agent-kit มี 2 ส่วน
- **วิธีทำงาน**: rules และ skill `verified-dev` ที่บังคับให้ agent ทำงานแบบมีหลักฐาน
- **เครื่องมือ (components)**: codegraph และ projectmem (เปิดเป็นค่าเริ่มต้น) รวมถึง rtk และ context-mode (เลือกเปิดเอง) ติดตั้งและเชื่อมเข้ากับ Claude Code, VS Code (Copilot) และ Antigravity

ติดตั้งคำสั่งเดียว แล้วทุกอย่างทำงานเองแบบ tokless ภาพรวมภาษาอังกฤษอยู่ใน `README.md`

---

## 1. ติดตั้ง

### 1.1 เครื่องใหม่: คำสั่งเดียว

ปิด Claude Code, VS Code และ Antigravity ก่อน แล้วรัน:
```sh
brew install gh && gh auth login        # ครั้งแรกเท่านั้น: ล็อกอินบัญชี Burapa-J (repo เป็น private)
gh api -H 'Accept: application/vnd.github.raw' repos/Burapa-J/A69-012-agent-kit/contents/bootstrap.sh | bash
```

คำสั่งนี้จะ
- ติดตั้งสิ่งที่ขาดผ่าน Homebrew (git, jq, python3, node)
- clone kit ไปไว้ที่ `~/.local/share/agent-kit/src` หรือใช้ที่เดิมถ้าเคยติดตั้งแล้ว
- ติดตั้ง rules, skill, hook, codegraph และ projectmem
- เปิดการตั้งค่าโปรเจกต์อัตโนมัติใน `~/Developer`
- เพิ่ม `~/.local/bin` ใน PATH

จากนั้นเปิด Terminal ใหม่ เปิด agent ใหม่ แล้วรัน `agent-kit status`

ถ้าเครื่องนั้นมี tokless อยู่ ให้รัน `tokless uninstall` ก่อน

### 1.2 เครื่องที่ clone repo ไว้แล้ว

```sh
cd <โฟลเดอร์ repo> && git pull --ff-only && ./install.sh && agent-kit status
```

### 1.3 ตัวเลือก (ไม่ใส่ก็ได้ ค่าเริ่มต้นคือแบบที่แนะนำ)

ใส่ต่อท้าย `./install.sh` หรือ `agent-kit install` หรือต่อท้าย bootstrap ด้วย `| bash -s -- <ตัวเลือก>`

| ตัวเลือก | ผล |
|---|---|
| (ไม่ใส่) | วิธีทำงาน + codegraph + projectmem + hook + ตั้งค่าโปรเจกต์อัตโนมัติใน `~/Developer` |
| `--with=codegraph,projectmem,rtk` | เพิ่ม rtk (ย่อ output ของ shell) |
| `--with=codegraph,projectmem,context-mode` | เพิ่ม context-mode (ต้องใช้ Node ≥ 22.5) |
| `--with=none` | เฉพาะวิธีทำงาน ไม่ติดตั้งเครื่องมือ |
| `--auto-project=~/Developer,~/Work` | กำหนดโฟลเดอร์ที่ตั้งค่าโปรเจกต์อัตโนมัติ |
| `--auto-project=none` | ปิดการตั้งค่าอัตโนมัติ |
| `--targets=claude` | ติดตั้งเฉพาะบาง agent: `claude`, `vscode`, `antigravity` |
| `--no-hooks` | ไม่ใส่ hook เตือนให้โหลด skill ใหม่หลัง compact |
| `--dry-run` | แสดงสิ่งที่จะเปลี่ยน โดยไม่แก้อะไรจริง |

- รันซ้ำได้ทุกเมื่อ ส่วนที่ติดตั้งแล้วจะไม่ถูกทำซ้ำ และระบบจำโฟลเดอร์อัตโนมัติเดิมไว้
- ไฟล์ที่ถูกแก้จะ backup ไว้ที่ `~/.agent-kit-backup/<เวลา>/`

---

## 2. โปรเจกต์ถูกตั้งค่าเอง

ทุก git repo ภายใต้ `~/Developer` (ลึก 1–2 ชั้น เช่น `~/Developer/app` และ `~/Developer/group/lib`) จะถูกตั้งค่าครั้งเดียวโดยอัตโนมัติ
- เพิ่ม `.verify/` ลง `.gitignore`
- สร้าง index ของ codegraph ที่ `.codegraph/` ซึ่งอัปเดตตัวเองหลังจากนั้น
- เริ่มต้น projectmem ที่ `.projectmem/` พร้อม git hooks และส่วน "projectmem bridge" ใน `CLAUDE.md` / `AGENTS.md` ของโปรเจกต์

**มี 3 ทางที่จะทำให้เกิดการตั้งค่า ครอบคลุมทุก agent**

| เกิดเมื่อ | ทำงานกับ |
|---|---|
| เปิด session ใน Claude Code | Claude Code |
| `cd` เข้า repo ใน zsh (รวม terminal ใน VS Code และ Antigravity) | ทุกตัว |
| launchd สแกนทุก 30 นาที และตอน login | ทุกตัว รวมถึง repo ที่ clone ผ่าน GUI |

- ทำงานเบื้องหลัง ไม่ทำให้ session ช้า และ repo ที่ตั้งค่าแล้วจะถูกข้ามทันที
- log อยู่ที่ `~/.agent-kit/logs/`
- repo นอกโฟลเดอร์ที่กำหนดจะไม่ถูกแตะ
- ตัว agent-kit เองมีไฟล์ `.agent-kit-skip` จึงไม่ถูกตั้งค่า

**คำสั่งที่เกี่ยวข้อง**
```sh
agent-kit init --all     # ตั้งค่า repo ที่มีอยู่แล้วทั้งหมดทันที ไม่ต้องรอสแกน
agent-kit init           # ตั้งค่า repo ที่อยู่ตอนนี้ (ใช้กับ repo นอก ~/Developer ได้)
agent-kit skip           # ยกเว้น repo ที่อยู่ตอนนี้จากการตั้งค่าอัตโนมัติ
```

---

## 3. ใช้งานประจำวัน

### เริ่มงานโค้ด
- พิมพ์ `/verified-dev` ตอนเริ่มงาน เพื่อให้ agent โหลด skill แน่นอน
- เรียกซ้ำเมื่อเริ่มงานใหม่ หรือเมื่อ agent ดูเหมือนลืมขั้นตอน
- Claude Code จะเตือนให้โหลดใหม่หลัง compact ให้เอง

### สิ่งที่ควรเห็นในคำตอบของ agent
- เลือก playbook (Bug fix, Feature, Refactor ฯลฯ) และมี task list ที่คัดลอกขั้นตอนมาครบ
- ขั้นที่ข้ามต้องมี `skip: <เหตุผล>`
- คำว่า "เสร็จ" ต้องมาพร้อมหลักฐาน: คำสั่ง, exit code และบรรทัดที่ fail หรือ pass
- ถ้ายังไม่ได้ verify ต้องบอกตรง ๆ

### เก็บหลักฐานด้วย agent-verify
agent จะเรียกเองตามกฎ แต่คุณใช้เองได้ด้วย:
```sh
agent-verify unit-tests -- xcodebuild test -scheme MyApp -destination 'platform=macOS'
agent-verify build -- swift build
```
ผลเต็มอยู่ที่ `.verify/<ชื่อ>.log` พร้อม exit code และคำสั่งจะคืน exit code เดียวกับคำสั่งที่รัน

### คำสั่งที่ใช้กับ agent ได้
| พิมพ์ | ผล |
|---|---|
| `new task` | ให้ agent เลือก playbook ใหม่ |
| `don't change code yet` | บังคับให้อยู่ใน Investigation (อ่านอย่างเดียว) |

---

## 4. คำสั่ง agent-kit

| คำสั่ง | ผล |
|---|---|
| `agent-kit status` | ดูสิ่งที่ติดตั้ง, wire และตั้งค่าอัตโนมัติ |
| `agent-kit update` | ดึงเวอร์ชันล่าสุดแล้วติดตั้งซ้ำ โดยคงการตั้งค่าเดิม |
| `agent-kit init` / `init --all` | ตั้งค่า repo นี้ หรือทุก repo ในโฟลเดอร์อัตโนมัติ |
| `agent-kit skip` | ยกเว้น repo นี้ |
| `agent-kit install [ตัวเลือก]` | เปลี่ยนการตั้งค่า (ดูข้อ 1.3) |
| `agent-kit uninstall [--purge]` | ถอนการติดตั้ง (ดูข้อ 6) |
| `agent-kit docs` | แสดงที่อยู่ของคู่มือ |

**อย่าย้ายหรือลบโฟลเดอร์ kit** เพราะลิงก์ทั้งหมดชี้มาที่นี่ ถ้าจำเป็นต้องย้าย ให้รัน `./install.sh` ใหม่จากตำแหน่งใหม่

---

## 5. ตรวจสถานะ

```sh
agent-kit status
```
- ส่วน **Core** ทุกบรรทัดควรเป็น `ok` ได้แก่ rules, skill, คำสั่ง, hook และการตั้งค่าอัตโนมัติทั้ง Claude Code, zsh และ launchd
- ส่วน **Components** ตัวที่เลือกไว้ควรเป็น `CLI installed, managed by agent-kit` และ `wired` ในทุก agent

ทดสอบกับ agent จริงในแต่ละโปรแกรม:
1. เปิด session ใหม่แล้วถามว่า "What rules are you following for code tasks?" คำตอบควรพูดถึง `verified-dev` และเรื่องหลักฐาน
2. สั่งแก้ bug ที่มี test fail อยู่ คำตอบควรมี path ของ log จาก `agent-verify`, exit code ก่อนและหลังแก้ และบรรทัดที่ fail กับ pass

---

## 6. ถอนการติดตั้ง

```sh
agent-kit uninstall --dry-run     # ดูก่อน
agent-kit uninstall               # ถอดทุกอย่างที่เพิ่มไว้ แต่เก็บ CLI ของเครื่องมือไว้
agent-kit uninstall --purge       # ลบ CLI ที่ agent-kit ติดตั้งเองด้วย
```

- ถอดออกครบ: rules, skill, คำสั่ง, hook ทั้งหมด, บล็อกใน `~/.zshrc`, launchd agent และการเชื่อมเครื่องมือใน MCP config
- `--purge` จะไม่ลบ CLI ที่คุณติดตั้งเองก่อนหน้า
- **สิ่งที่ไม่ถูกลบ**:
  - ข้อมูลของเครื่องมือ: `~/.codegraph/`, `~/.projectmem/` และ `.codegraph/` / `.projectmem/` ในแต่ละโปรเจกต์ ถ้าต้องการลบรายโปรเจกต์ใช้ `codegraph uninit` และ `pjm hooks uninstall` แล้วลบ `.projectmem/`
  - บรรทัด PATH ที่ bootstrap เพิ่มใน `~/.zshrc`

---

## 7. แก้ปัญหา

| อาการ | วิธีแก้ |
|---|---|
| `agent-kit: command not found` | เปิด Terminal ใหม่ ถ้ายังไม่ได้ ให้เพิ่ม `export PATH="$HOME/.local/bin:$PATH"` ใน `~/.zshrc` |
| agent ไม่พูดถึง verified-dev | พิมพ์ `/verified-dev` เอง และตรวจ `agent-kit status` ว่า skill link เป็น `ok` |
| คำตอบไม่มีหลักฐาน | มี rule จากที่อื่นชนะอยู่ (เช่น caveman หรือ rtk) ให้ตรวจ `~/.claude/CLAUDE.md` ว่ามี block อื่นที่สั่งให้ตอบสั้นหรือไม่ ดูหัวข้อ 9 ของ skill |
| `warning: ... already exists and is not managed by agent-kit; skipped` | มีไฟล์หรือโฟลเดอร์ชื่อเดียวกันอยู่ก่อน agent-kit จึงไม่เขียนทับ ให้ย้ายของเดิมออกแล้วรัน install ใหม่ |
| `tokless is installed` | รัน `tokless uninstall` เพื่อไม่ให้เครื่องมือถูกเชื่อมซ้ำ |
| VS Code ไม่เห็น MCP server | เปิด VS Code ใหม่ ตรวจ `~/Library/Application Support/Code/User/mcp.json` |
| repo ใหม่ไม่ถูกตั้งค่าอัตโนมัติ | ตรวจ `agent-kit status` ว่าบรรทัด auto setup เป็น `ok` และ repo อยู่ภายใต้ root ที่แสดง ดู `~/.agent-kit/logs/scan.log` ตรวจว่าไม่มี `.agent-kit-skip` หรือรัน `agent-kit init` เอง |
| ต้องการย้อนกลับไฟล์ใดไฟล์หนึ่ง | คัดลอกจาก `~/.agent-kit-backup/<เวลา>/` กลับไปที่เดิม |

---

## 8. แก้ไขหรือเพิ่มเติม

- **ปรับวิธีทำงาน**: แก้ `skills/verified-dev/SKILL.md` แล้ว commit และ push จากนั้นเครื่องอื่นรัน `agent-kit update`
- **ปรับกฎที่ทำงานตลอดเวลา**: แก้ `rules/core.md` ควรเก็บให้สั้น เพราะกิน token ทุก prompt
- **เพิ่มเครื่องมือ**: คัดลอก `components/context-mode.sh` แล้วแก้ฟังก์ชันให้ครบ เพิ่มชื่อใน `ALL_COMPONENTS` ใน `components/common.sh` และเพิ่ม test
- **ก่อน push ทุกครั้ง**: `/bin/bash tests/test-kit.sh && /bin/bash tests/test-components.sh`
