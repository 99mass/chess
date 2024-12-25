import 'package:chess/constant/constants.dart';
import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;

  const CustomTextField({
    required this.controller,
    required this.hintText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      cursorColor: ColorsConstants.white,
      style: const TextStyle(color: ColorsConstants.white),
      controller: controller,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.all(20.0),
        hintText: hintText,
        hintStyle: const TextStyle(
            color: ColorsConstants.white, height: 1.0),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
        filled: true,
        fillColor: ColorsConstants.colorBg3,
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 0.0),
          child: Image.asset('assets/icons8_user_24.png'),
        ),
      ),
    );
  }
}
