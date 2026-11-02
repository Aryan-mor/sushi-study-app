/// Regional-indicator flag for an ISO code. Iran is omitted: the title page uses the
/// lion-and-sun asset instead of the current flag emoji.
String? sushiCountryFlagEmoji(String? iso) {
  final code = iso?.trim().toUpperCase() ?? '';
  if (code.length != 2 || code == 'IR' || code == '-') return null;
  final a = code.codeUnitAt(0);
  final b = code.codeUnitAt(1);
  if (a < 0x41 || a > 0x5A || b < 0x41 || b > 0x5A) return null;
  return String.fromCharCodes([0x1F1E6 + a - 0x41, 0x1F1E6 + b - 0x41]);
}

/// Display name for a TMDB origin country (ISO 3166-1 alpha-2).
///
/// Unknown codes fall back to the code itself so a rare country still shows.
String? sushiOriginCountryLabel(String? iso, String languageCode) {
  final code = iso?.trim().toUpperCase() ?? '';
  if (code.length != 2 || code == '-') return null;
  if (languageCode == 'fa') {
    return _fa[code] ?? _en[code] ?? code;
  }
  return _en[code] ?? code;
}

const _en = <String, String>{
  'AE': 'United Arab Emirates',
  'AR': 'Argentina',
  'AT': 'Austria',
  'AU': 'Australia',
  'BE': 'Belgium',
  'BR': 'Brazil',
  'CA': 'Canada',
  'CH': 'Switzerland',
  'CL': 'Chile',
  'CN': 'China',
  'CO': 'Colombia',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DK': 'Denmark',
  'EG': 'Egypt',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'GB': 'United Kingdom',
  'GR': 'Greece',
  'HK': 'Hong Kong',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IN': 'India',
  'IR': 'Iran',
  'IT': 'Italy',
  'JP': 'Japan',
  'KR': 'South Korea',
  'MA': 'Morocco',
  'MX': 'Mexico',
  'NG': 'Nigeria',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NZ': 'New Zealand',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PT': 'Portugal',
  'RU': 'Russia',
  'SA': 'Saudi Arabia',
  'SE': 'Sweden',
  'TH': 'Thailand',
  'TR': 'Turkey',
  'TW': 'Taiwan',
  'US': 'United States',
  'ZA': 'South Africa',
};

const _fa = <String, String>{
  'AE': 'امارات',
  'AR': 'آرژانتین',
  'AT': 'اتریش',
  'AU': 'استرالیا',
  'BE': 'بلژیک',
  'BR': 'برزیل',
  'CA': 'کانادا',
  'CH': 'سوئیس',
  'CL': 'شیلی',
  'CN': 'چین',
  'CO': 'کلمبیا',
  'CZ': 'چک',
  'DE': 'آلمان',
  'DK': 'دانمارک',
  'EG': 'مصر',
  'ES': 'اسپانیا',
  'FI': 'فنلاند',
  'FR': 'فرانسه',
  'GB': 'بریتانیا',
  'GR': 'یونان',
  'HK': 'هنگ‌کنگ',
  'HU': 'مجارستان',
  'ID': 'اندونزی',
  'IE': 'ایرلند',
  'IL': 'اسرائیل',
  'IN': 'هند',
  'IR': 'ایران',
  'IT': 'ایتالیا',
  'JP': 'ژاپن',
  'KR': 'کره جنوبی',
  'MA': 'مراکش',
  'MX': 'مکزیک',
  'NG': 'نیجریه',
  'NL': 'هلند',
  'NO': 'نروژ',
  'NZ': 'نیوزیلند',
  'PH': 'فیلیپین',
  'PK': 'پاکستان',
  'PL': 'لهستان',
  'PT': 'پرتغال',
  'RU': 'روسیه',
  'SA': 'عربستان',
  'SE': 'سوئد',
  'TH': 'تایلند',
  'TR': 'ترکیه',
  'TW': 'تایوان',
  'US': 'آمریکا',
  'ZA': 'آفریقای جنوبی',
};
