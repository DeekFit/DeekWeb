// (c) 2022 Deeko Software LLC. This code is licensed under MIT license.

import 'dart:convert';
import 'package:deekweb/deekweb.dart';
import 'package:flutter/material.dart';

void main() => runApp(const ExampleApp());

/// Example app that shows making a request with `DeekWebClient` and parsing
/// the response.
class ExampleApp extends StatelessWidget {
  const ExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeekWeb Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ExampleAppHomePage(),
    );
  }
}

class ExampleAppHomePage extends StatefulWidget {
  const ExampleAppHomePage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ExampleAppHomePageState();
}

/// Sets up this widget as the listener for state changes in the
/// `DeekWebClient` by implemeting `DeekWebListener`
class _ExampleAppHomePageState extends State<ExampleAppHomePage>
    implements DeekWebListener {
  final DeekWebClient client = DeekWebClient();
  String status = "waiting";
  String response = "";

  @override
  void initState() {
    super.initState();

    // Add this class as a listener to the `DeekWebClient`
    client.addListener(this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(
            onPressed: () => startRequest(),
            child: const Text('Start GET request')),
        Text(status, style: const TextStyle(fontSize: 24)),
        Text(response, style: const TextStyle(fontSize: 16))
      ],
    )));
  }

  Future startRequest() async {
    setState(() => response = "");
    // First create your request
    var request = ExampleRequest(latitude: 39.2741349, longitude: -74.5760937);

    // Execute the request with the client
    var result = await client.executeRequest(request);

    // Check the parsed response
    if (result.data != null) {
      response = "ID: ${result.data!.id}, Type: ${result.data!.type}";
    } else {
      response = "null response";
    }
  }

  @override
  void requestCompleted({required String requestId, required int statusCode}) {
    setState(() => status = "Request completed, status code: $statusCode");
  }

  @override
  void requestCompletedWithError(
      {required String requestId, int? statusCode, String? error}) {
    setState(() => status = "Request error: ${error ?? "null"}");
  }

  @override
  void requestStarted(
      {required String requestId, required String requestType}) {
    setState(() => status = "Request started: $requestType");
  }
}

// Example of a simple GET request with a few URL parameters.
class ExampleRequest extends DeekWebRequest<ExampleData> {
  final double latitude;
  final double longitude;

  ExampleRequest({required this.latitude, required this.longitude});

  @override
  Method get method => Method.get;

  @override
  Uri get uri =>
      Uri.parse("https://api.weather.gov/points/$latitude,$longitude");

  @override
  Map<String, String> get headers => {"User-Agent": "DeekWebTestApp"};

  @override
  ExampleData? parseResponse(DeekWebHttpResponse response) {
    // Conditionally parse the response as JSON if the response was successful.
    if (response.statusCode == 200) {
      return ExampleData.fromJson(jsonDecode(response.body));
    } else {
      return null;
    }
  }
}

/// Simple model class that parses JSON data. You can also create more complex
/// versions of this with codegen from the `json_serializable` package.
class ExampleData {
  String id;
  String type;

  ExampleData.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        type = json['type'];
}
