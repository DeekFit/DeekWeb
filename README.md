# DeekWeb
DeekWeb is a strongly typed REST client for Flutter.

The goal of DeekWeb is to provide a mechanism to provide a consistent, strongly-typed web request framework. It gives you a mechanism to provide clean separation between your application's logic and the logic necessary to call a server and parse the results into classes.

DeekWebClient works well with [json_serializable](https://pub.dev/packages/json_serializable) as a framework for parsing your responses.

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

