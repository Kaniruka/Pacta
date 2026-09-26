import { createClient } from 'npm:@supabase/supabase-js@2';

type PurgeStatus = 'pending' | 'completed';

interface PurgeReceipt {
  user_id: string;
  status: PurgeStatus;
  purged_at: string | null;
}

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

function receiptForUser(value: unknown, userId: string): PurgeReceipt | null {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  const receipt = value as Record<string, unknown>;
  if (
    receipt.user_id !== userId ||
    (receipt.status !== 'pending' && receipt.status !== 'completed') ||
    (receipt.purged_at !== null && typeof receipt.purged_at !== 'string')
  ) {
    return null;
  }
  if (
    receipt.status === 'completed' &&
    (typeof receipt.purged_at !== 'string' ||
      Number.isNaN(Date.parse(receipt.purged_at)))
  ) {
    return null;
  }
  return receipt as unknown as PurgeReceipt;
}

const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

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
    console.error('admin user purge configuration is incomplete');
    return jsonResponse(500, { error: '管理员清除服务尚未配置。' });
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
  const userId = (body as Record<string, unknown>).user_id;
  if (typeof userId !== 'string' || !uuidPattern.test(userId)) {
    return jsonResponse(400, { error: '目标用户身份无效。' });
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
    console.error('admin user purge authorization lookup failed');
    return jsonResponse(500, { error: '无法确认管理员权限，请稍后重试。' });
  }
  if (!adminRecord) return jsonResponse(403, { error: '管理员权限不足。' });

  const { data: startedPurge, error: beginError } = await adminClient.rpc(
    'admin_begin_user_purge',
    { p_user_id: userId, p_admin_id: callerResult.user.id },
  );
  if (beginError) {
    console.error('admin user purge could not begin');
    return jsonResponse(409, { error: '目标用户当前不能清除。' });
  }
  const startReceipt = receiptForUser(startedPurge, userId);
  if (!startReceipt) {
    console.error('admin user purge begin returned an invalid result');
    return jsonResponse(502, { error: '无法确认清除状态，请稍后重试。' });
  }
  if (startReceipt.status === 'completed') {
    return jsonResponse(200, startReceipt as unknown as Record<string, unknown>);
  }

  const { error: businessDeleteError } = await adminClient.rpc(
    'admin_delete_user_business_data',
    { p_user_id: userId },
  );
  if (businessDeleteError) {
    const { error: cancelError } = await adminClient.rpc(
      'admin_cancel_user_purge',
      { p_user_id: userId, p_admin_id: callerResult.user.id },
    );
    if (cancelError) {
      console.error('admin user purge could not cancel a failed data deletion');
    }
    console.error('admin user business data deletion failed');
    return jsonResponse(502, { error: '云端业务数据尚未清除，请稍后重试。' });
  }

  const { data: targetLookup, error: targetLookupError } =
    await adminClient.auth.admin.getUserById(userId);
  if (targetLookupError && targetLookupError.status !== 404) {
    console.error('admin user purge target lookup failed');
    return jsonResponse(502, { error: '无法确认目标身份，请稍后重试。' });
  }

  if (!targetLookupError && targetLookup.user) {
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      userId,
      false,
    );
    if (deleteError) {
      const { data: afterDeleteLookup, error: afterDeleteError } =
        await adminClient.auth.admin.getUserById(userId);
      if (!afterDeleteError && afterDeleteLookup.user) {
        console.error('admin Auth user deletion did not remove the target');
        return jsonResponse(502, { error: '云端身份尚未清除，请稍后重试。' });
      }
      if (afterDeleteError?.status !== 404) {
        console.error('admin Auth user deletion failed');
        return jsonResponse(502, { error: '云端身份尚未清除，请稍后重试。' });
      }
    }
  }

  const { data: completedPurge, error: completeError } = await adminClient.rpc(
    'admin_complete_user_purge',
    { p_user_id: userId },
  );
  if (completeError) {
    console.error('admin user purge completion could not be recorded');
    return jsonResponse(502, { error: '尚未取得已完成回执，请稍后重试。' });
  }
  const completedReceipt = receiptForUser(completedPurge, userId);
  if (!completedReceipt || completedReceipt.status !== 'completed') {
    console.error('admin user purge completion returned an invalid result');
    return jsonResponse(502, { error: '尚未取得已完成回执，请稍后重试。' });
  }

  return jsonResponse(200, completedReceipt as unknown as Record<string, unknown>);
});
