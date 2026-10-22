import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/data/storage/download_jobs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'active downloads persist and paused downloads leave the queue',
    () async {
      await DownloadJobs.add('model-a');
      await DownloadJobs.add('embedding:embeddinggemma-300m-q8');
      expect(
        await DownloadJobs.active(),
        containsAll(['model-a', 'embedding:embeddinggemma-300m-q8']),
      );
      await DownloadJobs.remove('model-a');
      expect(await DownloadJobs.active(), {'embedding:embeddinggemma-300m-q8'});
    },
  );

  test('concurrent changes do not lose a job', () async {
    await Future.wait([
      DownloadJobs.add('one'),
      DownloadJobs.add('two'),
      DownloadJobs.add('three'),
    ]);
    expect(await DownloadJobs.active(), {'one', 'two', 'three'});
  });
}
