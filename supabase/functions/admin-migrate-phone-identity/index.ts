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

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

Deno.serve(async (request: Request) => {
  if (request.method !== 'POST') {
    return jsonResponse(405, { error: '仅支持 POST 请求。' });
  }

  const authorization = request.headers.get('Authorization') ?? '';
  const accessToken = authorization.match(/^Bearer\s+(.+)$/i)?.[1];
  if (!accessToken) return jsonResponse(401, { error: '请先登录。' });

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
    console.error('legacy phone identity migration configuration is incomplete');
    return jsonResponse(500, { error: '身份迁移服务尚未配置。' });
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
  const userId = values.user_id;
  const email = typeof values.email === 'string'
    ? values.email.trim().toLowerCase()
    : '';
  if (typeof userId !== 'string' || !uuidPattern.test(userId)) {
    return jsonResponse(400, { error: '目标用户身份无效。' });
  }
  if (!emailPattern.test(email) || email.length > 320) {
    return jsonResponse(400, { error: '请输入有效邮箱。' });
  }
  if (values.email_manually_verified !== true) {
    return jsonResponse(400, { error: '请确认已在应用外核实该邮箱。' });
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
    console.error('legacy phone identity migration authorization lookup failed');
    return jsonResponse(500, { error: '无法确认管理员权限，请稍后重试。' });
  }
  if (!adminRecord) return jsonResponse(403, { error: '管理员权限不足。' });

  const { data: purgeReceipt, error: purgeReceiptError } = await adminClient
    .from('user_purge_receipts')
    .select('status')
    .eq('user_id', userId)
    .maybeSingle();
  if (purgeReceiptError) {
    console.error('legacy phone identity migration purge-state lookup failed');
    return jsonResponse(500, { error: '无法确认目标身份状态，请稍后重试。' });
  }
  if (purgeReceipt) {
    return jsonResponse(409, { error: '该身份正在清除或已清除，不能迁移。' });
  }

  const { data: targetResult, error: targetLookupError } =
    await adminClient.auth.admin.getUserById(userId);
  if (targetLookupError || !targetResult.user) {
    const status = targetLookupError?.status === 404 ? 404 : 502;
    return jsonResponse(status, { error: '无法读取目标身份，请稍后重试。' });
  }

  const currentEmail = targetResult.user.email?.trim().toLowerCase() ?? '';
  if (currentEmail === email) {
    return jsonResponse(200, {
      status: 'already_migrated',
      user_id: targetResult.user.id,
      email,
    });
  }
  if (currentEmail || !targetResult.user.phone) {
    return jsonResponse(409, { error: '目标身份不是待迁移的手机号身份。' });
  }

  const { data: updatedResult, error: updateError } =
    await adminClient.auth.admin.updateUserById(userId, {
      email,
      email_confirm: true,
    });
  if (updateError) {
    console.error('legacy phone identity migration Auth update failed');
    return jsonResponse(409, { error: '邮箱不可用，身份未迁移。' });
  }
  if (
    updatedResult.user.id !== userId ||
    updatedResult.user.email?.trim().toLowerCase() !== email
  ) {
    console.error('legacy phone identity migration changed an unexpected identity');
    return jsonResponse(502, { error: '无法确认身份迁移结果，请稍后重试。' });
  }

  return jsonResponse(200, {
    status: 'migrated',
    user_id: updatedResult.user.id,
    email,
  });
});
