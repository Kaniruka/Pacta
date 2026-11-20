/// 面向用户的统一错误文案。
///
/// 技术异常（PostgREST/Supabase 函数签名、socket、TLS 握手等）只在日志里
/// 保留原文；界面上一律换成可继续操作的中文提示，避免把英文堆栈或 SQL
/// 函数签名直接摊给用户。已有中文业务提示保持原意。
String formatUserError(Object error, {String fallback = '操作未完成，请稍后重试。'}) {
  var text = error.toString().trim();
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
  if (text.isEmpty) return fallback;

  final lower = text.toLowerCase();
  final missingCloudFunction =
      lower.contains('could not find the function') ||
      lower.contains('schema cache') ||
      lower.contains('pgrst202');
  if (missingCloudFunction) {
    return '云端服务版本尚未同步最新接口，请稍后重试。';
  }
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
