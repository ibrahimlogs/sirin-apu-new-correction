import 'package:flutter/material.dart';

import '../../../core/values/app_color.dart';
import '../../../core/values/app_style.dart';

// ignore: must_be_immutable
class PersonalListWidgets extends StatelessWidget {
  String hint;
  final String data;

  VoidCallback onPressed;
  PersonalListWidgets({
    super.key,
    required this.hint,
    required this.data,
    required this.onPressed,
  });

  bool _shouldStack(BuildContext context, double maxWidth) {
    final textDirection = Directionality.of(context);

    final hintPainter = TextPainter(
      text: TextSpan(text: hint, style: subTitleTextStyleGray),
      maxLines: 1,
      textDirection: textDirection,
    )..layout();

    final dataPainter = TextPainter(
      text: TextSpan(text: data, style: subTitleTextStylePrimary),
      maxLines: 1,
      textDirection: textDirection,
    )..layout();

    const horizontalPadding = 24.0;
    const gap = 12.0;
    return hintPainter.width + dataPainter.width + horizontalPadding + gap >
        maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: TextButton(
        onPressed: onPressed,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(color: AppColors.pageBackgroundGray),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final shouldStack = _shouldStack(context, constraints.maxWidth);

              if (shouldStack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hint,
                      style: subTitleTextStyleGray,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        data,
                        style: subTitleTextStylePrimary,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Text(
                    hint,
                    style: subTitleTextStyleGray,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      data,
                      style: subTitleTextStylePrimary,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
