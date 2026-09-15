import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = File(
    'test/fixtures/fonts/PlusJakartaSans.ttf',
  ).readAsBytesSync();
  // Register under the default test theme as well as the actual font name.
  // Ahem's square glyphs otherwise create artificial household-card overflows.
  for (final family in ['Roboto', 'PlusJakartaSans']) {
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
  await testMain();
}
