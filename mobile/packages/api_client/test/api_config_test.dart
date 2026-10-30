import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:test/test.dart';

void main() {
  test("sans API_BASE_URL, vise l'hôte vu depuis l'émulateur Android", () {
    expect(
      ApiConfig.fromEnvironment().baseUrl,
      Uri.parse('http://10.0.2.2:8080'),
    );
  });
}
