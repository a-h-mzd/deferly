import 'dart:async';

import 'package:deferly/deferly.dart';
import 'package:test/test.dart';

Never _throwOriginal() => throw StateError('original');

Future<Never> _throwOriginalAsync() async {
  await Future<void>.delayed(Duration.zero);
  throw StateError('original');
}

final _isOriginal = isA<StateError>().having(
  (e) => e.message,
  'message',
  'original',
);

void main() {
  group('deferly', () {
    test('runs deferred actions in LIFO order after the body', () {
      final log = <String>[];
      final result = deferly((defer) {
        defer(() => log.add('a'));
        defer(() => log.add('b'));
        log.add('body');
        return 42;
      });
      expect(result, 42);
      expect(log, ['body', 'b', 'a']);
    });

    test('runs nested defers right after their parent', () {
      final log = <String>[];
      deferly<void>((defer) {
        defer(() {
          defer(() => log.add('0 inside'));
          log.add('0');
        });
        defer(() {
          defer(() => log.add('1 inside'));
          log.add('1');
        });
        log.add('body');
      });
      expect(log, ['body', '1', '1 inside', '0', '0 inside']);
    });

    test('runs deferred actions when the body throws', () {
      final log = <String>[];
      expect(
        () => deferly<void>((defer) {
          defer(() => log.add('cleanup'));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(log, ['cleanup']);
    });

    group('when a deferred action throws', () {
      test('still runs the remaining actions', () {
        final log = <String>[];
        expect(
          () => deferly<void>((defer) {
            defer(() => log.add('a'));
            defer(() => throw StateError('cleanup'));
            defer(() => log.add('c'));
          }),
          throwsStateError,
        );
        expect(log, ['c', 'a']);
      });

      test('still runs the remaining actions after several throw', () {
        final log = <String>[];
        expect(
          () => deferly<void>((defer) {
            defer(() => log.add('a'));
            defer(() => throw StateError('first'));
            defer(() => log.add('b'));
            defer(() => throw StateError('second'));
          }),
          throwsA(isA<StateError>()),
        );
        expect(log, ['b', 'a']);
      });

      test('the last error thrown wins', () {
        expect(
          () => deferly<void>((defer) {
            defer(() => throw ArgumentError('last'));
            defer(() => throw StateError('middle'));
            throw FormatException('body');
          }),
          throwsArgumentError,
        );
      });

      test('still runs nested actions it registered before throwing', () {
        final log = <String>[];
        expect(
          () => deferly<void>((defer) {
            defer(() => log.add('a'));
            defer(() {
              defer(() => log.add('nested'));
              throw StateError('cleanup');
            });
          }),
          throwsStateError,
        );
        expect(log, ['nested', 'a']);
      });

      test('throws even if the body returned a value', () {
        expect(
          () => deferly((defer) {
            defer(() => throw StateError('cleanup'));
            return 1;
          }),
          throwsStateError,
        );
      });
    });

    test('rethrows the body error with its original stack trace', () {
      StackTrace? caught;
      try {
        deferly<void>((defer) {
          defer(() {});
          _throwOriginal();
        });
      } catch (_, stackTrace) {
        caught = stackTrace;
      }
      expect(caught.toString(), contains('_throwOriginal'));
    });

    group('recover', () {
      test('returns null when no error is propagating', () {
        Object? recovered = 'not called';
        StackTrace? stackTrace;
        final result = deferly((defer) {
          defer(() {
            recovered = defer.recover();
            stackTrace = defer.stackTrace;
          });
          return 1;
        });
        expect(result, 1);
        expect(recovered, isNull);
        expect(stackTrace, isNull);
      });

      test('returns the body error and its stack trace', () {
        Object? recovered;
        StackTrace? stackTrace;
        expect(
          () => deferly<void>((defer) {
            defer(() {
              recovered = defer.recover();
              stackTrace = defer.stackTrace;
            });
            _throwOriginal();
          }),
          throwsA(_isOriginal),
        );
        expect(recovered, _isOriginal);
        expect(stackTrace.toString(), contains('_throwOriginal'));
      });

      test('does not stop the error if the action does nothing', () {
        final logged = <Object?>[];
        expect(
          () => deferly<int>((defer) {
            defer(() => logged.add(defer.recover()));
            throw StateError('original');
          }),
          throwsA(_isOriginal),
        );
        expect(logged, [_isOriginal]);
      });

      test('lets later actions see the same error', () {
        final seen = <Object?>[];
        expect(
          () => deferly<void>((defer) {
            defer(() => seen.add(defer.recover()));
            defer(() => seen.add(defer.recover()));
            throw StateError('original');
          }),
          throwsA(_isOriginal),
        );
        expect(seen, [_isOriginal, _isOriginal]);
      });

      test('returns an error thrown by an earlier action', () {
        Object? recovered;
        expect(
          () => deferly<void>((defer) {
            defer(() => recovered = defer.recover());
            defer(() => throw StateError('cleanup'));
          }),
          throwsStateError,
        );
        expect(
          recovered,
          isA<StateError>().having((e) => e.message, 'message', 'cleanup'),
        );
      });

      test('lets an action replace the error by throwing', () {
        Object? cause;
        expect(
          () => deferly<int>((defer) {
            defer(() {
              final error = defer.recover();
              if (error != null) {
                cause = error;
                throw FormatException('wrapped: $error');
              }
            });
            return int.parse('not a number');
          }),
          throwsA(isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('wrapped:'),
          )),
        );
        expect(cause, isFormatException);
      });

      test('throws a StateError when called from the body', () {
        expect(
          () => deferly((defer) => defer.recover()),
          throwsStateError,
        );
      });

      test('throws a StateError when called after deferly finished', () {
        late Defer<void> saved;
        deferly<void>((defer) => saved = defer);
        expect(saved.recover, throwsStateError);
      });
    });

    group('returns', () {
      test('stops the error and returns the value', () {
        final result = deferly<int>((defer) {
          defer(() {
            if (defer.recover() != null) defer.returns(-1);
          });
          return int.parse('not a number');
        });
        expect(result, -1);
      });

      test('stops an error thrown by an earlier action', () {
        final result = deferly((defer) {
          defer(() {
            if (defer.recover() is StateError) defer.returns(2);
          });
          defer(() => throw StateError('cleanup'));
          return 1;
        });
        expect(result, 2);
      });

      test('stops the error for a void function', () {
        final log = <String>[];
        deferly<void>((defer) {
          defer(() => log.add('runs after recovery'));
          defer(() => defer.returns(null));
          throw StateError('boom');
        });
        expect(log, ['runs after recovery']);
      });

      test('makes later actions see no error', () {
        Object? seen = 'not called';
        final result = deferly<int>((defer) {
          defer(() => seen = defer.recover());
          defer(() => defer.returns(0));
          throw StateError('boom');
        });
        expect(result, 0);
        expect(seen, isNull);
      });

      test('replaces a normal result', () {
        final result = deferly((defer) {
          defer(() => defer.returns(2));
          return 1;
        });
        expect(result, 2);
      });

      test('uses the last value when called several times', () {
        final result = deferly((defer) {
          defer(() => defer.returns(3));
          defer(() => defer.returns(2));
          return 1;
        });
        expect(result, 3);
      });

      test('is overridden by an action that throws later', () {
        expect(
          () => deferly((defer) {
            defer(() => throw StateError('later'));
            defer(() => defer.returns(2));
            return 1;
          }),
          throwsStateError,
        );
      });

      test('throws a StateError when called from the body', () {
        expect(
          () => deferly<int>((defer) {
            defer.returns(1);
            return 0;
          }),
          throwsStateError,
        );
      });
    });

    test('defer throws a StateError when called after deferly finished', () {
      late Defer<void> saved;
      deferly<void>((defer) => saved = defer);
      expect(() => saved(() {}), throwsStateError);
    });
  });

  group('deferlyAsync', () {
    test('runs deferred actions after the body completes', () async {
      final log = <String>[];
      final result = await deferlyAsync((defer) async {
        defer(() => log.add('a'));
        defer(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          log.add('b');
        });
        await Future<void>.delayed(const Duration(milliseconds: 10));
        log.add('body');
        return 42;
      });
      expect(result, 42);
      expect(log, ['body', 'b', 'a']);
    });

    test('runs nested async defers right after their parent', () async {
      final log = <String>[];
      await deferlyAsync<void>((defer) async {
        defer(() async {
          defer(() => log.add('0 inside'));
          await Future<void>.delayed(const Duration(milliseconds: 10));
          log.add('0');
        });
        defer(() async {
          defer(() async {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            log.add('1 inside');
          });
          log.add('1');
        });
        log.add('body');
      });
      expect(log, ['body', '1', '1 inside', '0', '0 inside']);
    });

    test('runs deferred actions when the body throws', () async {
      final log = <String>[];
      await expectLater(
        deferlyAsync<void>((defer) async {
          defer(() => log.add('cleanup'));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(log, ['cleanup']);
    });

    test('runs deferred actions when the body throws synchronously', () async {
      final log = <String>[];
      await expectLater(
        deferlyAsync<void>((defer) {
          defer(() => log.add('cleanup'));
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(log, ['cleanup']);
    });

    test('still runs the remaining actions when one throws', () async {
      final log = <String>[];
      await expectLater(
        deferlyAsync<void>((defer) async {
          defer(() => log.add('a'));
          defer(() async {
            await Future<void>.delayed(Duration.zero);
            throw StateError('cleanup');
          });
          defer(() => log.add('c'));
        }),
        throwsStateError,
      );
      expect(log, ['c', 'a']);
    });

    test('the last error thrown wins', () async {
      await expectLater(
        deferlyAsync<void>((defer) async {
          defer(() async => throw ArgumentError('last'));
          defer(() => throw StateError('middle'));
          throw FormatException('body');
        }),
        throwsArgumentError,
      );
    });

    test('rethrows the body error with its original stack trace', () async {
      StackTrace? caught;
      try {
        await deferlyAsync<void>((defer) async {
          defer(() {});
          await _throwOriginalAsync();
        });
      } catch (_, stackTrace) {
        caught = stackTrace;
      }
      expect(caught.toString(), contains('_throwOriginalAsync'));
    });

    test('recover returns null when no error is propagating', () async {
      Object? recovered = 'not called';
      final result = await deferlyAsync((defer) async {
        defer(() => recovered = defer.recover());
        return 1;
      });
      expect(result, 1);
      expect(recovered, isNull);
    });

    test('recover does not stop the error if the action does nothing',
        () async {
      final logged = <Object?>[];
      StackTrace? stackTrace;
      await expectLater(
        deferlyAsync<int>((defer) async {
          defer(() async {
            await Future<void>.delayed(Duration.zero);
            logged.add(defer.recover());
            stackTrace = defer.stackTrace;
          });
          return _throwOriginalAsync();
        }),
        throwsA(_isOriginal),
      );
      expect(logged, [_isOriginal]);
      expect(stackTrace.toString(), contains('_throwOriginalAsync'));
    });

    test('an async action can replace the error by throwing', () async {
      await expectLater(
        deferlyAsync<int>((defer) async {
          defer(() async {
            final error = defer.recover();
            await Future<void>.delayed(Duration.zero);
            if (error != null) throw FormatException('wrapped: $error');
          });
          throw StateError('original');
        }),
        throwsFormatException,
      );
    });

    test('returns stops the error and returns the value', () async {
      final result = await deferlyAsync<int>((defer) async {
        defer(() async {
          await Future<void>.delayed(Duration.zero);
          if (defer.recover() != null) defer.returns(-1);
        });
        await Future<void>.delayed(Duration.zero);
        throw StateError('boom');
      });
      expect(result, -1);
    });

    test('returns stops an error thrown by an earlier action', () async {
      final result = await deferlyAsync((defer) async {
        defer(() {
          if (defer.recover() is StateError) defer.returns(2);
        });
        defer(() async => throw StateError('cleanup'));
        return 1;
      });
      expect(result, 2);
    });

    test('returns replaces a normal result', () async {
      final result = await deferlyAsync((defer) async {
        defer(() => defer.returns(2));
        return 1;
      });
      expect(result, 2);
    });

    test('recover and returns throw a StateError from the body', () async {
      await expectLater(
        deferlyAsync((defer) async => defer.recover()),
        throwsStateError,
      );
      await expectLater(
        deferlyAsync<int>((defer) async {
          defer.returns(1);
          return 0;
        }),
        throwsStateError,
      );
    });

    test('defer accepts actions registered while cleanup is running', () async {
      final log = <String>[];
      final registered = Completer<void>();
      await deferlyAsync<void>((defer) async {
        // Registers an action from outside the body while an earlier
        // deferred action is still running.
        defer(() async {
          await registered.future;
        });
        defer(() {
          Future<void>(() {
            defer(() => log.add('late'));
            registered.complete();
          });
        });
      });
      expect(log, ['late']);
    });

    test('defer throws a StateError when called after it finished', () async {
      late AsyncDefer<void> saved;
      await deferlyAsync<void>((defer) async => saved = defer);
      expect(() => saved(() {}), throwsStateError);
      expect(saved.recover, throwsStateError);
      expect(() => saved.returns(null), throwsStateError);
    });
  });
}
