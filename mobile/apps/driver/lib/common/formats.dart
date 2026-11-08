// Formats des écrans Ivia Driver (spec 033). Les montants viennent de
// `formatXof` (« 1 200 F ») ; les heures sont celles de Lomé (UTC+0, sans
// heure d'été), quel que soit le fuseau du téléphone.

/// Heure de Lomé : « 23:41 ».
String hhmm(DateTime d) {
  final u = d.toUtc();
  return '${u.hour.toString().padLeft(2, '0')}:'
      '${u.minute.toString().padLeft(2, '0')}';
}

/// Jour de Lomé (minuit UTC) d'un instant.
DateTime lomeDay(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(u.year, u.month, u.day);
}

/// Distance : « 800 m » sous 1 km, sinon « 4,2 km ».
String distance(int meters) {
  final rounded = (meters / 10).round() * 10;
  if (rounded < 1000) return '$rounded m';
  final km = (meters / 100).round() / 10;
  final text = km == km.roundToDouble()
      ? km.toStringAsFixed(0)
      : km.toStringAsFixed(1);
  return '${text.replaceAll('.', ',')} km';
}

/// Durée : « 12 min », « 1 h 12 », « 2 h ».
String duration(Duration d) {
  final minutes = d.inMinutes < 1 ? 1 : d.inMinutes;
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

/// Salutation selon l'heure de Lomé : « Bonjour » avant 18 h, « Bonsoir »
/// ensuite (et avant 4 h).
String greeting(DateTime now) {
  final h = now.toUtc().hour;
  return h >= 18 || h < 4 ? 'Bonsoir' : 'Bonjour';
}

/// Initiales du nom (« Kossi Adjo » → « KA »).
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}
