import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'src/rust/api.dart';
import 'src/rust/frb_generated.dart';
import 'state/node_controller.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final settings = await AppSettings.load();
  String? rustError;
  try {
    await _initRust();
  } catch (error) {
    rustError = error.toString();
    debugPrint('kinly: could not load the Rust core: $error');
  }

  var dataDir = '';
  String? knownName;
  if (rustError == null) {
    try {
      final support = await getApplicationSupportDirectory();
      dataDir = '${support.path}${Platform.pathSeparator}kinly';
      await Directory(dataDir).create(recursive: true);
      knownName = await loadName(dataDir: dataDir);
    } catch (error) {
      rustError = error.toString();
      debugPrint('kinly: data directory failed: $error');
    }
  }

  final controller = NodeController(settings);
  runApp(
    KinlyApp(
      settings: settings,
      controller: controller,
      dataDir: dataDir,
      knownName: knownName,
      initError: rustError,
    ),
  );
}

/// Loads `libkinly_core` from the bundle, the dev build directory or a path
/// supplied with `--dart-define=KINLY_LIB=...`.
Future<void> _initRust() async {
  final candidates = <String>[
    const String.fromEnvironment('KINLY_LIB'),
    if (Platform.isAndroid) 'libkinly_core.so',
    _nextToExecutable(),
    '../core/target/release/libkinly_core.so',
    '../core/target/debug/libkinly_core.so',
    'core/target/release/libkinly_core.so',
    'core/target/debug/libkinly_core.so',
    if (Platform.isMacOS) '../core/target/release/libkinly_core.dylib',
    if (Platform.isWindows) '../core/target/release/kinly_core.dll',
  ].where((path) => path.isNotEmpty).toList();

  Object? lastError;
  for (final path in candidates) {
    try {
      final library = ExternalLibrary.open(path);
      await RustLib.init(externalLibrary: library);
      return;
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('libkinly_core not found (${lastError ?? 'no candidate'})');
}

String _nextToExecutable() {
  final executable = File(Platform.resolvedExecutable);
  final dir = executable.parent.path;
  final name = Platform.isWindows ? 'kinly_core.dll' : 'libkinly_core.so';
  return '$dir${Platform.pathSeparator}lib${Platform.pathSeparator}$name';
}
