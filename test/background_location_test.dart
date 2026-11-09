import 'package:background_location/background_location.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.almoullim.background_location/methods');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('getCurrentLocation requests a native location fix', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      expect(methodCall.method, 'get_current_location');
      return <String, dynamic>{
        'latitude': 1.0,
        'longitude': 2.0,
        'altitude': 3.0,
        'accuracy': 4.0,
        'bearing': 5.0,
        'speed': 6.0,
        'time': 7.0,
        'is_mock': false,
      };
    });

    final location = await BackgroundLocation().getCurrentLocation();

    expect(location.latitude, 1.0);
    expect(location.longitude, 2.0);
    expect(location.time, 7.0);
    expect(location.isMock, isFalse);
  });
}
