import 'package:flutter/material.dart';

import '../../../core/values/app_style.dart';
import 'personal_list_widgets.dart';

class AccountSectionWidgets extends StatelessWidget {
  final String nickName;
  final String gender;
  final String birthday;
  final String height;
  final String weight;
  final String personalCode;
  final VoidCallback onPressedNickName;
  final VoidCallback onPressedGender;
  final VoidCallback onPressedBirthday;
  final VoidCallback onPressedHeight;
  final VoidCallback onPressedWeight;
  final String companyName;
  final VoidCallback onPressedCompanyName;
  final VoidCallback onPressedPersonalCode;

  const AccountSectionWidgets({
    super.key,
    required this.nickName,
    required this.gender,
    required this.height,
    required this.weight,
    required this.personalCode,
    required this.birthday,
    required this.onPressedGender,
    required this.onPressedBirthday,
    required this.onPressedHeight,
    required this.onPressedWeight,
    required this.companyName,
    required this.onPressedCompanyName,
    required this.onPressedPersonalCode,
    required this.onPressedNickName,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 25),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.person_outline),
                SizedBox(width: 10),
                Text('Profile', style: titleTextStyleBlack),
                Spacer(),
                Icon(Icons.keyboard_arrow_down),
              ],
            ),
            const SizedBox(height: 20),
            PersonalListWidgets(
              hint: "Nick Name",
              data: nickName,
              onPressed: onPressedNickName,
            ),
            PersonalListWidgets(
              hint: "Gender",
              data: gender,
              onPressed: onPressedGender,
            ),

            PersonalListWidgets(
              hint: "Date Of Birth",
              data: birthday,
              onPressed: onPressedBirthday,
            ),

            PersonalListWidgets(
              hint: "Height",
              data: height,
              onPressed: onPressedHeight,
            ),
            PersonalListWidgets(
              hint: "Weight",
              data: weight,
              onPressed: onPressedWeight,
            ),
            PersonalListWidgets(
              hint: "Company Name",
              data: companyName,
              onPressed: onPressedCompanyName,
            ),
            PersonalListWidgets(
              hint: "Personal Code",
              data: personalCode,
              onPressed: onPressedPersonalCode,
            ),
          ],
        ),
      ),
    );
  }
}
