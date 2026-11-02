import 'package:flutter/material.dart';
import 'package:fladder/sushi/sushi_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public news / support channel. `?direct` opens the chat in Telegram.
const sushiSupportChannelUrl = 'https://t.me/${SushiConfig.supportChannelUsername}?direct';

/// EN + FA copy (R-I18N-1). Other locales fall back to English.
class SushiDmcaCopy {
  const SushiDmcaCopy(this._fa);

  factory SushiDmcaCopy.of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return SushiDmcaCopy(code.toLowerCase().startsWith('fa'));
  }

  final bool _fa;

  String get button => 'DMCA';
  String get support => _fa ? 'پشتیبانی' : 'Support';
  String get title => _fa ? 'سیاست DMCA' : 'DMCA Policy';
  String get lead => _fa
      ? 'سوشی به هر اخطار معتبر نقض حق نشر پاسخ می‌دهد.'
      : 'Sushi responds to every valid copyright notice.';
  String get intro => _fa
      ? 'سوشی طبق قانون حق نشر هزاره دیجیتال (DMCA، بند ۵۱۲ عنوان ۱۷ قانون ایالات متحده) و سایر قوانین مالکیت فکری عمل می‌کند. اگر اثر دارای حق نشر شما در سوشی منتشر شده و می‌خواهید حذف شود، اخطار کتبی بفرستید که همه موارد زیر را داشته باشد. اگر اطلاعات نادرست بدهید، ممکن است مسئول خسارت، از جمله هزینه و حق‌الوکاله، باشید. پیش از ارسال، با یک وکیل مشورت کنید.'
      : 'Sushi follows the Digital Millennium Copyright Act (17 U.S.C. § 512) and other applicable intellectual-property law. If your copyrighted work appears in Sushi and you want it removed, send a written notice that includes every item below. A false statement can make you liable for damages, including costs and attorney fees. Talk to a lawyer before you send a notice.';
  String get requiredHeading => _fa
      ? 'اخطار نقض حق نشر باید این‌ها را داشته باشد:'
      : 'A copyright notice must include:';
  List<String> get required => _fa
      ? const [
          'مدرک اینکه فرستنده مجاز است از طرف صاحب حق انحصاری که ادعا می‌شود نقض شده اقدام کند.',
          'راه تماس کافی، از جمله یک ایمیل معتبر.',
          'مشخصات دقیق اثر دارای حق نشر، و دست‌کم یک عنوان که با آن اثر در سوشی پیدا می‌شود.',
          'اظهار اینکه شاکی با حسن نیت باور دارد استفاده از اثر، به شکلی که شکایت شده، بدون اجازه صاحب حق، نماینده او، یا قانون است.',
          'اظهار اینکه اطلاعات اخطار درست است و، با علم به مجازات شهادت دروغ، فرستنده مجاز است از طرف صاحب حق انحصاری اقدام کند.',
          'امضای شخص مجاز به اقدام از طرف صاحب حق.',
        ]
      : const [
          'Evidence that you are authorized to act for the owner of the exclusive right that is allegedly infringed.',
          'Contact details we can use to reach you, including a valid email address.',
          'Enough detail to identify the copyrighted work, and at least one title under which it appears in Sushi.',
          'A statement that you have a good-faith belief the use is not authorized by the copyright owner, its agent, or the law.',
          'A statement that the notice is accurate and, under penalty of perjury, that you are authorized to act for the owner of the exclusive right.',
          'Your signature, as the person authorized to act for the owner.',
        ];
  String get send => _fa
      ? 'اخطار کتبی را در تلگرام به @${SushiConfig.supportChannelUsername} بفرستید.'
      : 'Send the written notice on Telegram to @${SushiConfig.supportChannelUsername}.';
  String get links => _fa
      ? 'فقط با یک عبارت جستجو نمی‌توان تضمین کرد همه نسخه‌ها حذف شوند. برای هر عنوان، لینک مستقیم و قابل کلیک بفرستید. فقط در این صورت حذف همه موارد تضمین می‌شود.'
      : 'A search term alone does not guarantee every copy is removed. Send a clickable direct link for each title. Only then can we guarantee removal of all of them.';
  String get timing => _fa
      ? 'پاسخ ایمیل یا پیام معمولاً ۱ تا ۳ روز کاری طول می‌کشد. فرستادن همان شکایت به میزبان یا ارائه‌دهنده اینترنت درخواست را سریع‌تر نمی‌کند و ممکن است جواب را عقب بیندازد، چون اخطار از راه درست ثبت نشده است.'
      : 'Allow 1–3 business days for a reply. Sending the same complaint to a host or internet provider does not speed this up, and can delay the reply, because the notice was not filed here.';
  String get openChannel => _fa ? 'باز کردن کانال تلگرام' : 'Open Telegram channel';
  String get openFailed => _fa ? 'تلگرام باز نشد.' : 'Could not open Telegram.';
}

Future<bool> sushiOpenSupportChannel() async {
  final https = Uri.parse(sushiSupportChannelUrl);
  if (await launchUrl(https, mode: LaunchMode.externalApplication)) return true;
  return launchUrl(
    Uri.parse('tg://resolve?domain=${SushiConfig.supportChannelUsername}'),
    mode: LaunchMode.externalApplication,
  );
}

class SushiDmcaPage extends StatelessWidget {
  const SushiDmcaPage({super.key});

  @override
  Widget build(BuildContext context) {
    final copy = SushiDmcaCopy.of(context);
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium;
    final muted = body?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: Text(copy.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(copy.lead, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          Text(copy.intro, style: body),
          const SizedBox(height: 20),
          Text(copy.requiredHeading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final item in copy.required) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: body),
                  Expanded(child: Text(item, style: body)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(copy.send, style: body),
          const SizedBox(height: 12),
          Text(copy.links, style: muted),
          const SizedBox(height: 12),
          Text(copy.timing, style: muted),
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.tonal(
              onPressed: () => _openChannel(context, copy),
              child: Text(copy.openChannel),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChannel(BuildContext context, SushiDmcaCopy copy) async {
    final opened = await sushiOpenSupportChannel();
    if (opened || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copy.openFailed)));
  }
}
