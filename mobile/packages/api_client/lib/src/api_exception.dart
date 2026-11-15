/// Erreur d'un appel à l'API, au format commun du backend :
/// `{"error": {"code": "...", "message": "...", "fields": {...}}}`.
///
/// [message] est en français et peut être affiché tel quel.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.fields = const {},
    this.statusCode,
  });

  /// Pas de réponse du serveur (réseau coupé, délai dépassé).
  const ApiException.network()
    : code = networkCode,
      message =
          'Pas de connexion internet. Vérifiez votre réseau et réessayez.',
      fields = const {},
      statusCode = null;

  /// Réponse inattendue du serveur.
  const ApiException.unknown({this.statusCode})
    : code = unknownCode,
      message = 'Une erreur est survenue. Réessayez dans un instant.',
      fields = const {};

  static const networkCode = 'network_error';
  static const unknownCode = 'unknown_error';

  /// Code stable en anglais (ex. `otp_invalid`).
  final String code;
  final String message;

  /// Erreurs par champ (`validation_failed`), clé = nom du champ de l'API.
  final Map<String, String> fields;
  final int? statusCode;

  bool get isNetwork => code == networkCode;

  @override
  String toString() => 'ApiException($code, $statusCode)';
}
