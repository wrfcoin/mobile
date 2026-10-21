import 'package:flutter_test/flutter_test.dart';
import 'package:wrfcoin_mobile/services/background/sync_worker.dart';

void main() {
  group('SyncWorker', () {
    late SyncWorker worker;

    setUp(() {
      worker = SyncWorker();
    });

    test('backoffDelay doubles with each attempt', () {
      expect(worker.backoffDelay(0), const Duration(seconds: 1));
      expect(worker.backoffDelay(1), const Duration(seconds: 2));
      expect(worker.backoffDelay(2), const Duration(seconds: 4));
      expect(worker.backoffDelay(3), const Duration(seconds: 8));
      expect(worker.backoffDelay(4), const Duration(seconds: 16));
    });

    test('maxBatchSize is 50', () {
      expect(SyncWorker.maxBatchSize, 50);
    });

    test('maxRetries is 5', () {
      expect(SyncWorker.maxRetries, 5);
    });
  });
}
