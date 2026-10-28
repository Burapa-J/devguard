# คู่มือใช้งาน agent-kit

agent-kit มี 2 ส่วน
- **วิธีทำงาน**: rules และ skill `verified-dev` ที่บังคับให้ agent ทำงานแบบมีหลักฐาน
- **เครื่องมือ (components)**: ติดตั้งและเชื่อมเข้ากับ Claude Code, VS Code (Copilot) และ Antigravity

ภาพรวมภาษาอังกฤษอยู่ใน `README.md`

---

## 1. ติดตั้งบนเครื่องใหม่

### 1.1 เตรียมเครื่อง (ครั้งเดียว)

```sh
xcode-select --install          # git, python3
brew install gh node jq         # gh: เข้า private repo, node: สำหรับ codegraph
gh auth login                   # ล็อกอินบัญชี Burapa-J
```

- macOS รุ่นใหม่มี `/usr/bin/jq` มาให้แล้ว ถ้ามีอยู่แล้วไม่ต้องลงซ้ำ
- ถ้าเลือกไม่ใช้ codegraph (`--with=projectmem` หรือ `--with=none`) ไม่ต้องลง node
- ถ้าเครื่องนั้นมี tokless อยู่ ให้ถอดออกก่อนด้วย `tokless uninstall`

### 1.2 Clone และติดตั้ง

ปิด Claude Code, VS Code และ Antigravity ก่อน เพราะโปรแกรมเหล่านี้เขียน config ของตัวเองทับได้ระหว่างที่เปิดอยู่

```sh
gh repo clone Burapa-J/A69-012-agent-kit ~/Developer/"A69-012 agent-kit"
cd ~/Developer/"A69-012 agent-kit"

/bin/bash tests/test-kit.sh | tail -1          # ทดสอบใน HOME จำลอง ไม่แตะเครื่องจริง
/bin/bash tests/test-components.sh | tail -1

./install.sh --dry-run --with-hooks            # ดูว่าจะแก้อะไรบ้าง
./install.sh --with-hooks                      # ติดตั้งจริง
./status.sh                                    # ตรวจผล
```

ถ้ามีคำเตือนว่า `~/.local/bin is not on PATH` ให้เพิ่มบรรทัดนี้ใน `~/.zshrc` แล้วเปิด Terminal ใหม่:
```sh
export PATH="$HOME/.local/bin:$PATH"
```

### 1.3 ตัวเลือกตอนติดตั้ง

| คำสั่ง | ผล |
|---|---|
| `./install.sh --with-hooks` | วิธีทำงาน + codegraph + projectmem + hook เตือนให้โหลด skill ใหม่หลัง compact (ค่าที่แนะนำ) |
| `./install.sh --with=none` | เฉพาะวิธีทำงาน ไม่ติดตั้งเครื่องมือ |
| `./install.sh --with=codegraph,projectmem,rtk` | เพิ่ม rtk (ย่อ output ของ shell) |
| `./install.sh --with=codegraph,projectmem,context-mode` | เพิ่ม context-mode (ต้องใช้ Node ≥ 22.5) |
| `./install.sh --targets=claude` | ติดตั้งเฉพาะบาง agent: `claude`, `vscode`, `antigravity` |
| `./install.sh --with-hooks --auto-project=~/Developer` | ตั้งค่าโปรเจกต์ภายใต้ `~/Developer` ให้อัตโนมัติ (ดูข้อ 2.1) |
| `./install.sh --dry-run ...` | แสดงสิ่งที่จะเปลี่ยน โดยไม่แก้อะไรจริง |

รันซ้ำได้ทุกเมื่อ ส่วนที่ติดตั้งแล้วจะไม่ถูกทำซ้ำ และไฟล์ที่ถูกแก้จะ backup ไว้ที่ `~/.agent-kit-backup/<เวลา>/`

---

## 2. ตั้งค่าแต่ละโปรเจกต์

แต่ละ repo ต้องตั้งค่าครั้งเดียว ได้แก่
- เพิ่ม `.verify/` ลง `.gitignore`
- สร้าง index ของ codegraph ที่ `.codegraph/` ซึ่งอัปเดตตัวเองอัตโนมัติหลังจากนั้น
- เริ่มต้น projectmem ที่ `.projectmem/` พร้อมติดตั้ง git hooks และเพิ่มส่วน "projectmem bridge" ใน `CLAUDE.md` และ `AGENTS.md` ของโปรเจกต์

### 2.1 แบบอัตโนมัติ (แนะนำ)

ติดตั้งพร้อมบอกว่าโปรเจกต์ของคุณอยู่ในโฟลเดอร์ไหน:
```sh
./install.sh --with-hooks --auto-project=~/Developer
agent-kit-project init-all ~/Developer     # ตั้งค่า repo ที่มีอยู่แล้วทั้งหมดครั้งเดียว
```

- **repo ใหม่** ภายใต้ `~/Developer` จะถูกตั้งค่าเองเมื่อเปิดด้วย Claude Code ครั้งแรก โดยทำงานเบื้องหลังและไม่ทำให้ session ช้า
- agent จะเห็นข้อความแจ้ง 1 บรรทัด และ log อยู่ที่ `~/.agent-kit/logs/<ชื่อ repo>.log`
- repo ที่ตั้งค่าแล้วจะข้ามทันที ไม่เสีย token
- **repo นอกโฟลเดอร์ที่กำหนดจะไม่ถูกแตะ** เช่น repo ของคนอื่นที่ clone มาดู
- ถ้าต้องการยกเว้น repo ใดภายใต้ `~/Developer` ให้สร้างไฟล์ว่าง `.agent-kit-skip` ที่ root ของ repo นั้น
- กำหนดหลายโฟลเดอร์ได้ด้วยเครื่องหมายจุลภาค: `--auto-project=~/Developer,~/Work`
- `init-all` ตั้งค่า repo ที่อยู่ลึก 1–2 ชั้น เช่น `~/Developer/app` และ `~/Developer/group/lib`

**ข้อจำกัด**: การตั้งค่าเองเมื่อเปิด repo ใช้ hook ของ Claude Code จึงทำงานเฉพาะใน Claude Code ถ้าเปิด repo ใหม่ด้วย VS Code หรือ Antigravity เท่านั้น ให้รัน `agent-kit-project init` เอง หรือรัน `init-all` ซ้ำเป็นระยะ

### 2.2 แบบสั่งเอง

```sh
cd <โฟลเดอร์โปรเจกต์>
agent-kit-project init            # ดูก่อนด้วย --dry-run
```

## 3. ใช้งานประจำวัน

### เริ่มงานโค้ด
- พิมพ์ `/verified-dev` ตอนเริ่มงาน เพื่อให้ agent โหลด skill แน่นอนโดยไม่ต้องรอให้มันจับคู่เอง
- เรียกซ้ำเมื่อเริ่มงานใหม่ หรือเมื่อ agent ดูเหมือนลืมขั้นตอน
- ถ้าติดตั้งแบบ `--with-hooks` Claude Code จะเตือนให้โหลดใหม่หลัง compact ให้เอง

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

## 4. อัปเดต

```sh
cd ~/Developer/"A69-012 agent-kit"
git pull --ff-only
./install.sh --with-hooks      # รันซ้ำเมื่อ version ของ component เปลี่ยน หรือมีไฟล์ใหม่
./status.sh
```

skill และ rules เป็น symlink การแก้ใน repo จึงมีผลกับทุก agent ทันทีหลัง `git pull` (เปิด session ใหม่เพื่อให้ agent โหลดเวอร์ชันใหม่)

**อย่าย้ายหรือลบโฟลเดอร์ repo** เพราะลิงก์ทั้งหมดชี้มาที่นี่ ถ้าจำเป็นต้องย้าย ให้รัน `./install.sh --with-hooks` ใหม่จากตำแหน่งใหม่

---

## 5. ตรวจสถานะ

```sh
./status.sh
```
- ส่วน **Core** ทุกบรรทัดควรเป็น `ok`
- ส่วน **Components** ตัวที่เลือกไว้ควรเป็น `CLI installed, managed by agent-kit` และ `wired` ในทุก agent

ทดสอบกับ agent จริงในแต่ละโปรแกรม:
1. เปิด session ใหม่แล้วถามว่า "What rules are you following for code tasks?" คำตอบควรพูดถึง `verified-dev` และเรื่องหลักฐาน
2. สั่งแก้ bug ที่มี test fail อยู่ คำตอบควรมี path ของ log จาก `agent-verify`, exit code ก่อนและหลังแก้ และบรรทัดที่ fail กับ pass

---

## 6. ถอนการติดตั้ง

```sh
./uninstall.sh --dry-run     # ดูก่อน
./uninstall.sh               # ถอด rules, skill, hook และการเชื่อมเครื่องมือ แต่เก็บ CLI ไว้
./uninstall.sh --purge       # ลบ CLI ที่ agent-kit ติดตั้งเองด้วย
```

- `--purge` จะไม่ลบ CLI ที่คุณติดตั้งเองก่อนหน้า
- การตั้งค่าอัตโนมัติ (hook, `~/.agent-kit/auto-roots`, logs) ถูกถอดออกด้วย
- ข้อมูลของเครื่องมือจะไม่ถูกลบ: `~/.codegraph/`, `~/.projectmem/` และ `.codegraph/` / `.projectmem/` ในแต่ละโปรเจกต์
- ถ้าต้องการลบรายโปรเจกต์: `codegraph uninit` และ `pjm hooks uninstall` แล้วลบโฟลเดอร์ `.projectmem/`

---

## 7. แก้ปัญหา

| อาการ | วิธีแก้ |
|---|---|
| `agent-verify: command not found` | เพิ่ม `~/.local/bin` ใน PATH (ข้อ 1.2) แล้วเปิด Terminal ใหม่ |
| agent ไม่พูดถึง verified-dev | พิมพ์ `/verified-dev` เอง และตรวจ `./status.sh` ว่า skill link เป็น `ok` |
| คำตอบไม่มีหลักฐาน | มี rule จากที่อื่นชนะอยู่ (เช่น caveman หรือ rtk) ให้ตรวจ `~/.claude/CLAUDE.md` ว่ามี block อื่นที่สั่งให้ตอบสั้นหรือไม่ ดูหัวข้อ 9 ของ skill |
| `warning: ... already exists and is not managed by agent-kit; skipped` | มีไฟล์หรือโฟลเดอร์ชื่อเดียวกันอยู่ก่อน agent-kit จึงไม่เขียนทับ ให้ย้ายของเดิมออกแล้วรัน install ใหม่ |
| `tokless is installed` | รัน `tokless uninstall` เพื่อไม่ให้เครื่องมือถูกเชื่อมซ้ำ |
| VS Code ไม่เห็น MCP server | เปิด VS Code ใหม่ ตรวจ `~/Library/Application Support/Code/User/mcp.json` |
| repo ใหม่ไม่ถูกตั้งค่าอัตโนมัติ | ตรวจ `./status.sh` ว่า `auto project setup hook` เป็น `ok` และ repo อยู่ภายใต้ root ที่แสดง ดู log ที่ `~/.agent-kit/logs/` และตรวจว่าไม่มี `.agent-kit-skip` |
| ต้องการย้อนกลับไฟล์ใดไฟล์หนึ่ง | คัดลอกจาก `~/.agent-kit-backup/<เวลา>/` กลับไปที่เดิม |

---

## 8. แก้ไขหรือเพิ่มเติม

- **ปรับวิธีทำงาน**: แก้ `skills/verified-dev/SKILL.md` แล้ว commit และ push
- **ปรับกฎที่ทำงานตลอดเวลา**: แก้ `rules/core.md` ควรเก็บให้สั้น เพราะกิน token ทุก prompt แล้วรัน `./install.sh` ใหม่
- **เพิ่มเครื่องมือ**: คัดลอก `components/context-mode.sh` แล้วแก้ฟังก์ชันให้ครบ เพิ่มชื่อใน `ALL_COMPONENTS` ใน `components/common.sh` และเพิ่ม test
- **ก่อน push ทุกครั้ง**: `/bin/bash tests/test-kit.sh && /bin/bash tests/test-components.sh`
