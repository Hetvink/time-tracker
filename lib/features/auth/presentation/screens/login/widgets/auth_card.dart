import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:time_trak/features/auth/presentation/providers/auth_provider.dart';
import 'package:time_trak/features/auth/presentation/providers/login_form_controller.dart';

import 'auth_card_view.dart';

class AuthCard extends StatelessWidget {
  const AuthCard({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (context) => LoginFormController(context.read<AuthProvider>()),
    child: const AuthCardView(),
  );
}
