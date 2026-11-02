/// Legacy account JSON field only — Seerr product surface removed (Phase 2).
/// Kept so stored accounts still deserialize; [isConfigured] is always false.
class SeerrCredentialsModel {
  final String serverUrl;
  final String apiKey;
  final String sessionCookie;
  final Map<String, String> customHeaders;

  const SeerrCredentialsModel({
    this.serverUrl = '',
    this.apiKey = '',
    this.sessionCookie = '',
    this.customHeaders = const {},
  });

  bool get isConfigured => false;

  bool get useProxy => false;

  factory SeerrCredentialsModel.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const SeerrCredentialsModel();
    final headersRaw = json['customHeaders'];
    final headers = <String, String>{};
    if (headersRaw is Map) {
      headersRaw.forEach((key, value) {
        if (key != null && value != null) {
          headers['$key'] = '$value';
        }
      });
    }
    return SeerrCredentialsModel(
      serverUrl: (json['serverUrl'] as String?) ?? '',
      apiKey: (json['apiKey'] as String?) ?? '',
      sessionCookie: (json['sessionCookie'] as String?) ?? '',
      customHeaders: headers,
    );
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'apiKey': apiKey,
        'sessionCookie': sessionCookie,
        'customHeaders': customHeaders,
      };

  SeerrCredentialsModel copyWith({
    String? serverUrl,
    String? apiKey,
    String? sessionCookie,
    Map<String, String>? customHeaders,
  }) {
    return SeerrCredentialsModel(
      serverUrl: serverUrl ?? this.serverUrl,
      apiKey: apiKey ?? this.apiKey,
      sessionCookie: sessionCookie ?? this.sessionCookie,
      customHeaders: customHeaders ?? this.customHeaders,
    );
  }
}

/// Freezed nested copyWith shim expected by [AccountModel] generated code.
class $SeerrCredentialsModelCopyWith<$Res> {
  $SeerrCredentialsModelCopyWith(this._value, this._then);

  final SeerrCredentialsModel _value;
  final $Res Function(SeerrCredentialsModel) _then;

  $Res call({
    Object? serverUrl = const _Unset(),
    Object? apiKey = const _Unset(),
    Object? sessionCookie = const _Unset(),
    Object? customHeaders = const _Unset(),
  }) {
    return _then(
      _value.copyWith(
        serverUrl: serverUrl is _Unset ? null : serverUrl as String?,
        apiKey: apiKey is _Unset ? null : apiKey as String?,
        sessionCookie: sessionCookie is _Unset ? null : sessionCookie as String?,
        customHeaders: customHeaders is _Unset ? null : customHeaders as Map<String, String>?,
      ),
    );
  }
}

class _Unset {
  const _Unset();
}
