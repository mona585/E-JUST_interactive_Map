import 'package:flutter/foundation.dart';

/// PHASE 15 observability contract: one stable, CI-parseable line format.
///
/// Line shape (space-separated key=value tokens after the `[NAV]` prefix):
///
///     EVENT=NAME  sid=ID  rev=N  dst=PUID  bldg=B-or-dash
///                 flr=F-or-dash  src=gps|wifi|dash  detail=...
///
/// Tests may swap [navigationLog] to capture the stream; production defaults
/// to debugPrint. Verbose events are gated by kDebugMode at emission sites;
/// SESSION_START / SESSION_END / TERMINATE / ARRIVAL always log.
typedef NavigationLogFn = void Function(String line);

NavigationLogFn navigationLog = (line) => debugPrint(line);