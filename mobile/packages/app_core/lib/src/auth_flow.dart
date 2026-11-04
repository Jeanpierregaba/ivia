import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import 'auth_controller.dart';
import 'auth_draft.dart';
import 'providers.dart';

/// Usage d'un code reçu par e-mail (ADR 0011).
enum CodePurpose {
  /// Création de compte (ou mot de passe d'un compte de l'ancienne
  /// connexion par code).
  signup,

  /// Mot de passe oublié.
  reset,
}

/// Parcours avec code en cours : adresse, usage, renvoi, et code saisi.
/// Le serveur ne vérifie le code qu'avec le mot de passe : il reste en
/// mémoire entre l'écran des 6 cases et celui du mot de passe, jamais écrit
/// sur le téléphone.
class AuthFlowState {
  const AuthFlowState({
    required this.purpose,
    required this.email,
    required this.resendAfter,
    required this.expiresIn,
    required this.attempt,
    required this.sentAt,
    this.devCode,
    this.code,
    this.codeError,
  });

  final CodePurpose purpose;
  final String email;

  /// Délai avant de pouvoir renvoyer un code.
  final Duration resendAfter;

  /// Validité du code.
  final Duration expiresIn;

  /// Numéro de la demande : relance le compte à rebours à chaque envoi.
  final int attempt;

  /// Heure de l'envoi : le temps avant le renvoi en part (et ne repart pas
  /// à chaque retour sur les 6 cases).
  final DateTime sentAt;

  /// Développement seulement ([devAutoCodeProvider]) : code lu sur l'API
  /// locale, saisi automatiquement.
  final String? devCode;

  /// Code saisi, en attente du mot de passe.
  final String? code;

  /// Code refusé par le serveur au moment du mot de passe (faux, expiré,
  /// trop d'essais) : affiché sur l'écran des 6 cases.
  final String? codeError;

  AuthFlowState copyWith({
    String? Function()? code,
    String? Function()? codeError,
    String? Function()? devCode,
  }) => AuthFlowState(
    purpose: purpose,
    email: email,
    resendAfter: resendAfter,
    expiresIn: expiresIn,
    attempt: attempt,
    sentAt: sentAt,
    devCode: devCode == null ? this.devCode : devCode(),
    code: code == null ? this.code : code(),
    codeError: codeError == null ? this.codeError : codeError(),
  );
}

/// Erreurs du code renvoyées avec le mot de passe : retour aux 6 cases.
const codeErrors = {'otp_invalid', 'otp_expired', 'otp_too_many_attempts'};

final authFlowProvider = NotifierProvider<AuthFlow, AuthFlowState?>(
  AuthFlow.new,
);

class AuthFlow extends Notifier<AuthFlowState?> {
  IviaApiClient get _client => ref.read(apiClientProvider);

  @override
  AuthFlowState? build() {
    // Session ouverte (par ce parcours ou un autre) : parcours et adresse
    // saisie oubliés (téléphone partagé).
    ref.listen(authControllerProvider, (_, next) {
      if (next is AuthSignedOut) return;
      state = null;
      ref.read(authEmailDraftProvider.notifier).set('');
    });
    return null;
  }

  /// Demande un code (premier envoi ou renvoi) pour [purpose]. Lève
  /// [ApiException].
  Future<void> requestCode(CodePurpose purpose, String email) async {
    final otp = switch (purpose) {
      CodePurpose.signup => await _client.requestSignupCode(email),
      CodePurpose.reset => await _client.requestPasswordReset(email),
    };
    final normalized = IviaApiClient.normalizeEmail(email);
    String? devCode;
    if (ref.read(devAutoCodeProvider)) {
      try {
        devCode = await _client.devOtp(normalized);
      } on ApiException {
        // Compte inconnu (mot de passe oublié) : aucun code envoyé.
      }
    }
    final same = state?.purpose == purpose && state?.email == normalized;
    state = AuthFlowState(
      purpose: purpose,
      email: normalized,
      resendAfter: otp.resendAfter,
      expiresIn: otp.expiresIn,
      attempt: same ? state!.attempt + 1 : 1,
      sentAt: DateTime.now(),
      devCode: devCode,
    );
  }

  /// Code de développement saisi : il ne l'est qu'une fois par envoi (un
  /// retour sur les 6 cases ne le ressaisit pas).
  void devCodeUsed() => state = state?.copyWith(devCode: () => null);

  /// Code saisi : gardé pour l'écran du mot de passe.
  void codeEntered(String code) =>
      state = state?.copyWith(code: () => code, codeError: () => null);

  /// Envoie le mot de passe avec le code ; la session ouverte fait changer
  /// d'écran et oublie le parcours. Code refusé : [codeError] posé, code
  /// effacé (retour aux 6 cases). Lève [ApiException].
  Future<void> submitPassword(String password) async {
    final flow = state;
    final code = flow?.code;
    if (flow == null || code == null) return;
    try {
      final session = switch (flow.purpose) {
        CodePurpose.signup => await _client.signup(flow.email, code, password),
        CodePurpose.reset => await _client.resetPassword(
          flow.email,
          code,
          password,
        ),
      };
      // Le parcours est oublié par l'écouteur de [build] quand la session
      // s'ouvre : l'écran garde son contenu pendant la transition.
      await ref.read(authControllerProvider.notifier).signedIn(session);
    } on ApiException catch (e) {
      if (codeErrors.contains(e.code)) {
        state = flow.copyWith(code: () => null, codeError: () => e.message);
      }
      rethrow;
    }
  }

  /// Parcours abandonné (retour à la connexion).
  void clear() => state = null;
}
