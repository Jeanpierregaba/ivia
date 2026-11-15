import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Espaces du compte et espace ouvert par la session.
class BusinessGate {
  const BusinessGate({this.spaces = const [], this.opened});
  final List<BusinessSpace> spaces;
  final BusinessSpace? opened;
}

String? _userId(AuthState auth) => switch (auth) {
  AuthSignedIn(:final user) => user.id,
  _ => null,
};

/// Lu à chaque connexion : pas d'espace, inscription ; plusieurs espaces sans
/// choix, sélection ; un seul, il s'ouvre tout seul.
final businessGateProvider =
    AsyncNotifierProvider<BusinessGateNotifier, BusinessGate>(
      BusinessGateNotifier.new,
      retry: (_, _) => null,
    );

class BusinessGateNotifier extends AsyncNotifier<BusinessGate> {
  IviaApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<BusinessGate> build() async {
    if (ref.watch(authControllerProvider.select(_userId)) == null) {
      return const BusinessGate();
    }
    return _load();
  }

  Future<BusinessGate> _load() async {
    final spaces = await _api.businessSpaces();
    var opened = await _api.openedBusinessSpace();
    if (opened == null && spaces.length == 1) {
      opened = await _api.openBusinessSpace(spaces.single.id);
    }
    return BusinessGate(spaces: spaces, opened: opened);
  }

  /// Relit les statuts sans repasser par le splash.
  Future<void> refresh() async {
    final next = await _load();
    if (ref.mounted) state = AsyncData(next);
  }

  Future<void> open(String id) async {
    await _api.openBusinessSpace(id);
    await refresh();
  }

  /// Revient à la liste des espaces (ou à l'inscription d'un nouvel espace).
  Future<void> close() async {
    await _api.closeBusinessSpace();
    final spaces = await _api.businessSpaces();
    if (ref.mounted) state = AsyncData(BusinessGate(spaces: spaces));
  }
}
