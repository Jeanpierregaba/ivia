import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

/// Alerte à traiter : en attente de réponse, délai pas écoulé.
bool isOpenAlert(InboxAlert a, DateTime now) =>
    !a.responded && a.status == 'pending' && a.searchEndsAt.isAfter(now);

/// Alerte ouverte que la pharmacie n'a pas encore regardée (pastille de la
/// cloche, « Nouvelle »).
bool isNewAlert(InboxAlert a, DateTime now) => isOpenAlert(a, now) && !a.seen;

/// « 2 produits · ordonnance · client à 650 m ».
String alertSummary(InboxAlert a) => [
  if (a.items.isNotEmpty)
    '${a.items.length} produit${a.items.length > 1 ? 's' : ''}'
  else
    'Ordonnance en photo',
  if (a.items.isNotEmpty && a.photoCount > 0) 'ordonnance',
  'client à ${formatDistance(a.distanceM)}',
].join(' · ');

/// Chiffres du jour (heure de Lomé, UTC) : alertes reçues, répondues,
/// confirmées par le client. Calculés sur les dernières alertes lues.
({int received, int responded, int confirmed}) todayStats(
  List<InboxAlert> inbox,
  DateTime now,
) {
  final today = inbox.where((a) {
    final d = a.receivedAt.toUtc();
    final n = now.toUtc();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  });
  return (
    received: today.length,
    responded: today.where((a) => a.responded).length,
    confirmed: today.where((a) => a.unlocked).length,
  );
}
