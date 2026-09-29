import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/core/widgets/ui_kit.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/company/presentation/providers/company_provider.dart';
import 'package:time_trak/core/constants/app_strings.dart';


class ProfileCard extends StatefulWidget {
  const ProfileCard({super.key});

  @override
  State<ProfileCard> createState() => ProfileCardState();
}

class ProfileCardState extends State<ProfileCard> {
  late final _name = TextEditingController(
    text: context.read<CompanyProvider>().context?.user?.name ?? '',
  );
  final _submit = SubmitController();

  @override
  void dispose() {
    _name.dispose();
    _submit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final company = context.read<CompanyProvider>();
    final ok = await _submit.run(() async {
      if (!await auth.updateProfile(name: name)) {
        return auth.errorMessage ?? 'Could not update profile';
      }
      await company.load();
      return null;
    });
    if (!mounted) return;
    showSnack(context, ok ? 'Profile updated' : _submit.error!, error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final company = context.watch<CompanyProvider>();
    final auth = context.watch<AuthProvider>();
    final user = company.context?.user;
    final display = user?.displayName ?? auth.user?.email ?? '';
    final role = company.isSuperAdmin
        ? 'Platform admin'
        : company.isCompanyAdmin
        ? 'Company admin'
        : 'Member';

    final avatar = Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.auroraGradient,
      ),
      child: UserAvatar(name: display, imageUrl: user?.avatarUrl, radius: 36),
    );
    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: 'Display name',
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(
              label: role,
              color: AppColors.primary,
              icon: Icons.verified_user_rounded,
            ),
            if (company.company != null)
              StatusPill(
                label: company.company!.name,
                color: AppColors.cyan,
                icon: Icons.business_rounded,
              ),
            if (user?.createdAt != null)
              StatusPill(
                label: 'Member since ${formatDate(user!.createdAt)}',
                color: AppColors.idle,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ListenableBuilder(
            listenable: _submit,
            builder: (context, _) => GradientButton(
              label: AppStrings.save,
              icon: Icons.check_rounded,
              loading: _submit.isBusy,
              onPressed: _save,
            ),
          ),
        ),
      ],
    );

    return context.isPhone
        ? Column(children: [avatar, const SizedBox(height: 16), form])
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TiltCard(child: avatar),
              const SizedBox(width: 20),
              Expanded(child: form),
            ],
          );
  }
}
