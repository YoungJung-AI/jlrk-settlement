# 봇 2개 되살리기 — 복구 매뉴얼

두 봇 모두 **맥미니에서 돌아가는 Claude Code 세션**이다. 각각:

| 봇 | 채널에서 보이는 이름 | 작업폴더 | Discord 설정폴더 | 실행 alias |
|---|---|---|---|---|
| ① 정산/CC 봇 | Client Care & Digital Analyst | `~/Desktop/jlrk-settlement` | `~/.claude/channels/discord` (기본) | `jlrk` |
| ② 비서(PA) 봇 | (새 봇 이름) | `~/pa` | `~/.claude/channels/discord-pa` | `pa` |

**핵심 규칙 3개**
1. 각 봇 = Claude Code 세션 1개. 세션이 죽으면 봇이 오프라인.
2. 실행할 때 **`--channels plugin:discord@claude-plugins-official` 반드시** 포함 (`jlrk`/`pa` alias에 이미 들어있음). 이거 빠지면 Discord 메시지가 조용히 무시됨.
3. 한 봇당 세션은 **1개만**. 유령 프로세스 있으면 먼저 정리.

---

## 상황 A — 터미널만 꺼졌고 `screen` 세션은 살아있는 경우 (가장 흔함)

`screen` 안에서 돌리고 있었다면, 터미널/SSH가 끊겨도 `screen` 세션과 그 안의 Claude Code는 **계속 살아있다**. 그냥 다시 붙으면 됨.

```
# 맥미니 터미널(또는 Termius로 접속) 후:
screen -ls                 # 'main' 세션이 (Detached) 로 보이는지 확인
screen -DR main            # 재접속  (= alias 'work')
```

붙으면 창 전환으로 각 봇 확인:
- `Ctrl-a` 누르고 `"` → 창 목록
- `Ctrl-a` `n` / `p` → 다음/이전 창
- 각 창에 Claude Code 프롬프트가 그대로 있으면 정상. 봇도 온라인 유지 중.

**둘 중 하나만 죽어 있으면** → 그 창으로 가서 아래 "상황 B" 진행.

---

## 상황 B — 봇 세션이 죽었을 때 (한 개 또는 둘 다)

### 1. 유령 프로세스 확인·정리
```
ps ax | grep '[c]laude --channels'
```
- 각 봇당 프로세스가 **정확히 1개**여야 함.
- 죽었는데 프로세스가 남아있거나, 2개 이상이면 그 PID 종료:
```
kill <PID>          # 안 죽으면 kill -9 <PID>
```

### 2. 되살리기 — `screen` 안에서 (권장)
```
screen -DR main             # 세션 없으면 자동 생성
```
screen 안에서:

**① 정산/CC 봇 창:**
```
source ~/.zshrc
jlrk --continue            # 직전 대화 이어서. 새로 시작하려면 그냥 'jlrk'
```

**② 비서(PA) 봇 창** — `Ctrl-a` `c` 로 새 창 만든 뒤:
```
source ~/.zshrc
pa --continue             # 직전 대화 이어서. 새로 시작하려면 그냥 'pa'
```

> `jlrk` = `cd ~/Desktop/jlrk-settlement && claude --channels plugin:discord@claude-plugins-official`
> `pa`   = `cd ~/pa && DISCORD_STATE_DIR="$HOME/.claude/channels/discord-pa" claude --channels plugin:discord@claude-plugins-official`
> 뒤에 `--continue` 붙이면 그 폴더의 **마지막 대화**를 이어감. `-r` 붙이면 대화 목록에서 고름.

### 3. Discord 연결 확인
각 봇 세션에서, 또는 다른 터미널에서:
```
# ① 정산봇
ls -t ~/Library/Caches/claude-cli-nodejs/-Users-youngjung-Desktop-jlrk-settlement/mcp-logs-plugin-discord-discord/*.jsonl | head -1 | xargs grep -o 'Channel notifications [a-z]*' | tail -1
# ② PA봇
ls -t ~/Library/Caches/claude-cli-nodejs/-Users-youngjung-pa/mcp-logs-plugin-discord-discord/*.jsonl | head -1 | xargs grep -o 'Channel notifications [a-z]*' | tail -1
```
- `Channel notifications registered` → 정상 연결
- `Channel notifications skipped` → `--channels` 빠졌음. 세션 종료하고 alias로 다시.

### 4. 최종 확인
채널에서 각 봇을 @멘션해서 "핑" → 각 세션(각 창)에 메시지 들어오면 복구 완료.

---

## 상황 C — 맥미니 재부팅 후 (콜드 스타트)

재부팅되면 SSH 서버·Tailscale은 자동 복구되지만(`autorestart 1`, Tailscale 'Launch at login'), **`screen` 세션과 봇 세션은 안 살아난다.** 처음부터:

```
# 1. (원격이면) Termius로 접속
# 2. screen 시작
screen -S main
# 3. 정산봇
source ~/.zshrc && jlrk
# 4. Ctrl-a c 로 새 창 → PA봇
source ~/.zshrc && pa
# 5. Ctrl-a d 로 detach (봇들은 계속 돎)
```

이후엔 상황 A대로 `screen -DR main` 으로 재접속.

---

## 빠른 참조

| 하고 싶은 것 | 명령 |
|---|---|
| screen 재접속 | `screen -DR main` (= `work`) |
| screen 새 창 | `Ctrl-a` `c` |
| 창 이동 / 목록 | `Ctrl-a` `n`·`p` / `Ctrl-a` `"` |
| screen 나가기(봇 유지) | `Ctrl-a` `d` |
| 정산봇 켜기 | `jlrk` (이어서: `jlrk --continue`) |
| PA봇 켜기 | `pa` (이어서: `pa --continue`) |
| 돌아가는 세션 보기 | `ps ax \| grep '[c]laude --channels'` |
| 세션 죽이기 | `kill <PID>` |
