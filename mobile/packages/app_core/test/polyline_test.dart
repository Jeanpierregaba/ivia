import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_app_core/ivia_app_core.dart';

void main() {
  test('polyline6 OSRM : points dans Lomé, écarts négatifs compris', () {
    // Trajet réel renvoyé par OSRM (Grand Marché vers Tokoin).
    final pts = decodePolyline6(
      'coguJsosiAah@zVqJxEoW`MeUnLiHrDgGzC}H|DmHzD}EnCyC|AgFdCaFfC_ErB}ExBkJtE{G`DwEtBmHzDoEtBgQ|IcHhDiI~DgMfGaB~@sBfAlAbEvGlU`EbOjEfPjArEx@|EwDd@mBTmGx@mJlA{YzDuP|BgOzBi_@|Fg^hIm]hG_b@rIgIxCoKpC{@ZsOlDeeCni@KBmPlDkY~FiH|A}K`CgGvAib@lKeFhAe]lI}NnDcDv@k]~IgPdEoJdC_a@xJcUxFqD`AiTlFk@NuPdE{SfFkYzGnFtO',
    );
    expect(pts, hasLength(71));
    expect(pts.first.lat, closeTo(6.13197, 1e-6));
    expect(pts.first.lng, closeTo(1.222922, 1e-6));
    expect(pts.last.lat, closeTo(6.148173, 1e-6));
    expect(pts.last.lng, closeTo(1.214921, 1e-6));
    for (final p in pts) {
      expect(p.lat, inInclusiveRange(6.1, 6.2));
      expect(p.lng, inInclusiveRange(1.2, 1.25));
    }
  });
}
