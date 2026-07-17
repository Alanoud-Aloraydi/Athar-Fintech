import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/app_settings.dart';
import '../core/strings.dart';
import '../core/auth_error_mapper.dart';
import '../services/auth_service.dart';
import '../widgets/common_widgets.dart';

/// Edits the same `user_metadata` fields the existing ProfileScreen reads
/// (`first_name`, `last_name`, `phone`) via Supabase's client-side
/// `auth.updateUser`. There is no dedicated `PATCH /profile` endpoint on the
/// FastAPI backend today (only GET-path profile reads via ProfileRepository),
/// so this intentionally goes through Supabase auth metadata -- the same
/// source of truth ProfileScreen already uses -- rather than fabricating a
/// backend call that doesn't exist.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController emailController;
  late final TextEditingController phoneController;
  bool isLoading = false;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    final user = AuthService().currentUser;
    final metadata = user?.userMetadata ?? {};
    final fullName = [metadata['first_name'], metadata['last_name']]
        .where((e) => e != null && (e as String).isNotEmpty)
        .join(' ');
    nameController = TextEditingController(text: fullName);
    emailController = TextEditingController(text: user?.email ?? '');
    phoneController = TextEditingController(text: (metadata['phone'] as String?) ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      isLoading = true;
      errorMsg = null;
    });
    try {
      final parts = nameController.text.trim().split(RegExp(r'\s+'));
      final firstName = parts.isNotEmpty ? parts.first : '';
      final lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {
            'first_name': firstName,
            'last_name': lastName,
            'phone': phoneController.text.trim(),
          },
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('saved_success'))));
      Navigator.pop(context);
    } catch (e) {
      setState(() => errorMsg = friendlyAuthErrorMessage(e, fallback: 'تعذّر حفظ التعديلات، حاول مرة أخرى'));
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScope(builder: (context) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('edit_personal_data'))),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppTextField(controller: nameController, label: tr('name'), icon: Icons.badge_outlined),
                const SizedBox(height: 14),
                AppTextField(
                    controller: emailController, label: tr('email'), icon: Icons.email_outlined, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 14),
                AppTextField(
                    controller: phoneController, label: tr('phone'), icon: Icons.phone_outlined, keyboardType: TextInputType.phone),
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Text(errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                ],
                const SizedBox(height: 26),
                PrimaryButton(text: tr('save_changes'), isLoading: isLoading, onPressed: _save),
              ],
            ),
          ),
        ),
      );
    });
  }
}