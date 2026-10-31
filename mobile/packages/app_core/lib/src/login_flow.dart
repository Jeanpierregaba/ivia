import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import 'auth_controller.dart';
import 'providers.dart';

/// Code demandé pour une adresse : partagé entre l'écran e-mail et l'écran
/// du code.
class LoginFlowState {
  const LoginFlowState({
    required this.email,
    required this.resendAfter,
    required this.expiresIn,
    required this.attempt,
  });

  final String email;

  /// Délai avant de pouvoir renvoyer un code.
  final Duration resendAfter;

  /// Validité du code.
  final Duration expiresIn;

  /// Numéro de la demande : relance le compte à rebours à chaque envoi.
  final int attempt;
}

final loginFlowProvider = NotifierProvider<LoginFlow, LoginFlowState?>(
  LoginFlow.new,
);

class LoginFlow extends Notifier<LoginFlowState?> {
  IviaApiClient get _client => ref.read(apiClientProvider);

  @override
  LoginFlowState? build() => null;

  /// Demande un code (premier envoi ou renvoi). Lève [ApiException].
  Future<void> requestCode(String email) async {
    final otp = await _client.requestOtp(email);
    state = LoginFlowState(
      email: IviaApiClient.normalizeEmail(email),
      resendAfter: otp.resendAfter,
      expiresIn: otp.expiresIn,
      attempt: (state?.attempt ?? 0) + 1,
    );
  }

  /// Vérifie le code ; la session ouverte fait changer d'écran.
  /// Lève [ApiException].
  Future<void> verify(String code) async {
    final email = state?.email;
    if (email == null) return;
    final session = await _client.verifyOtp(email, code);
    await ref.read(authControllerProvider.notifier).signedIn(session);
    state = null;
  }
}

/// Adresse e-mail plausible ; le serveur reste seul juge.
bool isPlausibleEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
