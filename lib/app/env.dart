class AppEnv {
  const AppEnv._();

  static const _defaultUrl = 'https://jrhdegdvdqnxstpdzbya.supabase.co';
  static const _envUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpyaGRlZ2R2ZHFueHN0cGR6YnlhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEyOTM2NDksImV4cCI6MjEwNjg2OTY0OX0.O8WMsF2z447mdWj6gNMyaJ9Q8eTFQwKZyLMMsxrfx5Y',
  );

  static String get supabaseUrl {
    var url = _envUrl.isEmpty ? _defaultUrl : _envUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    const restSuffix = '/rest/v1';
    if (url.endsWith(restSuffix)) {
      url = url.substring(0, url.length - restSuffix.length);
    }
    return url;
  }

  static bool get configured {
    final uri = Uri.tryParse(supabaseUrl);
    return uri != null &&
        uri.hasAuthority &&
        (uri.scheme == 'https' ||
            (uri.scheme == 'http' &&
                {'localhost', '127.0.0.1'}.contains(uri.host))) &&
        supabaseKey.isNotEmpty;
  }
}
