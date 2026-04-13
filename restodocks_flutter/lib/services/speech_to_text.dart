export 'speech_to_text_stub.dart'
    if (dart.library.html) 'speech_to_text_web.dart'
    if (dart.library.io) 'speech_to_text_io.dart';
