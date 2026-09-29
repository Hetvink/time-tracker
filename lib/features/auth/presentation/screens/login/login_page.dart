import 'package:flutter/material.dart';

import 'package:time_trak/core/widgets/ui_kit.dart';

import 'widgets/compact_brand.dart';
import 'widgets/hero.dart';
import 'widgets/auth_card.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = context.screenWidth >= 980;
    return Scaffold(
      body: AuroraBackground(
        grid: true,
        child: SafeArea(
          child: wide
              ? Row(
                  children: [
                    const Expanded(flex: 6, child: LoginHero()),
                    Expanded(
                      flex: 5,
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(32),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: const AuthCard(),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(context.gutter),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: const Column(
                        children: [
                          CompactBrand(),
                          SizedBox(height: 24),
                          AuthCard(),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Hero (wide screens)
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Auth card
// -----------------------------------------------------------------------------

/// Four-colour "G" without an image asset.
