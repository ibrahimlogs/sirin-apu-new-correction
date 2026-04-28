// goal_section_widgets.dart
import 'package:flutter/material.dart';
import '../../../core/values/app_style.dart';
import 'goal_list_widgets.dart';

class GoalSectionWidgets extends StatelessWidget {
  final String goal;

  const GoalSectionWidgets({super.key, required this.goal});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 25.0),
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
                const Icon(Icons.flag_outlined),
                const SizedBox(width: 10),
                Text('Goal', style: titleTextStyleBlack),
                const Spacer(),
                const Icon(Icons.keyboard_arrow_down),
              ],
            ),
            const SizedBox(height: 20),
            // Keep the exact same usage/design
            GoalListWidgets(hint: "Step Count (Per Day)", value: goal),
          ],
        ),
      ),
    );
  }
}
