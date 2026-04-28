import 'package:flutter/material.dart';
import '../../../core/values/app_style.dart';

class SignUpTextFieldWidget extends StatelessWidget {
  final String hintText;
  final TextEditingController controller;
  final bool isNumber;

  const SignUpTextFieldWidget({
    super.key,
    required this.hintText,
    required this.controller,
    required this.isNumber,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      controller: controller,
      decoration: InputDecoration(
        labelText: hintText,
        labelStyle: subTitleTextStyleGray,
        hintText: hintText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5)),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$hintText is required';
        }
        return null;
      },
    );
  }
}
