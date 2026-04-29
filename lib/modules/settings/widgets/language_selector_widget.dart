import 'package:flutter/material.dart';

import '../../../core/localization/l10n.dart';
import '../../../core/values/app_color.dart';
import '../../../core/values/app_style.dart';

class LanguageSelectorWidget extends StatelessWidget {
  const LanguageSelectorWidget({
    super.key,
    required this.selectedLanguageCode,
    required this.onChanged,
  });

  final String selectedLanguageCode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentValue = selectedLanguageCode == 'ja' ? 'ja' : 'en';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.language, size: 22),
            const SizedBox(width: 10),
            Text(l10n.language, style: titleTextStyleBlack),
            const Spacer(),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: currentValue,
                icon: const Icon(Icons.keyboard_arrow_down),
                style: subTitleTextStylePrimary,
                borderRadius: BorderRadius.circular(8),
                items: [
                  DropdownMenuItem<String>(
                    value: 'en',
                    child: Text(l10n.english),
                  ),
                  DropdownMenuItem<String>(
                    value: 'ja',
                    child: Text(l10n.japanese),
                  ),
                ],
                onChanged: (value) {
                  if (value == null || value == currentValue) return;
                  onChanged(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
