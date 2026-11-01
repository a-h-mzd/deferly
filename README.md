# deferly

[![pub package](https://img.shields.io/pub/v/deferly.svg)](https://pub.dev/packages/deferly)
[![pub points](https://img.shields.io/pub/points/deferly)](https://pub.dev/packages/deferly/score)
[![likes](https://img.shields.io/pub/likes/deferly)](https://pub.dev/packages/deferly/score)
[![downloads](https://img.shields.io/pub/dm/deferly)](https://pub.dev/packages/deferly/score)
[![CI](https://github.com/a-h-mzd/deferly/actions/workflows/ci.yml/badge.svg)](https://github.com/a-h-mzd/deferly/actions/workflows/ci.yml)
[![coverage](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/a-h-mzd/deferly/badges/coverage.json)](https://github.com/a-h-mzd/deferly/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/a-h-mzd/deferly/blob/main/LICENSE)

Go-style `defer` and `recover` for Dart. Register cleanup actions that run
in reverse order (LIFO) when a function exits, whether it returns normally
or throws. Works with sync and async code, supports nested defers, and lets
deferred actions inspect, replace or recover from errors.

```dart
String read(String path) => deferly((defer) {
      final file = File(path).openSync();
      defer(file.closeSync); // always runs, even if reading throws
      return utf8.decode(file.readSync(file.lengthSync()));
    });
```

## At a glance

| | |
|---|---|
| **API** | 2 functions: `deferly` (sync) and `deferlyAsync` (async) |
| **Dependencies** | None |
| **Platforms** | Android, iOS, Linux, macOS, Windows, Web, and Wasm |
| **Dart SDK** | 2.12 and later, including all of Dart 3 |
| **Test coverage** | 100% of lines and branches, enforced in CI |
| **License** | [MIT](https://github.com/a-h-mzd/deferly/blob/main/LICENSE) |

## Why

Without deferly, every resource needs its own nested `try`/`finally`, and
cleanup is written far from the code that acquires the resource:

```dart
final a = openA();
try {
  final b = openB();
  try {
    return work(a, b);
  } finally {
    b.close();
  }
} finally {
  a.close();
}
```

With deferly, cleanup sits right next to the acquisition, and runs in the
correct reverse order:

```dart
return deferly((defer) {
  final a = openA();
  defer(a.close);
  final b = openB();
  defer(b.close);
  return work(a, b);
});
```

## Installation

```sh
dart pub add deferly
```

## Usage

Wrap the function's **body**, not the function itself. The function keeps
its own signature, so any parameters, generics and return types work with
full static typing.

### Sync

```dart
import 'dart:convert';
import 'dart:io';

import 'package:deferly/deferly.dart';

String read(String path) => deferly((defer) {
      final file = File(path).openSync();
      defer(file.closeSync);
      return utf8.decode(file.readSync(file.lengthSync()));
    });
```

### Async

Use `deferlyAsync` for functions that return a `Future`. Cleanup actions
run after the body completes, and may be async themselves.

```dart
import 'dart:convert';
import 'dart:io';

import 'package:deferly/deferly.dart';

Future<String> fetch(Uri url) => deferlyAsync((defer) async {
      final client = HttpClient();
      defer(client.close);
      final request = await client.getUrl(url);
      final response = await request.close();
      return response.transform(utf8.decoder).join();
    });
```

### Order and nested defers

Actions run in reverse registration order. An action may call `defer`
itself; the nested action runs right after its parent, before earlier
actions, the same as in Go.

```dart
import 'package:deferly/deferly.dart';

int add(int a, int b) => deferly((defer) {
      defer(() {
        defer(() => print('defer0 inside'));
        print('defer0');
      });
      defer(() {
        defer(() => print('defer1 inside'));
        print('defer1');
      });
      print('normal');
      return a + b;
    });

void main() => print(add(2, 3));
```

Output:

```text
normal
defer1
defer1 inside
defer0
defer0 inside
5
```

## Errors and `recover`

Every deferred action runs, even if the body or an earlier action throws.
If an error is still propagating after the last action, it is rethrown with
its original stack trace. When several errors are thrown, the last one
wins, as in Go.

Inside a deferred action, `defer.recover()` returns the error that is
currently propagating, or `null` if there is none. Its stack trace is
available from `defer.stackTrace`. Calling `recover()` does not stop the
error by itself; the action decides what happens next.

**Return a value instead of throwing** with `defer.returns(value)`:

```dart
int parseOr(String input, int fallback) => deferly((defer) {
      defer(() {
        if (defer.recover() is FormatException) defer.returns(fallback);
      });
      return int.parse(input);
    });

parseOr('42', 0); // 42
parseOr('oops', 0); // 0
```

**Replace the error** by throwing a different one:

```dart
Config loadConfig(String path) => deferly((defer) {
      defer(() {
        final error = defer.recover();
        if (error != null) throw ConfigException(path, error);
      });
      return Config.parse(File(path).readAsStringSync());
    });
```

**Leave it unchanged**, for example to only log it, by doing nothing else:

```dart
Future<void> sync() => deferlyAsync((defer) async {
      defer(() {
        final error = defer.recover();
        if (error != null) log.severe('sync failed', error, defer.stackTrace);
      });
      await upload();
    });
```

`defer.returns(value)` can also be called when there is no error, to
replace the value the body returned. If several actions call it, the last
call wins. For a `void` function, use `defer.returns(null)` to stop the
error.

> **Note:** unlike Go's `recover()`, `defer.recover()` only reads the
> error. Call `defer.returns(value)` to stop it. This way an error can only
> be swallowed when a value of the right type is supplied, so a function
> that returns `int` never ends up without one.

## Notes

- Use `deferlyAsync` for async bodies. With `deferly`, cleanup would run
  as soon as the `Future` is returned, before the async work finishes.
  The same applies to `sync*` and `async*` generators.
- Don't pass `async` actions to `deferly`. They compile, but are not
  awaited, and their errors are not reported to the caller. Use
  `deferlyAsync` instead.
- Deferred actions are closures, so they read variables when they run,
  not when they are registered. Copy a value into a `final` local first
  if you need the value at registration time.
- `defer`, `defer.recover()` and `defer.returns()` throw a `StateError`
  when they can't work: calling `defer` after the body and all of its
  actions have finished, or calling `recover()` or `returns()` when no
  deferred action is running, for example from the body.

## API reference

| Member | Description |
|---|---|
| `R deferly<R>(R Function(Defer<R> defer) body)` | Runs `body`, then its deferred actions in LIFO order. For sync code. |
| `Future<R> deferlyAsync<R>(Future<R> Function(AsyncDefer<R> defer) body)` | Same, for async code. Deferred actions may be async and are awaited one by one. |
| `defer(action)` | Registers a deferred action. `Defer` takes `void Function()`; `AsyncDefer` takes `FutureOr<void> Function()`. |
| `defer.recover()` | Inside a deferred action: the propagating error, or `null`. Does not stop it. |
| `defer.stackTrace` | The stack trace of the error returned by `recover()`, or `null`. |
| `defer.returns(value)` | Inside a deferred action: stops the propagating error, if any, and makes the function return `value`. |

Full API documentation is on [pub.dev](https://pub.dev/documentation/deferly/latest/).

## For AI agents

A compact, self-contained reference for LLMs and coding agents is available
in [`llms.txt`](https://github.com/a-h-mzd/deferly/blob/main/llms.txt). It
is also included in the published package, at the package root.
