// Native platforms provide dart:io and real isolates; Web compilers do not.
export 'background_inline.dart' if (dart.library.io) 'background_isolate.dart';
