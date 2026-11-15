import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Dans le navigateur : le script Google Maps doit être chargé (réseau coupé,
/// clé absente ou bloqueur : la carte passe au fond OpenStreetMap).
bool googleMapsLoaded() {
  final google = globalContext['google'];
  if (google == null || google.isUndefinedOrNull) return false;
  final maps = (google as JSObject)['maps'];
  return maps != null && !maps.isUndefinedOrNull;
}
