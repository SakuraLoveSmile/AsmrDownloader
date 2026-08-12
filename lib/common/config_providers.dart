import 'package:asmr_downloader/utils/json_storage.dart';
import 'package:asmr_downloader/utils/tool_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

final configFileProvider = Provider<JsonStorage>((ref) {
  return JsonStorage(
    filePath: p.join(getAppDataDir(), 'asmr_dl_config.json'),
  );
});

final downloadPathProvider = StateProvider<String>((ref) => '');

final dlCoverProvider = StateProvider<bool>((ref) => false);

final proxyProvider = StateProvider<String>((ref) => 'DIRECT');

final apiChannelProvider = StateProvider<String>((ref) => 'asmr-200');
