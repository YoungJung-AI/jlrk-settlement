// Supabase Edge Function: send-email (Gmail SMTP 직접 구현)
// 역할: 브라우저에서 { to, subject, html } 요청을 받아 Gmail SMTP(465, implicit TLS)로
//       메일을 발송한다. GMAIL_USER / GMAIL_APP_PASSWORD 는 서버에서만 사용된다.
//
// ⚠️ denomailer@1.6.0 를 걷어냈다. 그 라이브러리의 인코더가 한글(멀티바이트)을 깨뜨린다:
//    - 제목: =?utf-8?Q?...?= 인코딩드워드를 74자에서 UTF-8 바이트 중간을 잘라 만들고
//            공백/줄바꿈 처리가 틀려서 Gmail 이 디코딩 실패 → 제목이 raw 로 표시됨
//    - 본문: quotedPrintableEncode 가 '=' 재이스케이프 누락 + 라인 폴딩 오류로
//            이중 인코딩(=3d20 흔적) → 본문 전체가 raw 로 표시됨
//    denomailer 는 1.6.0 이 최신이라 버전업으로 해결 불가. 그래서 최소 SMTP 대화를
//    직접 구현하고, 제목은 RFC 2047 base64 인코딩드워드, 본문은 base64 전송 인코딩으로
//    보낸다(둘 다 멀티바이트 안전).

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const enc = new TextEncoder();
const dec = new TextDecoder();

// ---------- 인코딩 헬퍼 ----------

function bytesToB64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

// RFC 2047 base64 encoded-word. 멀티바이트 문자 경계를 지키며 encoded-word 하나가
// 75자를 넘지 않도록 나누고, 넘치면 CRLF+space 로 폴딩한다.
function encodeHeaderWord(input: string): string {
  // 순수 ASCII(제어문자·"=?" 없음)면 인코딩 불필요
  if (/^[\x20-\x7E]*$/.test(input) && !input.includes('=?')) return input;

  const PREFIX = '=?UTF-8?B?';
  const SUFFIX = '?=';
  // encoded-word 최대 75자 → base64 payload 최대 63자 → 원본 바이트 최대 45(=3의 배수)
  const MAX_RAW_BYTES = 45;

  const words: string[] = [];
  let buf: number[] = [];
  const flush = () => {
    if (buf.length) {
      words.push(PREFIX + bytesToB64(new Uint8Array(buf)) + SUFFIX);
      buf = [];
    }
  };
  for (const ch of Array.from(input)) {
    const cb = Array.from(enc.encode(ch));
    if (buf.length + cb.length > MAX_RAW_BYTES) flush();
    buf.push(...cb);
  }
  flush();
  return words.join('\r\n '); // 헤더 폴딩(이어지는 줄은 공백으로 시작)
}

// base64 본문을 76자마다 CRLF 로 접는다.
function wrapBase64(b64: string): string {
  return (b64.match(/.{1,76}/g) ?? []).join('\r\n');
}

// ---------- 최소 SMTP 클라이언트 ----------

async function readReply(conn: Deno.Conn): Promise<{ code: number; text: string }> {
  const buf = new Uint8Array(8192);
  let acc = '';
  while (true) {
    const n = await withTimeout(conn.read(buf), 20000, 'SMTP 응답 대기 시간 초과');
    if (n === null) break;
    acc += dec.decode(buf.subarray(0, n));
    if (!acc.endsWith('\r\n')) continue;
    const lines = acc.split('\r\n').filter((l) => l.length > 0);
    const last = lines[lines.length - 1];
    // "NNN <text>" (하이픈 아닌 공백)이면 응답 종료
    if (last && /^\d{3} /.test(last)) {
      return { code: parseInt(last.slice(0, 3), 10), text: acc.trim() };
    }
  }
  return { code: 0, text: acc.trim() };
}

function withTimeout<T>(p: Promise<T>, ms: number, msg: string): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, rej) => setTimeout(() => rej(new Error(msg)), ms)),
  ]);
}

async function expect(
  conn: Deno.Conn,
  line: string | null,
  okCodes: number[],
  label: string,
): Promise<void> {
  if (line !== null) await conn.write(enc.encode(line + '\r\n'));
  const r = await readReply(conn);
  if (!okCodes.includes(r.code)) {
    throw new Error(`SMTP ${label} 실패 (${r.code}): ${r.text}`);
  }
}

async function sendViaGmail(opts: {
  user: string;
  pass: string;
  recipients: string[];
  rawMessage: string;
}): Promise<void> {
  const conn = await withTimeout(
    Deno.connectTls({ hostname: 'smtp.gmail.com', port: 465 }),
    20000,
    'smtp.gmail.com 접속 시간 초과',
  );
  try {
    await expect(conn, null, [220], 'greeting');
    await expect(conn, 'EHLO jlrk-settlement', [250], 'EHLO');
    await expect(conn, 'AUTH LOGIN', [334], 'AUTH LOGIN');
    await expect(conn, bytesToB64(enc.encode(opts.user)), [334], 'AUTH user');
    await expect(conn, bytesToB64(enc.encode(opts.pass)), [235], 'AUTH pass');
    await expect(conn, `MAIL FROM:<${opts.user}>`, [250], 'MAIL FROM');
    for (const rcpt of opts.recipients) {
      await expect(conn, `RCPT TO:<${rcpt}>`, [250, 251], `RCPT TO ${rcpt}`);
    }
    await expect(conn, 'DATA', [354], 'DATA');
    // dot-stuffing: 줄 첫 글자가 '.' 이면 '..' 로. (base64/헤더엔 없지만 안전장치)
    const body = opts.rawMessage.replace(/\r\n\./g, '\r\n..');
    await conn.write(enc.encode(body + '\r\n.\r\n'));
    await expect(conn, null, [250], '메시지 전송');
    try {
      await expect(conn, 'QUIT', [221], 'QUIT');
    } catch (_) {
      // QUIT 응답은 무시해도 됨 — 메일은 이미 큐에 들어감
    }
  } finally {
    try {
      conn.close();
    } catch (_) { /* already closed */ }
  }
}

// ---------- MIME 메시지 조립 ----------

function buildMessage(opts: {
  fromName: string;
  fromAddr: string;
  recipients: string[];
  subject: string;
  html: string;
}): string {
  const domain = opts.fromAddr.split('@')[1] || 'gmail.com';
  const headers = [
    `From: ${encodeHeaderWord(opts.fromName)} <${opts.fromAddr}>`,
    `To: ${opts.recipients.join(', ')}`,
    `Subject: ${encodeHeaderWord(opts.subject)}`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${crypto.randomUUID()}@${domain}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/html; charset="UTF-8"',
    'Content-Transfer-Encoding: base64',
  ];
  const body = wrapBase64(bytesToB64(enc.encode(opts.html)));
  return headers.join('\r\n') + '\r\n\r\n' + body;
}

// ---------- 엔트리포인트 ----------

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const json = (body: unknown, status: number) =>
    new Response(JSON.stringify(body), {
      status,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  try {
    const { to, subject, html } = await req.json().catch(() => ({}));
    if (!to || !subject || !html) {
      return json({ error: 'to, subject, html 값이 모두 필요합니다.' }, 400);
    }

    const gmailUser = Deno.env.get('GMAIL_USER');
    const gmailPass = Deno.env.get('GMAIL_APP_PASSWORD');
    if (!gmailUser || !gmailPass) {
      return json({ error: 'GMAIL_USER / GMAIL_APP_PASSWORD 시크릿이 설정되어 있지 않습니다.' }, 500);
    }

    const recipients = (Array.isArray(to) ? to : [to])
      .map((e) => String(e).trim())
      .filter((e) => e && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e));
    if (recipients.length === 0) {
      return json({ error: '유효한 수신자 주소가 없습니다.' }, 400);
    }

    const rawMessage = buildMessage({
      fromName: 'JLRK 정산 포털',
      fromAddr: gmailUser,
      recipients,
      subject: String(subject),
      html: String(html),
    });

    await sendViaGmail({ user: gmailUser, pass: gmailPass, recipients, rawMessage });

    return json({ success: true, sent: recipients.length }, 200);
  } catch (e) {
    return json({ error: String(e && (e as Error).message || e) }, 500);
  }
});
