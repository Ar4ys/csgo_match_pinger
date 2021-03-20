import 'dart:io';
import 'dart:async';
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:stack_trace/stack_trace.dart' show Trace;
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart' show Dio, DioError;
import 'package:pedantic/pedantic.dart';

const csgoPath = 
  'C:/Program Files (x86)/Steam/'
  'steamapps/common/Counter-Strike Global Offensive/csgo/';
final csgoLogPath = p.join(csgoPath, 'console.log');
final csgoCfgPath = p.join(csgoPath, 'cfg/pinger.cfg');
final csgoAutoExecPath = p.join(csgoPath, 'cfg/autoexec.cfg');
final tokenPath = p.join(Platform.environment['UserProfile'], 'appdata/local/csgo-pinger');

final matchReadyRegex = RegExp(r'Received Steam datagram .+ match_id=.+');
final matchClosed = RegExp(r'SDR server .+ closed by peer');
final dio = Dio()
  ..options.baseUrl = 'http://localhost:6860';

String token;
bool isMatchFounded = false;

void main(List<String> arguments) =>
  runZonedGuarded(() => _main(arguments), globalErrorHandler);

var getChanges = createCahngesParser();

void _main(List<String> arguments) async {
  ProcessSignal.sigint.watch().listen((_) async {
    final isConfigCleared = await clearConfig();
    _exit(paused: !isConfigCleared);
  });

  if (!Platform.isWindows) {
    print('Sorry, only for Windows');
  }
  print('To exit press Ctrl + C');
  await retrieveToken();

  final file = File(csgoLogPath);
  await file
    .exists()
    .then((exists) async => exists ? await file.delete() : Future.value())
    .then(
      (e) async {
        await patchAutoExec();
        final config = File(csgoCfgPath);
        await config.create().catchError((_) {});
        await config.writeAsString('con_logfile console.log');
        print('Starting CSGO');
        await runCSGO();
        await waitForCSGO();
      },
      onError: (e) async {
        print(
          'Cannot remove csgo log file.\n'
          'Looks like csgo is alredy blocked it\n'
          //'To start pinger execute "start_pinger" command in CSGO console'
        );

        final lineCount = (await File(csgoLogPath).readAsLines()).length;
        getChanges = createCahngesParser(lineCount);
      })
    .then((_) async {
      final watcher = PollingDirectoryWatcher(
        p.dirname(csgoLogPath),
        pollingDelay: Duration(milliseconds: 100)
      );
      
      watcher.events
        .where((WatchEvent event) =>
          event.type == ChangeType.MODIFY && p.equals(csgoLogPath, event.path))
        .listen((WatchEvent event) async {
          for (final line in await getChanges(event.path)) {
            if (matchReadyRegex.hasMatch(line)) {
              isMatchFounded = true;
              unawaited(dio.post('/message', data: jsonEncode({
                'type': 'foundMatch',
                'token': token
              })));
            } else if (matchClosed.hasMatch(line) && isMatchFounded) {
              isMatchFounded = false;
              unawaited(dio.post('/message', data: jsonEncode({
                'type': 'missedMatch',
                'token': token
              })));
            }
          }
        });
    }).then((_) => print('Pinger initialized'));
}

Future<void> retrieveToken() async {
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
      await clearConfig();
      _exit(paused: true);
    } catch (e) {
      print(e);
      await clearConfig();
      _exit(paused: true);
    }
  }
  print('Token successfuly retrieved');
}

Future<void> runCSGO() async =>
  await Process.run('explorer', ['steam://rungameid/730']);

Future<void> patchAutoExec() async {
  const autoExecDefault = 
    '\nalias start_pinger "exec pinger.cfg"\n'
    'start_pinger';

  final autoexec = File(csgoAutoExecPath);
  if (await autoexec.exists()) {
    try {
      final content = await autoexec.readAsString();
      if (!content.contains('alias start_pinger')) {
        await autoexec.writeAsString(autoExecDefault, mode: FileMode.append);
      }
    } catch (e) {
      print(
        'Unable to check/patch autoexec.cfg, '
        "command 'start_pinger' may not work"
      );
    }
  } else {
    await autoexec.writeAsString(autoExecDefault);
  }
}
  

void globalErrorHandler(Object error, StackTrace stackTrace) async {
  await clearConfig();
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

Future<bool> clearConfig() async {
  final config = File(csgoCfgPath);
  try {
    await config.writeAsString('');
    return true;
  } catch (_) {
    print(
      'Unable to clear csgo-pinger config file.\n'
      'Make sure to clear it yourself, if you wont start this app again.'
    );
    return false;
  }
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

void _exit({ int code = 0, bool paused = false }) {
  if (paused) {
    print('Press any key to exit...');
    stdin.echoMode = false;
    stdin.lineMode = false;
    stdin.readByteSync();
  }
  exit(code);
}
