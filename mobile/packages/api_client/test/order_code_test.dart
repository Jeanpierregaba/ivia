import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';

void main() {
  test('code de commande : mêmes valeurs que l\'API et le back-office', () {
    expect(orderCode(1), 'HSWK-20E0');
    expect(orderCode(111), 'NTNJ-CKVW');
    expect(orderCode(1042), 'W8MB-QRCH');
    expect(orderCode(1043), 'F4D6-PHF8');
    expect(orderCode(999999), 'DC1D-KHHF');
    expect(orderCodeOfReference('IV-000111'), 'NTNJ-CKVW');
    final seen = <String>{};
    for (var n = 1; n <= 20000; n++) {
      expect(seen.add(orderCode(n)), isTrue);
    }
  });
}
