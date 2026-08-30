// Supabase Edge Function: send-email (Gmail SMTP 방식)
// 역할: 브라우저에서 요청을 받아 Gmail SMTP로 실제 메일을 발송한다.
// Gmail 계정/앱비밀번호(GMAIL_USER, GMAIL_APP_PASSWORD)는 여기(서버)에서만 쓰이고
// 브라우저 코드에는 절대 노출되지 않는다.

import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { to, subject, html } = await req.json();
    if (!to || !subject || !html) {
      return new Response(JSON.stringify({ error: 'to, subject, html 값이 모두 필요합니다.' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const gmailUser = Deno.env.get('GMAIL_USER');
    const gmailPass = Deno.env.get('GMAIL_APP_PASSWORD');
    if (!gmailUser || !gmailPass) {
      return new Response(JSON.stringify({ error: 'GMAIL_USER / GMAIL_APP_PASSWORD 시크릿이 설정되어 있지 않습니다.' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const client = new SMTPClient({
      connection: {
        hostname: 'smtp.gmail.com',
        port: 465,
        tls: true,
        auth: { username: gmailUser, password: gmailPass },
      },
    });

    const toList = Array.isArray(to) ? to : [to];

    await client.send({
      from: `JLRK 정산 포털 <${gmailUser}>`,
      to: toList,
      subject,
      html,
      content: 'auto', // html만 있어도 자동으로 텍스트 버전 생성
    });

    await client.close();

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});
