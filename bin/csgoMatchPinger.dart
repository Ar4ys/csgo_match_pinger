import 'dart:io';
import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart' show Dio, DioError;
import 'package:pedantic/pedantic.dart';

//const csgoLogPath = 'C:\\Program Files (x86)\\Steam\\steamapps\\common\\Counter-Strike Global Offensive\\csgo\\console.log';
const csgoLogPath = 'C:/test/test.txt';
const csgoCfgPath = 'C:/test/test.cfg';
final tokenPath = p.join(Platform.environment['UserProfile'], 'appdata/local/csgo-pinger');

final matchReadyRegex = RegExp(r'ready');
final matchClosed = RegExp(r'closed');
final dio = Dio()
  ..options.baseUrl = 'http://localhost:6860';

String token;

void main(List<String> arguments) =>
  runZonedGuarded(() => _main(arguments), globalErrorHandler);

var getChanges = createCahngesParser();

void _main(List<String> arguments) async {
  if (!Platform.isWindows) {
    print('Sorry, only for Windows');
  }
  print('To exit press Ctrl + C');

  final tokenFile = File(tokenPath);
  if (await tokenFile.exists()) {
    token = await tokenFile.readAsString();
  } else {
    stdout.write('Enter passcode: ');
    final passcode = stdin.readLineSync(retainNewlines: true);
    try {
      final response = await dio.get('/token/$passcode');
      final token = jsonDecode(response.toString())['token'];
      await tokenFile.writeAsString(token);
    } on DioError catch(error) {
      final responseData = error.response.toString();
      final reason = jsonDecode(responseData)['reason'];
      print(reason);
      pauseExit();
    } catch (e) {
      print(e);
      pauseExit();
    }
  }

  final file = File(csgoLogPath);
  await file
    .exists()
    .then((exists) async => exists ? await file.delete() : Future.value())
    .then(
      (e) async {
        final config = File(csgoCfgPath);
        await config.create().catchError((_) {});
        await config.writeAsString('startPinger');
        await waitForCSGO();
      },
      onError: (e) async {
        print(
          'Cannot remove csgo log file. '
          'Looks like csgo is alredy blocked it'
        );

        final lineCount = (await File(csgoLogPath).readAsLines()).length;
        getChanges = createCahngesParser(lineCount);
      })
    .then((_) async {
      final watcher = DirectoryWatcher(p.dirname(csgoLogPath));
      watcher.events
        .where((WatchEvent event) =>
          event.type == ChangeType.MODIFY && p.equals(csgoLogPath, event.path))
        .listen((WatchEvent event) async {
          for (final line in await getChanges(event.path)) {
            if (matchReadyRegex.hasMatch(line)) {
              unawaited(dio.post('/message', data: jsonEncode({
                'type': 'foundMatch',
                'token': token
              })));
            } else if (matchClosed.hasMatch(line)) {
              unawaited(dio.post('/message', data: jsonEncode({
                'type': 'missedMatch',
                'token': token
              })));
            }
          }
        });
    });
}

void globalErrorHandler(Object error, StackTrace stackTrace) {
  final timeRegexp = RegExp(r'T(.+)\.');
  final prettyStackTrace = Trace.format(stackTrace);
  final date = DateTime.now().toIso8601String();
  final prettyTime = timeRegexp.firstMatch(date).group(1);
  print(
    '[$prettyTime] $error\n'
    '$prettyStackTrace'
  );
}

Future<void> waitForCSGO() async {
  final watcher = DirectoryWatcher(p.dirname(csgoLogPath));
  await watcher.events
    .firstWhere((WatchEvent event) =>
      event.type == ChangeType.ADD && p.equals(csgoLogPath, event.path)
  );
}

typedef _parser = Future<Iterable<String>> Function(String path);

_parser createCahngesParser([ int lastLine = 0 ]) {
  return (String path) async {
    final file = File(path);
    final lines = await file.readAsLines();
    final changes = lines.getRange(lastLine, lines.length);
    lastLine = lines.length;
    return changes;
  };
}

void pauseExit() {
  print('Press any key to exit...');
  stdin.echoMode = false;
  stdin.lineMode = false;
  stdin.readByteSync();
  exit(0);
}
