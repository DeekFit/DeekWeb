# DeekWeb
DeekWeb is a strongly typed REST client for Dart / Flutter.

The goal of DeekWeb is to provide a mechanism to provide a consistent, strongly-typed web request framework. It gives you a mechanism to provide clean separation between your application's logic and the logic necessary to call a server and parse the results into classes.

DeekWebClient works well with [json_serializable](https://pub.dev/packages/json_serializable) as a framework for parsing your responses.

## Why DeekWeb?

One of the primary advantages to using Dart / Flutter over other frameworks is that its a modern, strongly-typed, null-safe framework. So shouldn't your network access have the same benefits?

DeekWeb gives you the advantage of predefining your contracts once, and using them where you need them, keeping your logic clean, safe, and readable.

## Getting Started

First, defined a request by extending **DeekWebRequest**.

```dart
class MyRequest extends DeekWebRequest<MyResponseType> {
  @override
  Method get method => Method.get;

  @override
  Uri get uri => Uri.parse("https://www.myserver.com/myendpoint");

  @override
  Map<String, String> get headers {
    return {
      "someHeader": "someValue"
    };
  }

  @override
  Response<MyResponseType>? parseResponse(DeekWebHttpResponse response) {
    if (response.statusCode == 200) {
      var decoded = jsonDecode(response.body);
      return MyResponseType.fromJson(decoded);
    } else {
      return null;  
    }
  }      
}
```

Then, execute your request with **DeekWebClient**:
```dart
Future<MyResponseType> getResponse() async {
  var request = MyRequest();  
  var client = DeekWebClient();
  var response = await client.executeRequest(request);
  return response;
}
```

## Advanced Features

### Logging

You can pass a logger class to your `DeekWebClient` class. The client will log various events and changes throughout the request. Raw request/responses will not be logged.

```dart
class MyLogger implements DeekWebLogger {
  verbose(String logLine) => print(logline);
  info(String logLine) => print(logline);
  warn(String logLine) => print(logline);
  error(String logLine, {Exception? e}) => print("$logline: ${e ?? 'null'}");
}

void makeRequest() {
  var client = DeekWebClient(logger: MyLogger());
  /// execute requests like normal
}
```

### Correletion Vectors

`DeekWebClient` already generates a unique ID for each request. Want to include that in your request headers? [Correletion Vectors](https://github.com/microsoft/CorrelationVector) can be a powerful debugging tool to send an ID from client to server and use to track requests through logs across systems.

If you want to include your requestId as a header, specify so in the `DeekWebClient` constructor.

```dart
void makeRequest() {
  var client = DeekWebClient(includeCvHeader: true, cvHeader: 'My-CV');
  /// execute requests like normal
}
```

### Listeners

You may find it useful to know what requests are running and their status. For example, your app my display a sync indicator when a request is in progress. You can hook up a listener to your `DeekWebClient` that will notify you when a request starts/completes:

```dart
class MyListener implements DeekWebListener {
  @override
  void requestCompleted({required String requestId, required int statusCode}) {
    /// Do something when requests complete
  }

  @override
  void requestCompletedWithError(
      {required String requestId, int? statusCode, String? error}) {
    /// Do something when requests fail
  }

  @override
  void requestStarted(
      {required String requestId, required String requestType}) {
    /// Do something when requests start
  }
}

void makeRequest(MyListener requestListener) {
  var client = DeekWebClient(listener: requestListener);
  /// execute requests like normal
}
```