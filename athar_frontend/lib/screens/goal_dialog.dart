import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

/// Returns the created [Goal] on success, or null if cancelled.
/// Shows a safe, Arabic message if the user already has an ACTIVE goal
/// (create_goal is rejected server-side with 409, not client-side) --
/// see [ApiExceptionArabic] in api_service.dart for the mapping.
Future<Goal?> showCreateGoalDialog(BuildContext context, {required String userId}) {
  final titleController = TextEditingController();
  final amountController = TextEditingController();
  AppCategory selectedCategory = AppCategory.savings;
  bool isSubmitting = false;

  return showDialog<Goal>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('هدف مالي جديد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(controller: titleController, label: 'اسم الهدف', icon: Icons.flag_rounded),
              const SizedBox(height: 14),
              AppTextField(controller: amountController, label: 'المبلغ المستهدف', icon: Icons.savings_rounded, keyboardType: TextInputType.number),
              const SizedBox(height: 14),
              DropdownButtonFormField<AppCategory>(
                value: selectedCategory,
                decoration: const InputDecoration(labelText: 'التصنيف'),
                items: AppCategory.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                    .toList(),
                onChanged: (v) => setState(() => selectedCategory = v ?? selectedCategory),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(
            onPressed: isSubmitting
                ? null
                : () async {
                    final amount = double.tryParse(amountController.text.trim());
                    if (titleController.text.trim().isEmpty || amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال بيانات صحيحة')));
                      return;
                    }
                    setState(() => isSubmitting = true);
                    try {
                      final goal = await ApiService().createGoal(
                        userId: userId,
                        title: titleController.text.trim(),
                        targetAmount: amount,
                        category: selectedCategory,
                      );
                      if (context.mounted) Navigator.pop(context, goal);
                    } on ApiException catch (e) {
                      setState(() => isSubmitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.arabicMessage)));
                      }
                    }
                  },
            child: isSubmitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('إنشاء'),
          ),
        ],
      ),
    ),
  );
}