import 'package:flutter/widgets.dart';

class AboutVersionBannerText extends StatelessWidget {
  const AboutVersionBannerText({
    super.key,
    required this.text,
    required this.targetLabel,
    required this.style,
    this.textAlign = TextAlign.center,
  });

  static const String _productName = 'NipaPlay Reload';

  final String text;
  final String targetLabel;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final label = targetLabel.trim();
    if (label.isEmpty || !text.startsWith(_productName)) {
      return Text(
        text,
        style: style,
        textAlign: textAlign,
      );
    }

    final defaultFontSize = DefaultTextStyle.of(context).style.fontSize ?? 24;
    final baseFontSize = style.fontSize ?? defaultFontSize;
    final versionText = text.substring(_productName.length).trimLeft();

    return Text.rich(
      TextSpan(
        style: style,
        children: [
          const TextSpan(text: _productName),
          TextSpan(
            text: '\nfor $label',
            style: style.copyWith(
              color: _mutedColor(style.color),
              fontSize: baseFontSize * 0.58,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (versionText.isNotEmpty) TextSpan(text: '\n$versionText'),
        ],
      ),
      textAlign: textAlign,
    );
  }

  Color? _mutedColor(Color? color) {
    if (color == null) {
      return null;
    }
    return color.withValues(alpha: color.a * 0.72);
  }
}
