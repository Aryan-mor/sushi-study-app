final _tokenShape = RegExp(r'^\d{6,}:[A-Za-z0-9_-]{20,}$');

bool sushiLooksLikeBotToken(String text) => _tokenShape.hasMatch(text.trim());
