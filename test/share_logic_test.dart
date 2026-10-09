import 'package:flutter_test/flutter_test.dart';
import 'package:vaulton/features/storage/share_logic.dart';

void main() {
  const alice = ShareUser(userName: 'alice', displayName: 'Alice Adams', email: 'alice@example.com');
  const bob = ShareUser(userName: 'bob', displayName: 'bob');
  const carol = ShareUser(userName: 'carol', displayName: 'Carol', email: 'c@x.io', isLockedOut: true);
  const owner = ShareUser(userName: 'root');

  test('quota text <-> bytes', () {
    expect(parseQuota('').bytes, 0);
    expect(parseQuota('').error, isNull);
    expect(parseQuota('1').bytes, kGiB);
    expect(parseQuota('1,5').bytes, (1.5 * kGiB).round());
    expect(parseQuota('abc').error, isNotNull);
    expect(parseQuota('-2').error, isNotNull);

    expect(bytesToGb(0), '');
    expect(bytesToGb(kGiB), '1.00');
    expect(bytesToGb(kGiB * 3 ~/ 2), '1.50');
    expect(bytesToCapacity(kGiB, 'GiB'), '1.00');
    expect(bytesToCapacity(kGiB * 3 ~/ 2, 'GiB'), '1.50');
    expect(bytesToCapacity(kGiB * 3 ~/ 2, 'TiB'), '0.00');
    expect(gbToBytes('2'), 2 * kGiB);
    expect(gbToBytes('x'), isNull);
  });

  test('user display', () {
    expect(alice.title, 'Alice Adams');
    expect(alice.subtitle, '@alice · alice@example.com');
    expect(alice.initial, 'A');
    expect(bob.title, 'bob');
    expect(bob.subtitle, '');
  });

  test('search matches name, user name and e-mail, word by word', () {
    expect(alice.matches(''), isTrue);
    expect(alice.matches('adams'), isTrue);
    expect(alice.matches('ali exam'), isTrue);
    expect(alice.matches('zzz'), isFalse);
    expect(filterUsers([alice, bob], 'bo').map((u) => u.userName), ['bob']);
    expect(findUser([alice, bob], 'ALICE')?.userName, 'alice');
    expect(findUser([alice, bob], 'dave'), isNull);
  });

  test('available users skip taken + excluded, locked accounts last', () {
    final r = availableUsers(all: [carol, bob, alice, owner], taken: ['ALICE'], exclude: ['root']);
    expect(r.map((u) => u.userName), ['bob', 'carol']);
  });

  test('over-allocation', () {
    expect(overAllocated(100, 101), isTrue);
    expect(overAllocated(100, 100), isFalse);
    expect(overAllocated(0, 999), isFalse);
  });

  test('payload drops blanks and de-duplicates case-insensitively', () {
    final p = buildSharePayload([
      (userName: 'Alice', maxBytes: 1),
      (userName: ' ', maxBytes: 5),
      (userName: 'alice', maxBytes: 7),
      (userName: 'bob', maxBytes: 0),
    ]);
    expect(p, [
      {'userName': 'alice', 'maxBytes': 7},
      {'userName': 'bob', 'maxBytes': 0},
    ]);
  });
}
