import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/common_widgets.dart';

/// Returns the resulting [TransactionResult] on success (so the caller can
/// refresh the dashboard), or null if cancelled.
Future<TransactionResult?> showAddTransactionSheet(BuildContext context, {required String userId}) {
  final descriptionController = TextEditingController();
  final amountController = TextEditingController();
  String selectedType = 'EXPENSE';
  bool isSubmitting = false;
  // Generated once per sheet instance, reused across retries of the same
  // submission — this is exactly what the backend's idempotency_key is for.
  final idempotencyKey = const Uuid().v4();

  return showModalBottomSheet<TransactionResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('إضافة عملية جديدة', style: AppTextStyles.h2),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'EXPENSE', label: Text('مصروف'), icon: Icon(Icons.arrow_upward_rounded)),
                ButtonSegment(value: 'INCOME', label: Text('دخل'), icon: Icon(Icons.arrow_downward_rounded)),
              ],
              selected: {selectedType},
              onSelectionChanged: (s) => setState(() => selectedType = s.first),
            ),
            const SizedBox(height: 14),
            AppTextField(controller: amountController, label: 'المبلغ', icon: Icons.payments_rounded, keyboardType: TextInputType.number),
            const SizedBox(height: 14),
            AppTextField(controller: descriptionController, label: 'الوصف (مثال: STC، كارفور، ستاربكس)', icon: Icons.notes_rounded),
            const SizedBox(height: 6),
            const Text('يتم تصنيف العملية تلقائياً بواسطة محرك التصنيف في الخادم', style: AppTextStyles.small),
            const SizedBox(height: 18),
            PrimaryButton(
              text: 'حفظ العملية',
              isLoading: isSubmitting,
              onPressed: () async {
                final amount = double.tryParse(amountController.text.trim());
                if (amount == null || amount <= 0 || descriptionController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال بيانات صحيحة')));
                  return;
                }
                setState(() => isSubmitting = true);
                try {
                  final result = await ApiService().createTransaction(
                    userId: userId,
                    amount: amount,
                    description: descriptionController.text.trim(),
                    type: selectedType,
                    idempotencyKey: idempotencyKey,
                  );
                  if (context.mounted) Navigator.pop(context, result);
                } on ApiException catch (e) {
                  setState(() => isSubmitting = false);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.arabicMessage)));
                  }
                }
              },
            ),
          ],
        ),
      ),
    ),
  );
}