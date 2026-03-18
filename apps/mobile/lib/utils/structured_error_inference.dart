String? inferStructuredErrorCode({
  required String message,
  String? explicitErrorCode,
}) {
  if (explicitErrorCode != null && explicitErrorCode.isNotEmpty) {
    return explicitErrorCode;
  }

  final normalized = message.toLowerCase();

  if (_containsAny(normalized, const [
    'check openai_api_key',
    'codex authentication',
    'codex auth',
  ])) {
    return 'codex_auth_required';
  }

  if (_containsAny(normalized, const [
    'project path not allowed',
    'path not allowed',
    'bridge_allowed_dirs',
  ])) {
    return 'path_not_allowed';
  }

  if (_containsAny(normalized, const ['git not available', 'git features'])) {
    return 'git_not_available';
  }

  if (_containsAny(normalized, const [
    'session expired',
    'token has expired',
    'token expired',
    'invalid_grant',
    'oauth token refresh failed',
  ])) {
    return 'auth_token_expired';
  }

  if (_containsAny(normalized, const [
    'authentication_error',
    'failed to authenticate',
    'authentication failed',
    'api error: 401',
    '401 unauthorized',
    'claude code authentication failed',
    'oauth token',
  ])) {
    return 'auth_api_error';
  }

  if (_containsAny(normalized, const [
    'authentication required',
    'not logged in',
    'credentials file',
    'no access token',
  ])) {
    return 'auth_login_required';
  }

  return null;
}

bool _containsAny(String haystack, List<String> needles) {
  for (final needle in needles) {
    if (haystack.contains(needle)) return true;
  }
  return false;
}
