import 'package:flutter_test/flutter_test.dart';
import 'package:latihan_mobile/features/sessions/session.dart';

void main() {
  test('IDs are UUID v7: well-formed, unique and increasing', () {
    final ids = [for (var i = 0; i < 10000; i++) newId()];
    final format = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(ids.every(format.hasMatch), isTrue);
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, orderedEquals([...ids]..sort()));
  });

  test('the leading 48 bits are the creation time', () {
    final before = DateTime.now().millisecondsSinceEpoch;
    final id = newId();
    final after = DateTime.now().millisecondsSinceEpoch;
    final millis = int.parse(
      id.replaceAll('-', '').substring(0, 12),
      radix: 16,
    );
    // Allows for the counter having borrowed a millisecond.
    expect(millis, inInclusiveRange(before, after + 1));
  });
}
