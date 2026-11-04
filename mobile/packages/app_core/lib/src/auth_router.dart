import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_code_flow_screens.dart';
import 'auth_flow.dart';
import 'auth_routes.dart';
import 'login_screen.dart';

/// Routes de la connexion (ADR 0011), montées telles quelles par les trois
/// apps : connexion, création de compte, mot de passe oublié. Le mot de
/// passe est sous les 6 cases : le retour (bouton ou geste du système)
/// revient au code, puis à l'e-mail ; quitter le parcours oublie le code.
List<RouteBase> authRoutes() => [
  GoRoute(
    path: AuthRoutes.login,
    builder: (context, state) => const LoginScreen(),
    routes: [
      for (final (path, purpose) in const [
        ('signup', CodePurpose.signup),
        ('forgot', CodePurpose.reset),
      ])
        GoRoute(
          path: path,
          builder: (context, state) => AuthEmailScreen(purpose: purpose),
          onExit: (context, state) {
            ProviderScope.containerOf(
              context,
              listen: false,
            ).read(authFlowProvider.notifier).clear();
            return true;
          },
          routes: [
            GoRoute(
              path: 'code',
              builder: (context, state) => AuthCodeScreen(purpose: purpose),
              routes: [
                GoRoute(
                  path: 'password',
                  builder: (context, state) =>
                      NewPasswordScreen(purpose: purpose),
                ),
              ],
            ),
          ],
        ),
    ],
  ),
];
