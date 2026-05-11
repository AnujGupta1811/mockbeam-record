/// MockBeam Record — programmatic API for embedding the proxy in other tools.
///
/// For CLI use, run `mockbeam_record record --target <url>` directly.
library mockbeam_record;

export 'src/proxy_server.dart';
export 'src/request_forwarder.dart';
export 'src/route_store.dart';
export 'src/route_serializer.dart';
export 'src/response_capture.dart';
