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

Future<int> addAsync(int a, int b) => deferlyAsync((defer) async {
      defer(() async {
        defer(() => print('async defer0 inside'));
        await Future.delayed(const Duration(milliseconds: 100));
        print('async defer0');
      });
      defer(() async {
        defer(() async {
          await Future.delayed(const Duration(milliseconds: 100));
          print('async defer1 inside');
        });
        print('async defer1');
      });
      await Future.delayed(const Duration(milliseconds: 100));
      print('async normal');
      return a + b;
    });

/// Returns [fallback] instead of throwing when [input] is not a number.
int parseOr(String input, int fallback) => deferly((defer) {
      defer(() {
        final error = defer.recover();
        if (error is FormatException) {
          print('recovered from: ${error.message}');
          defer.returns(fallback);
        }
      });
      return int.parse(input);
    });

Future<void> main() async {
  print(add(2, 3));
  print(await addAsync(2, 3));
  print(parseOr('42', 0));
  print(parseOr('oops', 0));
}
