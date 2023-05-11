import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  late MqttServerClient client;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  void initState() {
    super.initState();
    connect();
  }

  onConnected() {
    print(
        'MQTT::OnConnected client callback - Client connection was successful');
  }

  onDisconnected() {
    print('MQTT::OnDisconnected client callback - Client disconnection');
    if (client.connectionStatus!.disconnectionOrigin ==
        MqttDisconnectionOrigin.solicited) {
      print('MQTT::OnDisconnected callback is solicited, this is correct');
    } else {
      print(
          'MQTT::OnDisconnected callback is unsolicited or none, this is incorrect - exiting');
    }
  }

  onSubscribed(String topic) {
    print('MQTT::onSubscribed topic $topic');
  }

  onSubscribeFail(String topic) {
    print('MQTT::onSubscribeFail topic $topic');
  }

  onUnsubscribed(String? topic) {
    print('MQTT::onUnsubscribed topic $topic');
  }

  connect() async {
    String username = '70155dfbfd6143a895964cbb1f1c8ba9';
    String password = '30bb43898-4a43-4561-b92a-bbf12ffb9408';
    String clientId =
        'App.AwfFACuQ0mXKhHUriqHKn-70155dfbfd6143a895964cbb1f1c8ba9';
    String server = 'wss://test-azuremqtt.arnoo.com/mqtt';
    client = MqttServerClient(server, clientId);
    client.useWebSocket = true;
    client.port = 8443; // ws: 8043, wss: 8443, tcp: 1883, tls: 8883
    client.logging(on: true);
    client.setProtocolV311();
    client.keepAlivePeriod = 60; // 心跳间隔, 秒
    client.connectTimeoutPeriod = 10000; // 连接超时，毫秒
    client.onDisconnected = onDisconnected;
    client.onConnected = onConnected;
    client.onSubscribed = onSubscribed;
    client.onSubscribeFail = onSubscribeFail;
    client.onUnsubscribed = onUnsubscribed;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .withWillTopic('iot/v1/cb/$username/user/disconnect')
        .withWillMessage(
            '{"service":"user","method":"disconnect","srcAddr":"0.$username","payload":{"timestamp":${DateTime.now().millisecondsSinceEpoch}}}')
        .withWillQos(MqttQos.atLeastOnce)
        .startClean(); // Non persistent session for testing
    try {
      await client.connect(username, password);
    } on NoConnectionException catch (e) {
      // Raised by the client when connection fails.
      print('MQTT::client exception - $e');
      client.disconnect();
      return;
    } on SocketException catch (e) {
      // Raised by the socket layer
      print('MQTT::socket exception - $e');
      client.disconnect();
      return;
    } catch (e) {
      print('MQTT::catch exception - $e');
      client.disconnect();
      return;
    }

    /// Check we are connected
    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      print('MQTT::client connected');
    } else {
      /// Use status here rather than state if you also want the broker return code.
      print(
          'MQTT::client connection failed - disconnecting, status is ${client.connectionStatus}');
      client.disconnect();
      return;
    }

    client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      /// The above may seem a little convoluted for users only interested in the
      /// payload, some users however may be interested in the received publish message,
      /// lets not constrain ourselves yet until the package has been in the wild
      /// for a while.
      /// The payload is a byte buffer, this will be specific to the topic
      print(
          'MQTT::Change notification:: topic is <${c[0].topic}>, payload is <-- $pt -->');
      print('');
    });

    client.published!.listen((MqttPublishMessage message) {
      print(
          'MQTT::Published notification:: topic is ${message.variableHeader!.topicName}, with Qos ${message.header!.qos}');
    });

    // 发布用户上线消息
    String pubTopic = 'iot/v1/cb/$username/user/connect';
    final builder = MqttClientPayloadBuilder();
    builder.addString(
        '{"service":"user","method":"connect","payload":{"timestamp":${DateTime.now().millisecondsSinceEpoch}}}');
    client.publishMessage(pubTopic, MqttQos.atLeastOnce, builder.payload!);

    // 监听用户相关消息
    String subTopic = 'iot/v1/c/$username/#';
    client.subscribe(subTopic, MqttQos.atLeastOnce);
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Invoke "debug painting" (press "p" in the console, choose the
          // "Toggle Debug Paint" action from the Flutter Inspector in Android
          // Studio, or the "Toggle Debug Paint" command in Visual Studio Code)
          // to see the wireframe for each widget.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text(
              'You have pushed the button this many times:',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
