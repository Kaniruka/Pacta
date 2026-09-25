import { createClient } from 'npm:@supabase/supabase-js@2';

const jsonResponse = (status: number, payload: Record<string, unknown>) =>
  new Response(JSON.stringify(payload), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

function configuredKey(legacyName: string, keySetName: string): string | null {
  const legacyKey = Deno.env.get(legacyName);
  if (legacyKey) return legacyKey;

  const rawKeySet = Deno.env.get(keySetName);
  if (!rawKeySet) return null;
  try {
    const keySet = JSON.parse(rawKeySet) as Record<string, string>;
    return keySet.default ?? Object.values(keySet)[0] ?? null;
  } catch {
    return rawKeySet;
  }
}

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return jsonResponse(405, { error: '仅支持 POST 请求。' });
  }

  const authorization = request.headers.get('Authorization') ?? '';
  const accessToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) {
    return jsonResponse(401, { error: '请先登录。' });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const publishableKey = configuredKey(
    'SUPABASE_ANON_KEY',
    'SUPABASE_PUBLISHABLE_KEYS',
  );
  const serviceKey = configuredKey(
    'SUPABASE_SERVICE_ROLE_KEY',
    'SUPABASE_SECRET_KEYS',
  );
  if (!supabaseUrl || !publishableKey || !serviceKey) {
    console.error('admin password reset configuration is incomplete');
    return jsonResponse(500, { error: '管理员重置服务尚未配置。' });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: '请求内容无效。' });
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    return jsonResponse(400, { error: '请求内容无效。' });
  }

  const values = body as Record<string, unknown>;
  const email = typeof values.email === 'string'
    ? values.email.trim().toLowerCase()
    : '';
  const newPassword = typeof values.new_password === 'string'
    ? values.new_password
    : '';
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return jsonResponse(400, { error: '请输入有效的目标用户邮箱。' });
  }
  if (newPassword.length < 8 || newPassword.length > 256) {
    return jsonResponse(400, { error: '新密码长度必须为 8 至 256 个字符。' });
  }
  if (values.manual_verification_confirmed !== true) {
    return jsonResponse(400, { error: '请先确认已完成人工核实。' });
  }

  const callerClient = createClient(supabaseUrl, publishableKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  const { data: callerResult, error: callerError } =
    await callerClient.auth.getUser(accessToken);
  if (callerError || !callerResult.user) {
    return jsonResponse(401, { error: '登录状态无效，请重新登录。' });
  }

  const adminClient = createClient(supabaseUrl, serviceKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });
  const { data: adminRecord, error: adminCheckError } = await adminClient
    .from('app_admins')
    .select('user_id')
    .eq('user_id', callerResult.user.id)
    .maybeSingle();
  if (adminCheckError) {
    console.error('admin password reset authorization lookup failed');
    return jsonResponse(500, { error: '无法确认管理员权限，请稍后重试。' });
  }
  if (!adminRecord) {
    return jsonResponse(403, { error: '管理员权限不足。' });
  }

  const { data: targetUserId, error: targetLookupError } = await adminClient.rpc(
    'admin_resolve_auth_user_id_by_email',
    { p_email: email },
  );
  if (targetLookupError) {
    console.error('admin password reset target lookup failed');
    return jsonResponse(500, { error: '无法查询目标用户，请稍后重试。' });
  }
  if (typeof targetUserId !== 'string') {
    return jsonResponse(404, { error: '找不到该邮箱对应的用户。' });
  }

  const { error: resetError } = await adminClient.auth.admin.updateUserById(
    targetUserId,
    { password: newPassword },
  );
  if (resetError) {
    console.error('admin password reset Auth Admin update failed');
    return jsonResponse(400, { error: '密码未能重置，请检查密码要求后重试。' });
  }

  return jsonResponse(200, { status: 'password_reset' });
});
