import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack/core/storage/server_url_store.dart';
import 'package:meditrack/features/doses/dose_models.dart';

void main() {
  test('server address is normalised to the API base URL', () {
    expect(ServerUrlStore.normalize('my-svc.run.app'), 'https://my-svc.run.app/api/v1');
    expect(ServerUrlStore.normalize('https://my-svc.run.app/'), 'https://my-svc.run.app/api/v1');
    expect(ServerUrlStore.normalize('http://10.0.2.2:8000/api/v1'), 'http://10.0.2.2:8000/api/v1');
    expect(ServerUrlStore.normalize('   '), isNull);
  });

  test('delivery parses the simulated flag, defaulting to a real delivery', () {
    final base = {'contact_name': 'A', 'channel': 'ivr', 'status': 'sent', 'attempts': 1, 'last_error': null};
    expect(Delivery.fromJson({...base, 'simulated': true}).simulated, isTrue);
    expect(Delivery.fromJson(base).simulated, isFalse);
  });
}
