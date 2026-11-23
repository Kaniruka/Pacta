/// 面向用户的统一错误文案。
///
/// 技术异常（PostgREST/Supabase 函数签名、socket、TLS 握手等）只在日志里
/// 保留原文；界面上一律换成可继续操作的中文提示，避免把英文堆栈或 SQL
/// 函数签名直接摊给用户。已有中文业务提示保持原意。
library;

/// 已知失败的精准中文文案。
///
/// 只做关键字识别，绝不回显 `statusCode`、`code`、堆栈或 PostgREST 函数
/// 签名。登录页与其它页面共用这一份对照表，保证同一类异常在任何入口都得到
/// 同一句话；未命中返回 `null`，由调用方决定兜底文案。
String? describeKnownFailure(Object error) {
  final text = _stripExceptionPrefixes(error);
  if (text.isEmpty) return null;
  final lower = text.toLowerCase();

  // 注册资格：GoTrue 邀请制项目的 `signup_not_allowed` 与自定义文案。
  // message 常是 `Signups not allowed for this instance`，不含 `eligib`，
  // 所以 code 与 message 两种形态都要认。
  if (lower.contains('eligib') ||
      lower.contains('not eligible') ||
      lower.contains('invitation') ||
      lower.contains('signup_not_allowed') ||
      lower.contains('signups not allowed')) {
    return '该邮箱尚未获得注册资格，请联系管理员开通。';
  }
  // 凭据不匹配：400 `invalid_grant` 与 `Invalid login credentials`。
  if (lower.contains('invalid login credentials') ||
      lower.contains('invalid_credentials') ||
      lower.contains('invalid email or password') ||
      lower.contains('invalid_grant')) {
    return '邮箱或密码错误，请核对后重试。';
  }
  if (lower.contains('user_already_exists') ||
      lower.contains('already registered')) {
    return '该邮箱已注册，请直接切换到「登录」。';
  }
  // 账号停用：400 `user_banned`。必须早于频率限制判定，停用不是「重试」。
  if (lower.contains('user_banned') || lower.contains('banned')) {
    return '该账号已被停用，请联系管理员。';
  }
  if (lower.contains('over_request_rate_limit') ||
      lower.contains('too many requests') ||
      _hasStatusCode(lower, 429)) {
    return '操作过于频繁，请稍后再试。';
  }
  // 数据库与网络层：离线、DNS 失败、TLS 握手、连接被拒、服务端 5xx。
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('handshakeexception') ||
      lower.contains('timeoutexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('database error') ||
      _hasStatusCode(lower, 502) ||
      _hasStatusCode(lower, 503) ||
      _hasStatusCode(lower, 504)) {
    return '无法连接到云端服务，请检查网络后重试。';
  }
  return null;
}

String formatUserError(Object error, {String fallback = '操作未完成，请稍后重试。'}) {
  final text = _stripExceptionPrefixes(error);
  if (text.isEmpty) return fallback;

  final lower = text.toLowerCase();
  final missingCloudFunction =
      lower.contains('could not find the function') ||
      lower.contains('schema cache') ||
      lower.contains('pgrst202');
  if (missingCloudFunction) {
    return '云端服务版本尚未同步最新接口，请稍后重试。';
  }

  final known = describeKnownFailure(text);
  if (known != null) return known;

  const technicalMarkers = [
    'postgrestexception',
    'pgrst',
    'socketexception',
    'clientexception',
    'handshakeexception',
    'databaseexception',
    'sqlexception',
  ];
  if (technicalMarkers.any(lower.contains)) {
    return '云端服务接口尚未就绪或网络异常，请稍后重试。';
  }
  return text;
}

String _stripExceptionPrefixes(Object error) {
  var text = (error is String ? error : error.toString()).trim();
  const prefixes = ['Bad state: ', 'Invalid argument(s): ', 'Exception: '];
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final prefix in prefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length).trim();
        stripped = true;
      }
    }
  }
  return text;
}

bool _hasStatusCode(String lower, int statusCode) =>
    RegExp('\\b$statusCode\\b').hasMatch(lower);
