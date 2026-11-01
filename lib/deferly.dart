/// Go-style `defer` and `recover` for Dart.
///
/// Wrap a function's body with [deferly] or [deferlyAsync] to register
/// cleanup actions that run in reverse order (LIFO) when the body exits,
/// whether it returns normally or throws. Deferred actions can inspect the
/// error that is propagating with [Defer.recover] and replace it with a
/// return value using [Defer.returns].
library deferly;

import 'dart:async';

/// Registers deferred actions for the enclosing [deferly] body, and lets
/// those actions inspect and handle the error that is propagating.
///
/// Call it like a function to register an action: `defer(file.closeSync)`.
///
/// Instances are created by [deferly] and passed to its body.
abstract class Defer<R> {
  const Defer._(); // coverage:ignore-line

  /// Registers [action] to run when the enclosing [deferly] body exits.
  ///
  /// Actions run in reverse registration order. An action may register
  /// more actions; they run right after it, before earlier actions.
  ///
  /// Throws a [StateError] if called after the body and all of its deferred
  /// actions have finished, since [action] could never run.
  void call(void Function() action);

  /// Returns the error that is currently propagating, or `null` if there is
  /// none.
  ///
  /// The error is the one thrown by the body, or by a deferred action that
  /// ran earlier, whichever was thrown last. Its stack trace is available
  /// from [stackTrace].
  ///
  /// Calling [recover] does not stop the error. After inspecting it, a
  /// deferred action can:
  ///
  /// * call [returns] to stop the error and return a value instead,
  /// * throw a different error to replace it, or
  /// * do nothing (for example, only log it) to let it keep propagating.
  ///
  /// ```dart
  /// int parseOr(String input, int fallback) => deferly((defer) {
  ///   defer(() {
  ///     final error = defer.recover();
  ///     if (error is FormatException) defer.returns(fallback);
  ///   });
  ///   return int.parse(input);
  /// });
  /// ```
  ///
  /// Throws a [StateError] if no deferred action is running, for example
  /// when called from the body.
  Object? recover();

  /// The stack trace of the error returned by [recover], or `null` if there
  /// is no error propagating.
  StackTrace? get stackTrace;

  /// Makes the enclosing function return [value] and stops the error that
  /// is propagating, if any.
  ///
  /// If the body returned normally, [value] replaces its result. If several
  /// actions call [returns], the last call wins. A deferred action that
  /// throws after [returns] was called makes the function throw again.
  ///
  /// For a `void` function, call `returns(null)` to stop the error.
  ///
  /// Throws a [StateError] if no deferred action is running, for example
  /// when called from the body.
  void returns(R value);
}

/// Async version of [Defer], used by [deferlyAsync].
///
/// Deferred actions may be async; each one is awaited before the next runs.
///
/// Instances are created by [deferlyAsync] and passed to its body.
abstract class AsyncDefer<R> {
  const AsyncDefer._(); // coverage:ignore-line

  /// Registers [action], which may be async, to run when the enclosing
  /// [deferlyAsync] body exits.
  ///
  /// See [Defer.call].
  void call(FutureOr<void> Function() action);

  /// Returns the error that is currently propagating, or `null` if there is
  /// none, without stopping it.
  ///
  /// See [Defer.recover].
  Object? recover();

  /// The stack trace of the error returned by [recover], or `null` if there
  /// is no error propagating.
  StackTrace? get stackTrace;

  /// Makes the enclosing function return [value] and stops the error that
  /// is propagating, if any.
  ///
  /// See [Defer.returns].
  void returns(R value);
}

/// Runs [body] and then runs every action registered with `defer`, in
/// reverse registration order.
///
/// Deferred actions run whether [body] returns or throws, and every action
/// runs even if an earlier one throws. If an error is still propagating
/// after the last action, it is rethrown; when several errors were thrown,
/// the last one wins, as in Go. Actions can inspect the error with
/// [Defer.recover] and replace it with a return value using
/// [Defer.returns].
///
/// Wrap the body rather than the function, so the function keeps its own
/// signature and full static typing:
///
/// ```dart
/// String read(String path) => deferly((defer) {
///   final file = File(path).openSync();
///   defer(file.closeSync);
///   return utf8.decode(file.readSync(file.lengthSync()));
/// });
/// ```
///
/// For bodies that return a [Future], use [deferlyAsync] instead.
R deferly<R>(R Function(Defer<R> defer) body) {
  final scope = _Scope<R>();
  try {
    scope._result = body(scope);
  } catch (error, stackTrace) {
    // Remaining actions run inside this catch clause so that, if the error
    // is still propagating at the end, `rethrow` keeps its stack trace.
    final id = scope._fail(error, stackTrace);
    _runSync(scope);
    if (scope._isPending(id)) rethrow;
    return scope._result;
  }
  _runSync(scope);
  return scope._result;
}

/// Async version of [deferly].
///
/// Waits for [body] to complete, then runs and awaits every action
/// registered with `defer`, in reverse registration order. Actions may be
/// sync or async, may register nested actions, and can use
/// [AsyncDefer.recover] and [AsyncDefer.returns] like in [deferly].
///
/// ```dart
/// Future<String> fetch(Uri url) => deferlyAsync((defer) async {
///   final client = HttpClient();
///   defer(client.close);
///   final request = await client.getUrl(url);
///   final response = await request.close();
///   return response.transform(utf8.decoder).join();
/// });
/// ```
Future<R> deferlyAsync<R>(Future<R> Function(AsyncDefer<R> defer) body) async {
  final scope = _Scope<R>();
  try {
    scope._result = await body(scope);
  } catch (error, stackTrace) {
    scope._fail(error, stackTrace);
  }
  scope._phase = _Phase.cleanup;
  while (scope._actions.isNotEmpty) {
    try {
      await scope._actions.removeLast()();
    } catch (error, stackTrace) {
      scope._fail(error, stackTrace);
    }
  }
  scope._phase = _Phase.done;
  final error = scope._error;
  if (error != null) return Future<R>.error(error, scope._stackTrace);
  return scope._result;
}

/// Runs the remaining actions of [scope]. Each action that throws records
/// its error, and the actions after it run inside its catch clause, so the
/// error can be rethrown with its original stack trace if it is still
/// propagating once every action has run.
void _runSync(_Scope<Object?> scope) {
  scope._phase = _Phase.cleanup;
  while (scope._actions.isNotEmpty) {
    final action = scope._actions.removeLast();
    try {
      action();
    } catch (error, stackTrace) {
      final id = scope._fail(error, stackTrace);
      _runSync(scope);
      if (scope._isPending(id)) rethrow;
      return;
    }
  }
  scope._phase = _Phase.done;
}

enum _Phase { body, cleanup, done }

class _Scope<R> implements Defer<R>, AsyncDefer<R> {
  final _actions = <FutureOr<void> Function()>[];
  var _phase = _Phase.body;
  Object? _error;
  StackTrace? _stackTrace;
  var _errorId = 0;
  late R _result;

  @override
  void call(FutureOr<void> Function() action) {
    if (_phase == _Phase.done) {
      throw StateError(
        'defer() was called after the body and all of its deferred actions '
        'finished, so the action would never run. Register deferred actions '
        'from the body or from another deferred action.',
      );
    }
    _actions.add(action);
  }

  @override
  Object? recover() {
    _checkCleanup('recover');
    return _error;
  }

  @override
  StackTrace? get stackTrace => _stackTrace;

  @override
  void returns(R value) {
    _checkCleanup('returns');
    _error = null;
    _stackTrace = null;
    _result = value;
  }

  void _checkCleanup(String method) {
    if (_phase != _Phase.cleanup) {
      throw StateError(
        '$method() can only be called while deferred actions are running.',
      );
    }
  }

  /// Records [error] as the one propagating and returns an id for it.
  int _fail(Object error, StackTrace stackTrace) {
    _error = error;
    _stackTrace = stackTrace;
    return ++_errorId;
  }

  /// Whether the error recorded with [id] is still the one propagating.
  bool _isPending(int id) => _error != null && _errorId == id;
}
