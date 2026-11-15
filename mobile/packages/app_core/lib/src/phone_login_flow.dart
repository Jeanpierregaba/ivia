import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

import 'app_identity.dart';
import 'auth_controller.dart';
import 'providers.dart';

/// Connexion par numéro (ADR 0012) : partagée entre l'écran du numéro,
/// l'écran du code et « Faisons connaissance ».
class PhoneLoginState {
  const PhoneLoginState({
    required this.phone,
    required this.channel,
    required this.resendAfter,
    required this.expiresIn,
    required this.attempt,
    this.signup,
    this.devCode,
  });

  /// Numéro au format +228XXXXXXXX.
  final String phone;

  /// Canal réellement utilisé pour le dernier code.
  final OtpChannel channel;
  final Duration resendAfter;
  final Duration expiresIn;

  /// Numéro de la demande : relance le compte à rebours à chaque envoi.
  final int attempt;

  /// Numéro nouveau, prouvé : inscription à terminer (jeton en mémoire
  /// seulement, jamais stocké).
  final PhoneSignupRequired? signup;

  /// Développement seulement ([devAutoCodeProvider]).
  final String? devCode;

  PhoneLoginState withSignup(PhoneSignupRequired signup) => PhoneLoginState(
    phone: phone,
    channel: channel,
    resendAfter: resendAfter,
    expiresIn: expiresIn,
    attempt: attempt,
    signup: signup,
  );
}

final phoneLoginFlowProvider =
    NotifierProvider<PhoneLoginFlow, PhoneLoginState?>(PhoneLoginFlow.new);

/// Nom lisible de l'appareil, montré dans « Appareils connectés » et dans
/// l'alerte « Nouvelle connexion ».
String defaultDeviceName() => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'Téléphone Android',
  TargetPlatform.iOS => 'iPhone',
  _ => 'Navigateur',
};

class PhoneLoginFlow extends Notifier<PhoneLoginState?> {
  IviaApiClient get _client => ref.read(apiClientProvider);

  @override
  PhoneLoginState? build() => null;

  Future<DeviceInfo> _device() async => DeviceInfo(
    id: await ref.read(sessionStoreProvider).deviceId(),
    name: defaultDeviceName(),
    app: ref.read(appIdentityProvider).appCode,
  );

  /// Demande un code (premier envoi, renvoi ou passage au SMS). [phone] :
  /// +228XXXXXXXX. Lève [ApiException].
  Future<void> requestCode(
    String phone, {
    OtpChannel channel = OtpChannel.whatsapp,
  }) async {
    final otp = await _client.requestPhoneCode(
      phone,
      await _device(),
      channel: channel,
    );
    final devCode = ref.read(devAutoCodeProvider)
        ? await _client.devOtp(phone)
        : null;
    state = PhoneLoginState(
      phone: phone,
      channel: otp.channel,
      resendAfter: otp.resendAfter,
      expiresIn: otp.expiresIn,
      attempt: (state?.attempt ?? 0) + 1,
      devCode: devCode,
    );
  }

  /// Vérifie le code. Numéro connu : la session ouverte fait changer
  /// d'écran ; retourne `false`. Numéro nouveau : retourne `true`, l'écran
  /// « Faisons connaissance » suit. Lève [ApiException].
  Future<bool> verify(String code) async {
    final current = state;
    if (current == null) return false;
    final result = await _client.verifyPhone(
      current.phone,
      code,
      await _device(),
    );
    switch (result) {
      case PhoneSignedIn(:final session):
        await ref.read(authControllerProvider.notifier).signedIn(session);
        state = null;
        return false;
      case PhoneSignupRequired():
        state = current.withSignup(result);
        return true;
    }
  }

  /// Crée le compte (prénom, nom, consentement donné) et ouvre la session.
  /// Lève [ApiException] (`signup_expired` : tout recommencer).
  Future<void> signup({
    required String firstName,
    required String lastName,
  }) async {
    final signup = state?.signup;
    if (signup == null) return;
    final session = await _client.phoneSignup(
      signupToken: signup.token,
      firstName: firstName,
      lastName: lastName,
      device: await _device(),
    );
    await ref.read(authControllerProvider.notifier).signedIn(session);
    state = null;
  }

  /// Retour à l'écran du numéro : l'inscription en cours est abandonnée.
  void reset() => state = null;
}
