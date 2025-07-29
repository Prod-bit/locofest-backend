import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:locofest_new/pages/home_page.dart';
import 'package:locofest_new/pages/events_page.dart';
import 'package:locofest_new/pages/events_list_page.dart';
import 'package:locofest_new/pages/login_page.dart';
import 'package:locofest_new/pages/profile_page.dart';
import 'package:locofest_new/pages/choose_pseudo_page.dart';
import 'package:locofest_new/pages/forgot_password_page.dart';
import 'package:locofest_new/pages/favorites_page.dart';
import 'package:locofest_new/pages/organizer_request_page.dart';
import 'package:locofest_new/pages/admin_organizer_requests_page.dart';
import 'package:locofest_new/pages/feedback_page.dart';
// Ajout des imports pour les pages privées
import 'package:locofest_new/pages/private_calendar_page.dart';
import 'package:locofest_new/pages/private_calendar_settings_page.dart';
import 'package:locofest_new/pages/canal_page.dart';
import 'package:locofest_new/pages/private_calendar_management_page.dart';
import 'package:locofest_new/pages/private_access_page.dart';
import 'package:locofest_new/pages/private_profile_full_page.dart';
// AJOUT : import de la page des calendriers privés
import 'package:locofest_new/pages/my_private_calendars_page.dart';
// AJOUT : import de la page premium
import 'package:locofest_new/pages/premium_page.dart';
// AJOUT : import de la page des conditions d'utilisation
import 'package:locofest_new/pages/terms_page.dart';
// AJOUT : import de la page de chat général par ville
import 'package:locofest_new/pages/city_chat_page.dart';
// AJOUT : import de la page stats
import 'package:locofest_new/pages/my_stats_page.dart';
// AJOUT : import de la page d'analyse privée
import 'package:locofest_new/pages/private_analyse_page.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// AJOUT : Provider pour le thème
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:locofest_new/widgets/event_card.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Exécuter la configuration des notifications uniquement sur Android/iOS
  if (!kIsWeb) {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print('User granted permission: ${settings.authorizationStatus}');

    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // CORRECTION : Bloc try/catch autour de getToken et getAPNSToken
    try {
      String? token = await messaging.getToken();
      if (token != null) {
        print('FCM Token: $token');
        FirebaseAuth.instance.authStateChanges().listen((User? user) async {
          if (user != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({
              'fcmToken': token,
            });
          }
        });
      }

      final apnsToken = await messaging.getAPNSToken();
      print('APNS Token: $apnsToken');
    } catch (e) {
      print('Erreur Firebase Messaging (simulateur iOS) : $e');
    }
  }

  // Vérification de l'acceptation des CGU
  final prefs = await SharedPreferences.getInstance();
  final termsAccepted = prefs.getBool('termsAccepted') ?? false;

  // Initialisation du provider pour le thème
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: LocoFestApp(termsAccepted: termsAccepted),
    ),
  );
}

// Gestionnaire pour les notifications en arrière-plan
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}

class LocoFestApp extends StatelessWidget {
  final bool termsAccepted;
  const LocoFestApp({required this.termsAccepted, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      title: 'LocoFest',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('fr', 'FR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('fr', 'FR'),
      theme: ThemeData(
        useMaterial3: true,
        primaryColor: const Color(0xFF2196F3),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Color(0xFF2196F3),
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFamily: 'SansSerif',
          ),
          bodyMedium: TextStyle(
            color: Color(0xFF333333),
            fontSize: 16,
            fontFamily: 'SansSerif',
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2196F3),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
          ),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
      ),
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      initialRoute: termsAccepted ? '/home' : '/terms',
      onGenerateRoute: (settings) {
        print(
            'Navigation vers ${settings.name} avec arguments: ${settings.arguments}');
        if (settings.name == '/home') {
          return MaterialPageRoute(builder: (context) => const HomePage());
        }
        if (settings.name == '/events') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => EventsPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/events_list') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => EventsListPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/login') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => LoginPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/profile') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => ProfilePage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/choose_pseudo') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => ChoosePseudoPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/forgot_password') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => ForgotPasswordPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/favorites') {
          final args = settings.arguments as Map<String, dynamic>?;
          final city = args?['city'] ?? '';
          return MaterialPageRoute(
            builder: (context) => FavoritesPage(city: city),
            settings: settings,
          );
        }
        if (settings.name == '/organizer_request') {
          return MaterialPageRoute(
              builder: (context) => const OrganizerRequestPage(),
              settings: settings);
        }
        if (settings.name == '/admin_organizer_requests') {
          return MaterialPageRoute(
              builder: (context) => const AdminOrganizerRequestsPage(),
              settings: settings);
        }
        if (settings.name == '/feedback') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => FeedbackPage(
              city: args?['city'],
              isOrganizer: args?['isOrganizer'] ?? false,
            ),
            settings: settings,
          );
        }
        // ROUTES POUR LES EVENEMENTS PRIVES
        if (settings.name == '/private_calendar') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => PrivateCalendarPage(arguments: args),
            settings: settings,
          );
        }
        if (settings.name == '/private_calendar_settings') {
          final args = settings.arguments as Map<String, dynamic>?;
          print('Arguments reçus pour private_calendar_settings: $args');
          if (args == null || args['calendarId'] == null) {
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                body: Center(child: Text('calendarId manquant')),
              ),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => PrivateCalendarSettingsPage(
              calendarId: args['calendarId'],
              calendarName: args['calendarName'] ?? '',
              isOwner: args['isOwner'] ?? false,
            ),
            settings: settings,
          );
        }
        if (settings.name == '/canal') {
          final args = settings.arguments as Map<String, dynamic>?;
          print('Arguments reçus pour Canal : $args');
          if (args == null ||
              args['calendarId'] == null ||
              args['ownerId'] == null ||
              args['isOwner'] == null) {
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                body: Center(child: Text('Arguments manquants pour le canal')),
              ),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => CanalPage(
              calendarId: args['calendarId'],
              ownerId: args['ownerId'],
              isOwner: args['isOwner'],
            ),
            settings: settings,
          );
        }
        // ROUTE POUR LA GESTION DES CALENDRIERS PRIVES
        if (settings.name == '/private_calendar_management') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) =>
                PrivateCalendarManagementPage(arguments: args),
            settings: settings,
          );
        }
        // ROUTE POUR ACCES PAR LIEN D'INVITATION
        if (settings.name == '/private_access') {
          return MaterialPageRoute(
            builder: (context) => const PrivateAccessPage(),
            settings: settings,
          );
        }
        // ROUTE POUR LE PROFIL PRIVE (propriétaire/organisateur)
        if (settings.name == '/private_profile_full') {
          return MaterialPageRoute(
            builder: (context) => const PrivateProfileFullPage(),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE DES CALENDRIERS PRIVES
        if (settings.name == '/my_private_calendars') {
          return MaterialPageRoute(
            builder: (context) => const MyPrivateCalendarsPage(),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE PREMIUM
        if (settings.name == '/premium') {
          return MaterialPageRoute(
            builder: (context) => const PremiumPage(),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE DES CONDITIONS D'UTILISATION
        if (settings.name == '/terms') {
          final args = settings.arguments as Map<String, dynamic>?;
          final city = args?['city'] ?? '';
          final fromPrivate = args?['fromPrivate'] ?? false;
          return MaterialPageRoute(
            builder: (context) =>
                TermsPage(city: city, fromPrivate: fromPrivate),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE DE CHAT GENERAL PAR VILLE
        if (settings.name == '/city_chat') {
          final args = settings.arguments as Map<String, dynamic>?;
          final city = args?['city'] ?? '';
          return MaterialPageRoute(
            builder: (context) => CityChatPage(city: city),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE DE MES STATISTIQUES
        if (settings.name == '/my_stats') {
          return MaterialPageRoute(
            builder: (context) => MyStatsPage(),
            settings: settings,
          );
        }
        // AJOUT : ROUTE POUR LA PAGE D'ANALYSE PRIVEE
        if (settings.name == '/private_analyse') {
          final args = settings.arguments as Map<String, dynamic>?;
          return MaterialPageRoute(
            builder: (context) => PrivateAnalysePage(
              calendarId: args?['calendarId'],
              calendarName: args?['calendarName'],
            ),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
