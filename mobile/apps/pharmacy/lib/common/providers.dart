import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

// Données de l'espace pharmacie, partagées entre les écrans.

/// Pharmacie du compte connecté ; `null` : pas encore inscrite.
final pharmacyProfileProvider = FutureProvider<PharmacyProfile?>((ref) async {
  final signedIn = ref.watch(
    authControllerProvider.select((a) => a is AuthSignedIn),
  );
  if (!signedIn) return null;
  return ref.read(apiClientProvider).pharmacyMe();
});

final inboxProvider = FutureProvider.autoDispose<List<InboxAlert>>(
  (ref) => ref.read(apiClientProvider).pharmacyInbox(openOnly: false),
);
final ordersProvider = FutureProvider.autoDispose<List<PharmacyOrder>>(
  (ref) => ref.read(apiClientProvider).pharmacyOrders(),
);
final earningsProvider = FutureProvider.autoDispose<PharmacyEarnings>(
  (ref) => ref.read(apiClientProvider).pharmacyEarnings(),
);
final shiftsProvider = FutureProvider.autoDispose(
  (ref) => ref.read(apiClientProvider).pharmacyDutyShifts(),
);
