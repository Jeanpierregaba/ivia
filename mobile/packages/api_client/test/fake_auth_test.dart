import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ivia_api_client/ivia_api_client.dart';
import 'package:ivia_api_client/testing.dart';

// Tests du faux serveur d'authentification `FakeAuth` (spec 029, ADR 0011),
// écrits avant lui (docs/TESTING.md, partie critique « OTP et sessions »).
// Les attentes reprennent le module `auth` du serveur Go : codes et messages
// de backend/internal/auth/flows.go, service.go et password.go.

// Mots de passe valables (10 caractères ou plus, ni courants ni tirés de
// l'e-mail).
const strong = 'manioc-et-gari-2026';
const other = 'pagne-wax-bleu-lome';
const third = 'akassa-du-matin-77';

// Messages exacts du serveur Go.
const invalidCredentials = 'E-mail ou mot de passe incorrect.';
const accountExists =
    'Un compte existe déjà avec cet e-mail : connectez-vous, ou utilisez '
    '« Mot de passe oublié ».';
String lockedMessage(int minutes) =>
    "Trop d'essais : compte bloqué $minutes min. Réessayez plus tard, ou "
    'utilisez « Mot de passe oublié ».';
const otpInvalid = 'Code incorrect ou expiré.';
const otpExpired = 'Ce code a expiré. Demandez-en un nouveau.';
const otpAttempts = "Trop d'essais. Demandez un nouveau code.";
const otpRateLimited =
    "Un code vient d'être envoyé. Patientez une minute avant d'en demander "
    'un autre.';
const otpDailyLimit =
    "Nombre maximal de codes atteint pour aujourd'hui. Réessayez demain.";
const validationFailed = 'Certaines informations sont invalides.';
const tooShort = 'Le mot de passe doit faire au moins 10 caractères.';
const tooLong = 'Le mot de passe fait 128 caractères au plus.';
const tooEasy =
    'Ce mot de passe est trop facile à deviner. Choisissez-en un autre.';
const currentWrong = 'Mot de passe actuel incorrect.';
const googleDisabled = "La connexion avec Google n'est pas encore disponible.";
const googleInvalid = 'Connexion avec Google impossible. Réessayez.';
const invalidSession = 'Votre session a expiré. Reconnectez-vous.';
const unauthenticated = 'Connectez-vous pour continuer.';

void main() {
  late FakeApiServer server;
  late FakeAuth auth;
  late IviaApiClient client;
  late DateTime clock;

  setUp(() {
    server = FakeApiServer();
    auth = FakeAuth(server);
    clock = DateTime.utc(2026, 11, 4, 8);
    auth.now = () => clock;
    client = IviaApiClient(
      config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
      adapter: server,
    );
  });

  void advance(Duration d) => clock = clock.add(d);

  /// Erreur renvoyée par [call] ; échoue si l'appel réussit.
  Future<ApiException> failure(Future<Object?> Function() call) async {
    try {
      await call();
    } on ApiException catch (e) {
      return e;
    }
    fail('ApiException attendue, l\'appel a réussi');
  }

  void expectError(ApiException e, int status, String code, [String? message]) {
    expect(e.statusCode, status, reason: e.code);
    expect(e.code, code);
    if (message != null) expect(e.message, message);
  }

  /// Requête brute (statut et corps tels que le serveur les renvoie), avec
  /// le jeton du client s'il y en a un.
  Future<Response<Object?>> raw(String method, String path, [Object? data]) =>
      client.debugDio.request<Object?>(
        path,
        data: data,
        options: Options(method: method, validateStatus: (_) => true),
      );

  /// Demande un code et retourne celui que le faux serveur a « envoyé ».
  Future<String> signupCode(String email) async {
    await client.requestSignupCode(email);
    return auth.lastCode(email, 'signup')!;
  }

  Future<String> resetCode(String email) async {
    await client.requestPasswordReset(email);
    return auth.lastCode(email, 'reset')!;
  }

  /// Un autre code à 6 chiffres que [code].
  String wrong(String code) =>
      ((int.parse(code) + 1) % 1000000).toString().padLeft(6, '0');

  Future<String> loginToken(String email, String password) async =>
      (await client.login(email, password)).token;

  group('modes de connexion et état de la session', () {
    test('Google annoncé selon le réglage `google`', () async {
      final off = await client.authProviders();
      expect(off.password, isTrue);
      expect(off.google, isFalse);

      auth.google = true;
      final on = await client.authProviders();
      expect(on.password, isTrue);
      expect(on.google, isTrue);
    });

    test('FakeAuth(google: true) annonce Google dès le départ', () async {
      final s = FakeApiServer();
      FakeAuth(s, google: true);
      final c = IviaApiClient(
        config: ApiConfig(baseUrl: Uri.parse('http://api.test')),
        adapter: s,
      );
      expect((await c.authProviders()).google, isTrue);
    });

    test('session ouverte : non vérifiée, mot de passe, expiration', () async {
      auth.addAccount('awa@test.tg', password: strong);
      client.token = await loginToken('awa@test.tg', strong);

      final response = await raw('GET', '/v1/auth/session');
      expect(response.statusCode, 200);
      final body = response.data! as Map<String, dynamic>;
      expect(body['mfa_verified'], isFalse);
      expect(body['has_password'], isTrue);
      expect(
        DateTime.parse(body['expires_at'] as String).isAfter(clock),
        isTrue,
      );
      expect((await client.sessionInfo()).hasPassword, isTrue);
    });

    test('session : jeton inconnu ⇒ 401 invalid_session', () async {
      client.token = 'jeton-inconnu-de-quarante-caracteres-au-moins-xx';
      final e = await failure(client.sessionInfo);
      expectError(e, 401, 'invalid_session', invalidSession);
    });

    test('session : sans jeton ⇒ 401 unauthenticated', () async {
      final e = await failure(client.sessionInfo);
      expectError(e, 401, 'unauthenticated', unauthenticated);
    });

    test('e-mails normalisés : casse et espaces ignorés', () async {
      auth.addAccount('Awa.Mensah@Test.TG', password: strong);
      // Corps brut : le faux serveur normalise lui-même, comme le serveur Go.
      final response = await raw('POST', '/v1/auth/login', {
        'email': '  AWA.mensah@test.tg ',
        'password': strong,
      });
      expect(response.statusCode, 200);
      final body = response.data! as Map<String, dynamic>;
      expect((body['user'] as Map)['email'], 'awa.mensah@test.tg');
      expect(auth.passwordOf('awa.mensah@test.tg'), strong);
    });
  });

  group('demande de code', () {
    test('202 : canal e-mail, valable 10 min, renvoi après 60 s', () async {
      final response = await raw('POST', '/v1/auth/signup/code', {
        'email': 'kofi@test.tg',
      });
      expect(response.statusCode, 202);
      expect(response.data, {
        'channel': 'email',
        'expires_in_seconds': 600,
        'resend_after_seconds': 60,
      });
      expect(auth.lastCode('kofi@test.tg', 'signup'), matches(r'^\d{6}$'));
      expect(auth.lastCode('kofi@test.tg', 'reset'), isNull);
    });

    test(
      'mot de passe oublié, compte connu : même 202 et code envoyé',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        final response = await raw('POST', '/v1/auth/password/forgot', {
          'email': 'awa@test.tg',
        });
        expect(response.statusCode, 202);
        expect(response.data, {
          'channel': 'email',
          'expires_in_seconds': 600,
          'resend_after_seconds': 60,
        });
        expect(auth.lastCode('awa@test.tg', 'reset'), matches(r'^\d{6}$'));
        expect(auth.lastCode('awa@test.tg', 'signup'), isNull);
      },
    );

    test('adresse invalide ⇒ 400 validation_failed sur recipient', () async {
      final e = await failure(() => client.requestSignupCode('pas-un-email'));
      expectError(e, 400, 'validation_failed', validationFailed);
      expect(e.fields['recipient'], 'Adresse e-mail invalide.');
    });

    test('même réponse que le compte existe ou non', () async {
      auth
        ..addAccount('avec@test.tg', password: strong)
        ..addAccount('ancien@test.tg');
      final bodies = [
        for (final email in ['avec@test.tg', 'ancien@test.tg', 'neuf@test.tg'])
          await raw('POST', '/v1/auth/signup/code', {'email': email}),
      ];
      for (final r in bodies) {
        expect(r.statusCode, 202);
        expect(r.data, bodies.first.data);
      }
      for (final email in ['avec@test.tg', 'ancien@test.tg', 'neuf@test.tg']) {
        expect(auth.lastCode(email, 'signup'), isNotNull, reason: email);
      }
    });

    test(
      'second code du même usage dans la minute ⇒ 429 otp_rate_limited',
      () async {
        await client.requestSignupCode('kofi@test.tg');
        final first = auth.lastCode('kofi@test.tg', 'signup');
        advance(const Duration(seconds: 59));
        final e = await failure(() => client.requestSignupCode('kofi@test.tg'));
        expectError(e, 429, 'otp_rate_limited', otpRateLimited);
        expect(auth.lastCode('kofi@test.tg', 'signup'), first);

        advance(const Duration(seconds: 2));
        await client.requestSignupCode('kofi@test.tg');
        expect(auth.lastCode('kofi@test.tg', 'signup'), isNotNull);
      },
    );

    test('usages différents dans la même minute : acceptés', () async {
      auth.addAccount('awa@test.tg', password: strong);
      await client.requestSignupCode('awa@test.tg');
      await client.requestPasswordReset('awa@test.tg');
      expect(auth.lastCode('awa@test.tg', 'signup'), isNotNull);
      expect(auth.lastCode('awa@test.tg', 'reset'), isNotNull);
    });

    test(
      '10 codes par jour tous usages confondus, puis otp_daily_limit',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        final start = clock;
        for (var i = 0; i < 5; i++) {
          await client.requestSignupCode('awa@test.tg');
          await client.requestPasswordReset('awa@test.tg');
          advance(const Duration(seconds: 61));
        }
        final signup = await failure(
          () => client.requestSignupCode('awa@test.tg'),
        );
        expectError(signup, 429, 'otp_daily_limit', otpDailyLimit);
        final reset = await failure(
          () => client.requestPasswordReset('awa@test.tg'),
        );
        expectError(reset, 429, 'otp_daily_limit', otpDailyLimit);

        // Fenêtre glissante de 24 h : les deux premiers codes en sortent.
        clock = start.add(const Duration(hours: 24, seconds: 1));
        await client.requestSignupCode('awa@test.tg');
      },
    );

    test('la limite par jour vaut par adresse', () async {
      for (var i = 0; i < 10; i++) {
        await client.requestSignupCode('kofi@test.tg');
        advance(const Duration(seconds: 61));
      }
      await failure(() => client.requestSignupCode('kofi@test.tg'));
      await client.requestSignupCode('ama@test.tg');
      expect(auth.lastCode('ama@test.tg', 'signup'), isNotNull);
    });

    test('un nouveau code annule l\'ancien du même usage', () async {
      final first = await signupCode('kofi@test.tg');
      advance(const Duration(seconds: 61));
      final second = await signupCode('kofi@test.tg');
      expect(second, isNot(first));

      final e = await failure(
        () => client.signup('kofi@test.tg', first, strong),
      );
      expectError(e, 401, 'otp_invalid', otpInvalid);
      final session = await client.signup('kofi@test.tg', second, strong);
      expect(session.isNewUser, isTrue);
    });

    test('un nouveau code n\'annule pas celui d\'un autre usage', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final reset = await resetCode('awa@test.tg');
      await client.requestSignupCode('awa@test.tg');
      final session = await client.resetPassword('awa@test.tg', reset, other);
      expect(session.user.email, 'awa@test.tg');
    });

    test('le code d\'un usage est refusé pour l\'autre', () async {
      auth.addAccount('awa@test.tg');
      final signup = await signupCode('awa@test.tg');
      final asReset = await failure(
        () => client.resetPassword('awa@test.tg', signup, strong),
      );
      expectError(asReset, 401, 'otp_invalid', otpInvalid);

      final reset = await resetCode('awa@test.tg');
      if (reset != signup) {
        final asSignup = await failure(
          () => client.signup('awa@test.tg', reset, strong),
        );
        expectError(asSignup, 401, 'otp_invalid', otpInvalid);
      }
      // Chaque code reste valable pour son usage.
      await client.signup('awa@test.tg', signup, strong);
      await client.resetPassword('awa@test.tg', reset, other);
      expect(auth.passwordOf('awa@test.tg'), other);
    });
  });

  group('vérification du code', () {
    test('code faux ⇒ 401 otp_invalid', () async {
      final code = await signupCode('kofi@test.tg');
      final e = await failure(
        () => client.signup('kofi@test.tg', wrong(code), strong),
      );
      expectError(e, 401, 'otp_invalid', otpInvalid);
      expect(auth.passwordOf('kofi@test.tg'), isNull);
    });

    test('aucun code demandé ⇒ otp_invalid', () async {
      final e = await failure(
        () => client.signup('kofi@test.tg', '123456', strong),
      );
      expectError(e, 401, 'otp_invalid', otpInvalid);
    });

    test('4 codes faux puis le bon : accepté', () async {
      final code = await signupCode('kofi@test.tg');
      for (var i = 0; i < 4; i++) {
        final e = await failure(
          () => client.signup('kofi@test.tg', wrong(code), strong),
        );
        expectError(e, 401, 'otp_invalid', otpInvalid);
      }
      final session = await client.signup('kofi@test.tg', code, strong);
      expect(session.isNewUser, isTrue);
    });

    test('5e code faux ⇒ otp_too_many_attempts, puis toujours', () async {
      final code = await signupCode('kofi@test.tg');
      for (var i = 0; i < 4; i++) {
        await failure(() => client.signup('kofi@test.tg', wrong(code), strong));
      }
      final fifth = await failure(
        () => client.signup('kofi@test.tg', wrong(code), strong),
      );
      expectError(fifth, 401, 'otp_too_many_attempts', otpAttempts);

      final right = await failure(
        () => client.signup('kofi@test.tg', code, strong),
      );
      expectError(right, 401, 'otp_too_many_attempts', otpAttempts);
      expect(auth.passwordOf('kofi@test.tg'), isNull);
    });

    test('un nouveau code repart avec 5 essais', () async {
      final code = await signupCode('kofi@test.tg');
      for (var i = 0; i < 5; i++) {
        await failure(() => client.signup('kofi@test.tg', wrong(code), strong));
      }
      advance(const Duration(seconds: 61));
      final fresh = await signupCode('kofi@test.tg');
      for (var i = 0; i < 4; i++) {
        final e = await failure(
          () => client.signup('kofi@test.tg', wrong(fresh), strong),
        );
        expectError(e, 401, 'otp_invalid');
      }
      await client.signup('kofi@test.tg', fresh, strong);
    });

    test('code de mauvaise longueur : refusé sans compter d\'essai', () async {
      final code = await signupCode('kofi@test.tg');
      for (var i = 0; i < 6; i++) {
        final e = await failure(
          () => client.signup('kofi@test.tg', '12345', strong),
        );
        expectError(e, 401, 'otp_invalid', otpInvalid);
      }
      await client.signup('kofi@test.tg', code, strong);
    });

    test('valable jusqu\'à 10 min', () async {
      final code = await signupCode('kofi@test.tg');
      advance(const Duration(minutes: 9, seconds: 59));
      final session = await client.signup('kofi@test.tg', code, strong);
      expect(session.isNewUser, isTrue);
    });

    test('expiré après 10 min ⇒ otp_expired', () async {
      final code = await signupCode('kofi@test.tg');
      advance(const Duration(minutes: 10, seconds: 1));
      final e = await failure(
        () => client.signup('kofi@test.tg', code, strong),
      );
      expectError(e, 401, 'otp_expired', otpExpired);
      expect(auth.passwordOf('kofi@test.tg'), isNull);
    });

    test('un code ne sert qu\'une fois', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final code = await resetCode('awa@test.tg');
      await client.resetPassword('awa@test.tg', code, other);
      final e = await failure(
        () => client.resetPassword('awa@test.tg', code, third),
      );
      expectError(e, 401, 'otp_invalid', otpInvalid);
      expect(auth.passwordOf('awa@test.tg'), other);
    });
  });

  group('règles du mot de passe (vérifiées avant le code)', () {
    /// Demande un code de création pour [email] et tente la création avec
    /// [password] ; retourne l'erreur, ou `null` si le compte est créé.
    Future<ApiException?> trySignup(String email, String password) async {
      final code = await signupCode(email);
      try {
        await client.signup(email, code, password);
        return null;
      } on ApiException catch (e) {
        return e;
      }
    }

    void expectRefused(ApiException? e, String message) {
      expect(e, isNotNull, reason: 'mot de passe accepté à tort');
      expectError(e!, 400, 'validation_failed', validationFailed);
      expect(e.fields['password'], message);
    }

    test('moins de 10 caractères ⇒ refusé', () async {
      expectRefused(await trySignup('a1@test.tg', 'Kp7#qz!w2'), tooShort);
      expectRefused(await trySignup('a2@test.tg', ''), tooShort);
    });

    test('10 caractères, accents compris : accepté', () async {
      expect(await trySignup('a1@test.tg', 'àéèùçôîëüé'), isNull);
      expect(auth.passwordOf('a1@test.tg'), 'àéèùçôîëüé');
    });

    test('longueur comptée en caractères, pas en unités UTF-16', () async {
      // 9 caractères (5 émojis + 4 lettres), 14 unités UTF-16.
      expectRefused(await trySignup('a1@test.tg', '😀😀😀😀😀abcd'), tooShort);
    });

    test('plus de 128 caractères ⇒ refusé ; 128 accepté', () async {
      expectRefused(await trySignup('a1@test.tg', 'k' * 129), tooLong);
      expect(await trySignup('a2@test.tg', 'k' * 128), isNull);
    });

    test(
      'mots de passe courants refusés, casse et ponctuation ignorées',
      () async {
        final common = [
          'motdepasse123',
          'azertyuiop',
          'Password123',
          'azerty-1234',
          'TOGO123456',
          'iloveyou12',
        ];
        for (final (i, password) in common.indexed) {
          expectRefused(await trySignup('c$i@test.tg', password), tooEasy);
        }
      },
    );

    test('égal à l\'e-mail ⇒ refusé', () async {
      expectRefused(
        await trySignup('kossi.agbeko@test.tg', 'Kossi.Agbeko@test.tg'),
        tooEasy,
      );
    });

    test(
      'contient la partie locale de l\'e-mail (moins de 16) ⇒ refusé',
      () async {
        expectRefused(
          await trySignup('kossi.agbeko@test.tg', 'kossiagbeko2026'),
          tooEasy,
        );
      },
    );

    test(
      'contient la partie locale mais 16 caractères ou plus : accepté',
      () async {
        expect(
          await trySignup('kossi.agbeko@test.tg', 'kossiagbeko-2026!'),
          isNull,
        );
      },
    );

    test('partie locale de moins de 4 lettres ou chiffres : ignorée', () async {
      expect(await trySignup('ama@test.tg', 'ama-lome-26'), isNull);
    });

    test('refus du mot de passe : code ni consommé ni compté', () async {
      final code = await signupCode('kofi@test.tg');
      // Même avec un code faux, c'est le mot de passe qui est refusé, sans
      // compter d'essai : six refus ne bloquent pas le code.
      for (var i = 0; i < 6; i++) {
        final e = await failure(
          () => client.signup('kofi@test.tg', wrong(code), 'court'),
        );
        expectError(e, 400, 'validation_failed');
        expect(e.fields['password'], tooShort);
      }
      final weak = await failure(
        () => client.signup('kofi@test.tg', code, 'azertyuiop'),
      );
      expect(weak.fields['password'], tooEasy);

      final session = await client.signup('kofi@test.tg', code, strong);
      expect(session.isNewUser, isTrue);
    });
  });

  group('création de compte', () {
    test(
      'compte neuf : 201, session ouverte, mot de passe enregistré',
      () async {
        final code = await signupCode('kofi@test.tg');
        final response = await raw('POST', '/v1/auth/signup', {
          'email': 'kofi@test.tg',
          'code': code,
          'password': strong,
        });
        expect(response.statusCode, 201);
        final session = Session.fromJson(
          response.data! as Map<String, dynamic>,
        );
        expect(session.isNewUser, isTrue);
        expect(session.user.email, 'kofi@test.tg');
        expect(session.user.profileComplete, isFalse);
        expect(session.token, isNotEmpty);
        final body = response.data! as Map<String, dynamic>;
        expect(
          DateTime.parse(body['expires_at'] as String).isAfter(clock),
          isTrue,
        );

        expect(auth.passwordOf('kofi@test.tg'), strong);
        expect(auth.sessionsOf('kofi@test.tg'), {session.token});
        client.token = session.token;
        expect((await client.sessionInfo()).hasPassword, isTrue);
      },
    );

    test(
      'compte de l\'ancienne connexion par code : mot de passe ajouté',
      () async {
        auth.addAccount('awa@test.tg');
        expect(auth.passwordOf('awa@test.tg'), isNull);
        final code = await signupCode('awa@test.tg');
        final session = await client.signup('awa@test.tg', code, strong);
        expect(session.isNewUser, isFalse);
        expect(session.user.profileComplete, isTrue);
        expect(auth.passwordOf('awa@test.tg'), strong);

        final again = await client.login('awa@test.tg', strong);
        expect(again.user.id, session.user.id);
      },
    );

    test('compte au profil incomplet : profil rendu tel quel', () async {
      auth.addAccount('awa@test.tg', complete: false);
      final code = await signupCode('awa@test.tg');
      final session = await client.signup('awa@test.tg', code, strong);
      expect(session.isNewUser, isFalse);
      expect(session.user.profileComplete, isFalse);
    });

    test(
      'compte qui a déjà un mot de passe ⇒ 409, code toujours valable',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        final code = await signupCode('awa@test.tg');
        final e = await failure(
          () => client.signup('awa@test.tg', code, other),
        );
        expectError(e, 409, 'account_exists', accountExists);
        expect(auth.passwordOf('awa@test.tg'), strong);
        expect(auth.sessionsOf('awa@test.tg'), isEmpty);

        // Code non consommé : même réponse, pas otp_invalid.
        final again = await failure(
          () => client.signup('awa@test.tg', code, other),
        );
        expectError(again, 409, 'account_exists');
      },
    );
  });

  group('connexion par mot de passe', () {
    test('succès : session ouverte, compte existant', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final response = await raw('POST', '/v1/auth/login', {
        'email': 'awa@test.tg',
        'password': strong,
      });
      expect(response.statusCode, 200);
      final session = Session.fromJson(response.data! as Map<String, dynamic>);
      expect(session.isNewUser, isFalse);
      expect(session.user.email, 'awa@test.tg');
      expect(session.user.profileComplete, isTrue);
      expect(auth.sessionsOf('awa@test.tg'), {session.token});
    });

    test('chaque connexion ouvre une session distincte', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final a = await loginToken('awa@test.tg', strong);
      final b = await loginToken('awa@test.tg', strong);
      expect(a, isNot(b));
      expect(auth.sessionsOf('awa@test.tg'), {a, b});
    });

    test(
      'mauvais mot de passe, compte inconnu ou sans mot de passe : même 401',
      () async {
        auth
          ..addAccount('awa@test.tg', password: strong)
          ..addAccount('ancien@test.tg');
        final errors = [
          await failure(() => client.login('awa@test.tg', other)),
          await failure(() => client.login('inconnu@test.tg', strong)),
          await failure(() => client.login('ancien@test.tg', strong)),
          await failure(() => client.login('pas-un-email', strong)),
        ];
        for (final e in errors) {
          expectError(e, 401, 'invalid_credentials', invalidCredentials);
          expect(e.fields, isEmpty);
        }
      },
    );

    test('10 échecs d\'affilée ⇒ 429 account_locked pour 15 min', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 9; i++) {
        final e = await failure(() => client.login('awa@test.tg', other));
        expectError(e, 401, 'invalid_credentials', invalidCredentials);
      }
      expect(auth.isLocked('awa@test.tg'), isFalse);
      final tenth = await failure(() => client.login('awa@test.tg', other));
      expectError(tenth, 429, 'account_locked', lockedMessage(15));
      expect(auth.isLocked('awa@test.tg'), isTrue);
    });

    test('compte bloqué : même le bon mot de passe est refusé', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 10; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      final e = await failure(() => client.login('awa@test.tg', strong));
      expectError(e, 429, 'account_locked', lockedMessage(15));
      expect(auth.sessionsOf('awa@test.tg'), isEmpty);

      // Le message donne les minutes restantes.
      advance(const Duration(minutes: 5));
      final later = await failure(() => client.login('awa@test.tg', strong));
      expectError(later, 429, 'account_locked', lockedMessage(10));
      advance(const Duration(minutes: 9, seconds: 59));
      final last = await failure(() => client.login('awa@test.tg', strong));
      expectError(last, 429, 'account_locked', lockedMessage(1));
    });

    test('déverrouillé après 15 min', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 10; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      advance(const Duration(minutes: 15, seconds: 1));
      expect(auth.isLocked('awa@test.tg'), isFalse);
      final session = await client.login('awa@test.tg', strong);
      expect(auth.sessionsOf('awa@test.tg'), {session.token});
    });

    test('les essais pendant le blocage ne le prolongent pas', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 10; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      advance(const Duration(minutes: 14));
      for (var i = 0; i < 5; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      advance(const Duration(minutes: 1, seconds: 1));
      await client.login('awa@test.tg', strong);
    });

    test('après le déverrouillage, le compteur repart de zéro', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 10; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      advance(const Duration(minutes: 15, seconds: 1));
      for (var i = 0; i < 9; i++) {
        final e = await failure(() => client.login('awa@test.tg', other));
        expectError(e, 401, 'invalid_credentials');
      }
      final tenth = await failure(() => client.login('awa@test.tg', other));
      expectError(tenth, 429, 'account_locked', lockedMessage(15));
    });

    test('un succès remet le compteur d\'échecs à zéro', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 9; i++) {
        await failure(() => client.login('awa@test.tg', other));
      }
      await client.login('awa@test.tg', strong);
      for (var i = 0; i < 9; i++) {
        final e = await failure(() => client.login('awa@test.tg', other));
        expectError(e, 401, 'invalid_credentials');
      }
      expect(auth.isLocked('awa@test.tg'), isFalse);
      await client.login('awa@test.tg', strong);
    });

    test(
      'compte inconnu : jamais bloqué, toujours invalid_credentials',
      () async {
        for (var i = 0; i < 12; i++) {
          final e = await failure(() => client.login('inconnu@test.tg', other));
          expectError(e, 401, 'invalid_credentials');
        }
      },
    );
  });

  group('mot de passe oublié', () {
    test('compte inconnu : même 202, aucun code envoyé', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final known = await raw('POST', '/v1/auth/password/forgot', {
        'email': 'awa@test.tg',
      });
      final unknown = await raw('POST', '/v1/auth/password/forgot', {
        'email': 'inconnu@test.tg',
      });
      expect(unknown.statusCode, 202);
      expect(unknown.data, known.data);
      expect(auth.lastCode('inconnu@test.tg', 'reset'), isNull);
    });

    test('compte inconnu : pas de limite par minute (aucun code)', () async {
      await client.requestPasswordReset('inconnu@test.tg');
      await client.requestPasswordReset('inconnu@test.tg');
      expect(auth.lastCode('inconnu@test.tg', 'reset'), isNull);
    });

    test('compte inconnu : un code deviné ne crée rien', () async {
      await client.requestPasswordReset('inconnu@test.tg');
      final e = await failure(
        () => client.resetPassword('inconnu@test.tg', '123456', strong),
      );
      expectError(e, 401, 'otp_invalid', otpInvalid);
      expect(auth.passwordOf('inconnu@test.tg'), isNull);
    });

    test('réinitialisation : nouveau mot de passe, l\'ancien refusé', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final code = await resetCode('awa@test.tg');
      final response = await raw('POST', '/v1/auth/password/reset', {
        'email': 'awa@test.tg',
        'code': code,
        'password': other,
      });
      expect(response.statusCode, 200);
      final session = Session.fromJson(response.data! as Map<String, dynamic>);
      expect(session.isNewUser, isFalse);
      expect(session.user.email, 'awa@test.tg');
      expect(auth.passwordOf('awa@test.tg'), other);

      await client.login('awa@test.tg', other);
      final old = await failure(() => client.login('awa@test.tg', strong));
      expectError(old, 401, 'invalid_credentials');
    });

    test('toutes les anciennes sessions sont révoquées', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final a = await loginToken('awa@test.tg', strong);
      final b = await loginToken('awa@test.tg', strong);
      final code = await resetCode('awa@test.tg');
      final session = await client.resetPassword('awa@test.tg', code, other);
      expect(auth.sessionsOf('awa@test.tg'), {session.token});

      for (final old in [a, b]) {
        client.token = old;
        final e = await failure(client.sessionInfo);
        expectError(e, 401, 'invalid_session');
      }
      client.token = session.token;
      expect((await client.sessionInfo()).hasPassword, isTrue);
    });

    test('compte bloqué : débloqué par la réinitialisation', () async {
      auth.addAccount('awa@test.tg', password: strong);
      for (var i = 0; i < 10; i++) {
        await failure(() => client.login('awa@test.tg', third));
      }
      expect(auth.isLocked('awa@test.tg'), isTrue);
      final code = await resetCode('awa@test.tg');
      await client.resetPassword('awa@test.tg', code, other);
      expect(auth.isLocked('awa@test.tg'), isFalse);
      await client.login('awa@test.tg', other);
    });

    test('compte sans mot de passe : en reçoit un', () async {
      auth.addAccount('ancien@test.tg');
      final code = await resetCode('ancien@test.tg');
      final session = await client.resetPassword(
        'ancien@test.tg',
        code,
        strong,
      );
      expect(auth.passwordOf('ancien@test.tg'), strong);
      client.token = session.token;
      expect((await client.sessionInfo()).hasPassword, isTrue);
    });

    test('règles du mot de passe appliquées, code non consommé', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final code = await resetCode('awa@test.tg');
      final e = await failure(
        () => client.resetPassword('awa@test.tg', code, 'motdepasse1'),
      );
      expectError(e, 400, 'validation_failed', validationFailed);
      expect(e.fields['password'], tooEasy);
      expect(auth.passwordOf('awa@test.tg'), strong);

      await client.resetPassword('awa@test.tg', code, other);
      expect(auth.passwordOf('awa@test.tg'), other);
    });
  });

  group('connexion avec Google', () {
    test('Google désactivé ⇒ 400 google_disabled', () async {
      auth.addGoogleToken('jeton-g', subject: 'g-1', email: 'awa@test.tg');
      final e = await failure(() => client.signInWithGoogle('jeton-g'));
      expectError(e, 400, 'google_disabled', googleDisabled);
      expect(auth.sessionsOf('awa@test.tg'), isEmpty);
    });

    test('jeton inconnu ⇒ 401 google_token_invalid', () async {
      auth.google = true;
      final e = await failure(() => client.signInWithGoogle('jeton-faux'));
      expectError(e, 401, 'google_token_invalid', googleInvalid);
    });

    test('nouvel e-mail : compte créé, sans mot de passe', () async {
      auth
        ..google = true
        ..addGoogleToken('jeton-g', subject: 'g-1', email: 'kofi@test.tg');
      final response = await raw('POST', '/v1/auth/google', {
        'id_token': 'jeton-g',
      });
      expect(response.statusCode, 200);
      final session = Session.fromJson(response.data! as Map<String, dynamic>);
      expect(session.isNewUser, isTrue);
      expect(session.user.email, 'kofi@test.tg');
      expect(session.user.profileComplete, isFalse);
      expect(auth.passwordOf('kofi@test.tg'), isNull);
      expect(auth.sessionsOf('kofi@test.tg'), {session.token});

      client.token = session.token;
      expect((await client.sessionInfo()).hasPassword, isFalse);
      final login = await failure(() => client.login('kofi@test.tg', strong));
      expectError(login, 401, 'invalid_credentials');
    });

    test(
      'e-mail d\'un compte existant : compte rattaché, pas recréé',
      () async {
        auth
          ..google = true
          ..addAccount('awa@test.tg', password: strong)
          ..addGoogleToken('jeton-g', subject: 'g-1', email: 'Awa@Test.TG');
        final byPassword = await client.login('awa@test.tg', strong);
        final byGoogle = await client.signInWithGoogle('jeton-g');
        expect(byGoogle.isNewUser, isFalse);
        expect(byGoogle.user.id, byPassword.user.id);
        expect(byGoogle.user.email, 'awa@test.tg');
        expect(byGoogle.user.profileComplete, isTrue);
        expect(auth.passwordOf('awa@test.tg'), strong);

        client.token = byGoogle.token;
        expect((await client.sessionInfo()).hasPassword, isTrue);
      },
    );

    test('deuxième connexion Google : même compte, pas nouveau', () async {
      auth
        ..google = true
        ..addGoogleToken('jeton-g', subject: 'g-1', email: 'kofi@test.tg');
      final first = await client.signInWithGoogle('jeton-g');
      final second = await client.signInWithGoogle('jeton-g');
      expect(second.isNewUser, isFalse);
      expect(second.user.id, first.user.id);
      expect(second.token, isNot(first.token));
      expect(auth.sessionsOf('kofi@test.tg'), {first.token, second.token});
    });

    test(
      'compte retrouvé par l\'identifiant Google, même si l\'e-mail change',
      () async {
        auth
          ..google = true
          ..addGoogleToken('jeton-1', subject: 'g-1', email: 'kofi@test.tg')
          ..addGoogleToken('jeton-2', subject: 'g-1', email: 'kofi.n@test.tg');
        final first = await client.signInWithGoogle('jeton-1');
        final second = await client.signInWithGoogle('jeton-2');
        expect(second.isNewUser, isFalse);
        expect(second.user.id, first.user.id);
        expect(second.user.email, 'kofi@test.tg');
        expect(auth.sessionsOf('kofi@test.tg'), {first.token, second.token});
        expect(auth.sessionsOf('kofi.n@test.tg'), isEmpty);

        // Aucun compte n'a été créé pour la nouvelle adresse.
        await client.requestPasswordReset('kofi.n@test.tg');
        expect(auth.lastCode('kofi.n@test.tg', 'reset'), isNull);
      },
    );
  });

  group('changement de mot de passe', () {
    test('sans session ⇒ 401 unauthenticated', () async {
      final e = await failure(
        () => client.changePassword(current: strong, next: other),
      );
      expectError(e, 401, 'unauthenticated', unauthenticated);
    });

    test('session révoquée ⇒ 401 invalid_session', () async {
      auth.addAccount('awa@test.tg', password: strong);
      final old = await loginToken('awa@test.tg', strong);
      final code = await resetCode('awa@test.tg');
      await client.resetPassword('awa@test.tg', code, other);
      client.token = old;
      final e = await failure(
        () => client.changePassword(current: other, next: third),
      );
      expectError(e, 401, 'invalid_session', invalidSession);
      expect(auth.passwordOf('awa@test.tg'), other);
    });

    test(
      'succès : 204, autres sessions révoquées, la courante gardée',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        final current = await loginToken('awa@test.tg', strong);
        final elsewhere = await loginToken('awa@test.tg', strong);
        client.token = current;
        final response = await raw('POST', '/v1/me/password', {
          'current_password': strong,
          'new_password': other,
        });
        expect(response.statusCode, 204);
        expect(auth.passwordOf('awa@test.tg'), other);
        expect(auth.sessionsOf('awa@test.tg'), {current});
        expect((await client.sessionInfo()).hasPassword, isTrue);

        client.token = elsewhere;
        final e = await failure(client.sessionInfo);
        expectError(e, 401, 'invalid_session');

        client.token = null;
        await client.login('awa@test.tg', other);
        final old = await failure(() => client.login('awa@test.tg', strong));
        expectError(old, 401, 'invalid_credentials');
      },
    );

    test('mot de passe actuel faux ⇒ 400 sur current_password', () async {
      auth.addAccount('awa@test.tg', password: strong);
      client.token = await loginToken('awa@test.tg', strong);
      final e = await failure(
        () => client.changePassword(current: third, next: other),
      );
      expectError(e, 400, 'validation_failed', validationFailed);
      expect(e.fields, {'current_password': currentWrong});
      expect(auth.passwordOf('awa@test.tg'), strong);
    });

    test(
      'mot de passe actuel absent alors que le compte en a un ⇒ 400',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        client.token = await loginToken('awa@test.tg', strong);
        final e = await failure(() => client.changePassword(next: other));
        expectError(e, 400, 'validation_failed');
        expect(e.fields['current_password'], currentWrong);
        expect(auth.passwordOf('awa@test.tg'), strong);
      },
    );

    test('actuel faux compté dans les échecs de connexion', () async {
      auth.addAccount('awa@test.tg', password: strong);
      client.token = await loginToken('awa@test.tg', strong);
      for (var i = 0; i < 9; i++) {
        await failure(() => client.login('awa@test.tg', third));
      }
      // 10e échec : le serveur répond toujours sur le champ, mais bloque.
      final e = await failure(
        () => client.changePassword(current: third, next: other),
      );
      expect(e.fields['current_password'], currentWrong);
      expect(auth.isLocked('awa@test.tg'), isTrue);

      final saved = client.token;
      client.token = null;
      final login = await failure(() => client.login('awa@test.tg', strong));
      expectError(login, 429, 'account_locked', lockedMessage(15));
      client.token = saved;
    });

    test(
      'compte bloqué ⇒ 429 account_locked, même avec le bon actuel',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        client.token = await loginToken('awa@test.tg', strong);
        for (var i = 0; i < 10; i++) {
          await failure(() => client.login('awa@test.tg', third));
        }
        final e = await failure(
          () => client.changePassword(current: strong, next: other),
        );
        expectError(e, 429, 'account_locked', lockedMessage(15));
        expect(auth.passwordOf('awa@test.tg'), strong);
      },
    );

    test('nouveau mot de passe soumis aux règles (champ password)', () async {
      auth.addAccount('kossi.agbeko@test.tg', password: strong);
      client.token = await loginToken('kossi.agbeko@test.tg', strong);
      final cases = {
        'court': tooShort,
        'k' * 129: tooLong,
        'azertyuiop': tooEasy,
        'kossiagbeko2026': tooEasy,
      };
      for (final MapEntry(key: next, value: message) in cases.entries) {
        final e = await failure(
          () => client.changePassword(current: strong, next: next),
        );
        expectError(e, 400, 'validation_failed', validationFailed);
        expect(e.fields['password'], message, reason: next);
      }
      expect(auth.passwordOf('kossi.agbeko@test.tg'), strong);
    });

    test(
      'nouveau mot de passe vérifié avant l\'actuel, sans compter d\'échec',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        client.token = await loginToken('awa@test.tg', strong);
        for (var i = 0; i < 10; i++) {
          final e = await failure(
            () => client.changePassword(current: third, next: 'court'),
          );
          expect(e.fields.keys, ['password']);
        }
        expect(auth.isLocked('awa@test.tg'), isFalse);
        await client.changePassword(current: strong, next: other);
      },
    );

    test(
      'compte créé avec Google : mot de passe défini sans l\'actuel',
      () async {
        auth
          ..google = true
          ..addGoogleToken('jeton-g', subject: 'g-1', email: 'kofi@test.tg');
        final session = await client.signInWithGoogle('jeton-g');
        client.token = session.token;
        await client.changePassword(next: strong);
        expect(auth.passwordOf('kofi@test.tg'), strong);
        expect((await client.sessionInfo()).hasPassword, isTrue);
        expect(auth.sessionsOf('kofi@test.tg'), {session.token});

        client.token = null;
        await client.login('kofi@test.tg', strong);
      },
    );

    test(
      'compte sans mot de passe : un « actuel » envoyé est ignoré',
      () async {
        // Compte de l'ancienne connexion par code, ouvert ici par Google
        // (rattaché par l'e-mail) : il n'a toujours pas de mot de passe.
        auth
          ..addAccount('ancien@test.tg')
          ..google = true
          ..addGoogleToken('jeton-g', subject: 'g-2', email: 'ancien@test.tg');
        final session = await client.signInWithGoogle('jeton-g');
        expect(session.isNewUser, isFalse);
        client.token = session.token;
        expect((await client.sessionInfo()).hasPassword, isFalse);

        await client.changePassword(current: 'nimporte-quoi-123', next: strong);
        expect(auth.passwordOf('ancien@test.tg'), strong);
      },
    );
  });

  group('pannes simulées', () {
    test(
      'failures : une fois, sur la première requête correspondante',
      () async {
        auth.failures['POST /v1/auth/signup/code'] = FakeResponse.error(
          503,
          'otp_send_failed',
          "Le code n'a pas pu être envoyé. Réessayez dans un instant.",
        );
        final e = await failure(() => client.requestSignupCode('kofi@test.tg'));
        expectError(e, 503, 'otp_send_failed');
        expect(auth.lastCode('kofi@test.tg', 'signup'), isNull);

        // Retirée après usage ; la panne n'a pas compté dans la limite.
        await client.requestSignupCode('kofi@test.tg');
        expect(auth.lastCode('kofi@test.tg', 'signup'), isNotNull);
        expect(auth.failures, isEmpty);
      },
    );

    test(
      'failures : clé partielle, seules les routes qui la contiennent',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        auth.failures['password/reset'] = FakeResponse.networkError();
        await client.requestPasswordReset('awa@test.tg');
        final code = auth.lastCode('awa@test.tg', 'reset')!;
        await client.login('awa@test.tg', strong);

        final e = await failure(
          () => client.resetPassword('awa@test.tg', code, other),
        );
        expect(e.isNetwork, isTrue);
        expect(auth.passwordOf('awa@test.tg'), strong);

        // La requête perdue n'a pas consommé le code.
        await client.resetPassword('awa@test.tg', code, other);
        expect(auth.passwordOf('awa@test.tg'), other);
      },
    );

    test(
      'beforeRequest : réponse retenue jusqu\'à la fin de l\'attente',
      () async {
        auth.addAccount('awa@test.tg', password: strong);
        final gate = Completer<void>();
        final seen = <String>[];
        auth.beforeRequest = (r) {
          seen.add('${r.method} ${r.path}');
          return gate.future;
        };
        var done = false;
        final pending = client.login('awa@test.tg', strong).then((s) {
          done = true;
          return s;
        });
        await pumpEventQueue();
        expect(seen, ['POST /v1/auth/login']);
        expect(done, isFalse);

        gate.complete();
        final session = await pending;
        expect(done, isTrue);
        expect(auth.sessionsOf('awa@test.tg'), {session.token});
      },
    );

    test('requêtes enregistrées par le serveur', () async {
      auth.addAccount('awa@test.tg', password: strong);
      await client.login('awa@test.tg', strong);
      expect(server.calls('POST', '/v1/auth/login'), hasLength(1));
      expect(server.last.body, {'email': 'awa@test.tg', 'password': strong});
    });
  });
}
