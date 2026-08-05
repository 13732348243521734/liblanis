/// Deprecated entrypoint — use [capture_matrix.dart] for the fixture matrix.
///
/// ```sh
/// dart run tool/substitutions/capture_matrix.dart
/// ```
library;

import 'dart:io';

Future<void> main(List<String> args) async {
  stderr.writeln(
    'tool/substitutions/generate_permutations.dart is retired.\n'
    'Use: dart run tool/substitutions/capture_matrix.dart\n'
    'See tool/substitutions/discovery/CAPTURE.md',
  );
  exitCode = 2;
}
