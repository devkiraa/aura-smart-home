import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/broker.dart';

class MQTTManager {
  // Private constructor
  MQTTManager._privateConstructor();

  // Singleton instance
  static final MQTTManager _instance = MQTTManager._privateConstructor();

  // Factory constructor to return the singleton instance
  factory MQTTManager() {
    return _instance;
  }

  final MqttClient client = MqttClient.withPort(
      '2b3bee44d0f3453280249ee38fb5192f.s1.eu.hivemq.cloud', // Replace with your server URL
      'AuraAppClient_${DateTime.now().millisecondsSinceEpoch}',
      8883);

  Future<void> connect() async {
    client.secure = true;
    client.securityContext = SecurityContext.defaultSecurityContext;
    client.logging(on: true);
    client.keepAlivePeriod = 60;
    client.onConnected = onConnected;
    client.onDisconnected = onDisconnected;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(client.clientIdentifier)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMessage;

    try {
      await client.connect('Kiraa', 'M1670529m'); // Replace with your credentials
    } catch (e) {
      print('Exception: $e');
      client.disconnect();
    }
  }

  void onConnected() {
    print('MQTT Client connected!');
  }

  void onDisconnected() {
    print('MQTT Client disconnected');
  }

  void publish(String topic, String message) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(message);
    client.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }
}