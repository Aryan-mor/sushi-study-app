import 'package:http/http.dart' as http;

http.Client createAppHttpClient({http.Client? inner}) => inner ?? http.Client();

http.Client? _sharedAppHttpClient;

http.Client get appHttpClient => _sharedAppHttpClient ??= createAppHttpClient();
