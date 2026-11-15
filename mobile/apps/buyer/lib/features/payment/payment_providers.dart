import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

import '../../app/account.dart';

/// Intervalle de relecture d'une demande de paiement en attente.
const paymentRefreshInterval = Duration(seconds: 3);

/// Boutons « Simuler la validation » et « Simuler un refus » (faux
/// prestataire du serveur) : build debug avec
/// `--dart-define=IVIA_DEV_PAYMENT=true` seulement, jamais en release.
final devPaymentsProvider = Provider<bool>(
  (ref) => !kReleaseMode && const bool.fromEnvironment('IVIA_DEV_PAYMENT'),
);

/// Numéro complet de chaque demande envoyée depuis l'écran Paiement, par
/// identifiant de demande : en mémoire seulement (ni URL, ni état de
/// navigation, ni stockage), pour « Renvoyer la demande ». Lu une fois par
/// l'écran d'attente ; vidé au changement de compte.
final paymentPhonesProvider = Provider<Map<String, String>>((ref) {
  ref.watch(accountIdProvider);
  return {};
});

/// Nom de l'opérateur tel qu'affiché.
String operatorLabel(PaymentOperator operator) => switch (operator) {
  PaymentOperator.flooz => 'Flooz',
  PaymentOperator.tmoney => 'T-Money',
};

/// Une demande de paiement, relue pendant l'attente.
final paymentProvider = AsyncNotifierProvider.autoDispose
    .family<PaymentController, Payment, String>(
      PaymentController.new,
      retry: (_, _) => null,
    );

class PaymentController extends AsyncNotifier<Payment> {
  PaymentController(this.id);

  final String id;

  IviaApiClient get _client => ref.read(apiClientProvider);

  @override
  Future<Payment> build() {
    ref.watch(accountIdProvider);
    return _client.payment(id);
  }

  /// Relecture en cours, partagée : jamais deux à la fois.
  Future<void>? _loading;

  /// Relit la demande ; un échec garde la version affichée (et lève
  /// l'erreur). Une version plus ancienne que l'affichée est ignorée.
  Future<void> refresh() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    final payment = await _client.payment(id);
    if (!ref.mounted) return;
    final shown = state.value;
    if (shown != null && payment.updatedAt.isBefore(shown.updatedAt)) return;
    state = AsyncData(payment);
  }
}
