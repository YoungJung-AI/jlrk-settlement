// Supabase Edge Function: manage-user
// 관리자만 호출 가능한 계정 관리 API.
// SERVICE_ROLE_KEY는 RLS를 무시하는 마스터 키이므로 반드시 서버(여기)에서만 사용한다.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
    const SERVICE_KEY = Deno.env.get('SERVICE_ROLE_KEY');
    const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!;
    if (!SERVICE_KEY) return json({ error: 'SERVICE_ROLE_KEY 시크릿이 설정되어 있지 않습니다.' }, 500);

    // ---- 1) 호출자가 정말 관리자인지 서버에서 재검증 ----
    const authHeader = req.headers.get('Authorization') || '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) return json({ error: '인증 정보가 없습니다.' }, 401);

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: uErr } = await userClient.auth.getUser();
    if (uErr || !user) return json({ error: '로그인이 필요합니다.' }, 401);

    const admin = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: me } = await admin
      .from('profiles').select('role').eq('id', user.id).single();
    if (!me || me.role !== 'ADMIN') return json({ error: '관리자만 사용할 수 있습니다.' }, 403);

    // ---- 2) 작업 처리 ----
    const body = await req.json();
    const action = body.action as string;

    if (action === 'list') {
      const { data: profiles } = await admin
        .from('profiles')
        .select('id, role, display_name, retailer_id, email, is_active, must_change_password, password_changed_at, created_at, retailers(code, name)')
        .order('created_at');
      return json({ success: true, users: profiles || [] });
    }

    if (action === 'create') {
      const { email, password, role, retailer_id, display_name } = body;
      if (!email || !password) return json({ error: '이메일과 초기 비밀번호가 필요합니다.' }, 400);
      if (String(password).length < 8) return json({ error: '초기 비밀번호는 8자 이상이어야 합니다.' }, 400);
      if (role === 'RETAILER' && !retailer_id) return json({ error: '리테일러 계정은 소속 리테일러가 필요합니다.' }, 400);

      const { data: created, error: cErr } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true, // 관리자가 만든 계정이므로 메일 인증 생략
      });
      if (cErr) return json({ error: cErr.message }, 400);

      const { error: pErr } = await admin.from('profiles').insert({
        id: created.user.id,
        role: role || 'RETAILER',
        retailer_id: role === 'ADMIN' ? null : retailer_id,
        display_name: display_name || email,
        email,
        must_change_password: true, // 첫 로그인 시 변경 강제
        is_active: true,
      });
      if (pErr) {
        // 프로필 생성이 실패하면 계정도 되돌린다 (고아 계정 방지)
        await admin.auth.admin.deleteUser(created.user.id);
        return json({ error: 'profiles 등록 실패: ' + pErr.message }, 400);
      }
      return json({ success: true, id: created.user.id });
    }

    if (action === 'reset_password') {
      const { user_id, password } = body;
      if (!user_id || !password) return json({ error: '대상 계정과 새 비밀번호가 필요합니다.' }, 400);
      if (String(password).length < 8) return json({ error: '비밀번호는 8자 이상이어야 합니다.' }, 400);

      const { error: rErr } = await admin.auth.admin.updateUserById(user_id, { password });
      if (rErr) return json({ error: rErr.message }, 400);
      await admin.from('profiles')
        .update({ must_change_password: true, password_changed_at: null })
        .eq('id', user_id);
      return json({ success: true });
    }

    if (action === 'set_active') {
      const { user_id, is_active } = body;
      if (!user_id) return json({ error: '대상 계정이 필요합니다.' }, 400);
      if (user_id === user.id) return json({ error: '본인 계정은 비활성화할 수 없습니다.' }, 400);

      // 마지막 활성 관리자를 잠그지 않도록 방어
      if (is_active === false) {
        const { data: target } = await admin.from('profiles').select('role').eq('id', user_id).single();
        if (target?.role === 'ADMIN') {
          const { count } = await admin.from('profiles')
            .select('id', { count: 'exact', head: true })
            .eq('role', 'ADMIN').eq('is_active', true);
          if ((count || 0) <= 1) return json({ error: '마지막 관리자 계정은 비활성화할 수 없습니다.' }, 400);
        }
      }

      // 로그인 차단은 ban 으로 처리 (해제 시 none)
      const { error: bErr } = await admin.auth.admin.updateUserById(user_id, {
        ban_duration: is_active ? 'none' : '876000h', // 약 100년
      });
      if (bErr) return json({ error: bErr.message }, 400);
      await admin.from('profiles').update({ is_active }).eq('id', user_id);
      return json({ success: true });
    }

    return json({ error: '알 수 없는 action 입니다.' }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
