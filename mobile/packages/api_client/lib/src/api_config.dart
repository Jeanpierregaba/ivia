/// Configuration de l'accès à l'API ivia.
class ApiConfig {
  const ApiConfig({required this.baseUrl});

  /// Lit l'URL passée au build : `--dart-define=API_BASE_URL=https://…`.
  ///
  /// En développement, sans valeur : la machine de développement vue depuis
  /// l'émulateur Android (`10.0.2.2`), où tourne `go run ./cmd/api`.
  /// En release, la valeur est obligatoire.
  factory ApiConfig.fromEnvironment() {
    const url = String.fromEnvironment('API_BASE_URL');
    if (url.isNotEmpty) return ApiConfig(baseUrl: Uri.parse(url));
    if (const bool.fromEnvironment('dart.vm.product')) {
      throw StateError(
        'API_BASE_URL manquante : construire avec --dart-define=API_BASE_URL=https://…',
      );
    }
    return ApiConfig(baseUrl: Uri.parse(defaultBaseUrl));
  }

  static const defaultBaseUrl = 'http://10.0.2.2:8080';

  final Uri baseUrl;
}
