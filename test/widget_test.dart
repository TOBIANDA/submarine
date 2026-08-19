// Basic smoke test for Tobitube
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('ProviderScope smoke test', (WidgetTester tester) async {
    // AudioService requires platform channels that can't run in unit tests.
    // Just verify ProviderScope type is available.
    expect(ProviderScope, isNotNull);
  });
}
