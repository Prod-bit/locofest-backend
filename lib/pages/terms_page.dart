import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

class TermsPage extends StatefulWidget {
  final String? city;
  final bool? fromPrivate;

  const TermsPage({Key? key, this.city, this.fromPrivate}) : super(key: key);

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  final ScrollController _scrollController = ScrollController();
  bool _hasScrolledToEnd = false;
  int _currentTermsVersion = 1;

  bool _initialized = false;
  late bool _fromPrivate;
  String? _city;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchTermsVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      _fromPrivate = args?['fromPrivate'] ?? widget.fromPrivate ?? false;
      _city = args?['city'] ?? widget.city;
      _initialized = true;
    }
  }

  void _onScroll() {
    if (!_hasScrolledToEnd &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 10) {
      setState(() {
        _hasScrolledToEnd = true;
      });
    }
  }

  Future<void> _fetchTermsVersion() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('terms')
          .get();
      if (doc.exists && doc.data()?['termsVersion'] != null) {
        if (!mounted) return;
        setState(() {
          _currentTermsVersion = doc.data()!['termsVersion'] as int;
        });
      }
    } catch (_) {
      // Si erreur, garde la version 1 par défaut
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _acceptTerms(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    final prefs = await SharedPreferences.getInstance();

    // Stockage local
    await prefs.setBool('termsAccepted', true);
    await prefs.setInt('termsVersion', _currentTermsVersion);

    // Stockage Firestore pour non-connecté (deviceId)
    if (user == null) {
      final deviceInfo = DeviceInfoPlugin();
      String deviceId = '';
      try {
        if (Theme.of(context).platform == TargetPlatform.android) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id ?? '';
        } else if (Theme.of(context).platform == TargetPlatform.iOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? '';
        }
      } catch (_) {
        deviceId = '';
      }

      if (deviceId.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('terms_acceptances')
            .doc(deviceId)
            .set({
          'acceptedAt': DateTime.now(),
          'termsVersion': _currentTermsVersion,
          'deviceId': deviceId,
        });
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    // Utilisateur connecté : stocke sur son profil
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.now(),
      'termsVersion': _currentTermsVersion,
    });

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _refuseTerms(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[900]
            : Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, color: Colors.red[600], size: 48),
              const SizedBox(height: 16),
              Text(
                "Accès refusé",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: Colors.red[700],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                "Vous devez accepter les conditions d'utilisation pour accéder à l'application.",
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: const Text("Retour"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[700],
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Responsive values
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalPadding = screenWidth * 0.06;
    double cardPadding = screenWidth * 0.05;
    double fontTitle = screenWidth * 0.06;
    double fontSubtitle = screenWidth * 0.045;
    double fontNormal = screenWidth * 0.04;
    double buttonHeight = screenWidth * 0.13;
    double buttonFont = screenWidth * 0.045;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Conditions d'utilisation"),
        centerTitle: true,
        backgroundColor: Colors.amber[700],
        foregroundColor: Colors.white,
        elevation: 2,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(
                      horizontal: horizontalPadding, vertical: cardPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Icon(Icons.privacy_tip,
                            color: Colors.amber[700], size: screenWidth * 0.13),
                      ),
                      SizedBox(height: screenWidth * 0.04),
                      Center(
                        child: Text(
                          "Conditions d'utilisation",
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: Colors.amber[800],
                            fontWeight: FontWeight.bold,
                            fontSize: fontTitle,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      SizedBox(height: screenWidth * 0.04),
                      Text(
                        "Merci de lire attentivement l'intégralité des conditions d'utilisation avant d'accéder à l'application.",
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: fontNormal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: screenWidth * 0.06),
                      Container(
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[900] : Colors.amber[50],
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.amber),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTerm(
                              "1. Objet",
                              "L'application LocoFest permet de créer, partager et consulter des événements publics ou privés, d'accéder à des services Premium, et d'interagir avec d'autres utilisateurs.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "2. Inscription et Compte Utilisateur",
                              "Vous devez fournir des informations exactes lors de votre inscription. Vous êtes responsable de la confidentialité de vos identifiants. L'accès à certaines fonctionnalités peut être restreint selon votre âge ou votre pays.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "3. Messagerie et Contenus",
                              "Les messages et contenus publiés doivent respecter la loi et les règles de respect. Aucun contenu illégal, offensant, haineux ou discriminatoire n'est toléré. Les contenus peuvent être modérés ou supprimés à tout moment.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "4. Paiement et Abonnement Premium",
                              "L'abonnement Premium est facturé de manière récurrente (mensuelle) via un prestataire de paiement sécurisé. L'abonnement est reconduit automatiquement jusqu'à résiliation. Aucun remboursement n'est possible sauf disposition légale contraire. En cas d'échec de paiement, l'accès Premium sera suspendu. Les paiements peuvent être effectués par carte bancaire ou, le cas échéant, en cryptomonnaie (dans ce cas, la volatilité des cours et l'absence de remboursement en crypto sont à la charge de l'utilisateur).",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "5. API et Services Tiers",
                              "LocoFest utilise des API et services tiers (paiement, analytics, notifications, etc.). L'utilisation de ces services est soumise à leurs propres conditions et politiques de confidentialité.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "6. Données personnelles et données sensibles",
                              "Vos données, y compris des données sensibles (âge, localisation, préférences), sont traitées conformément à la politique de confidentialité. Vous pouvez demander la suppression de vos données à tout moment.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "7. Cible internationale",
                              "L'application est accessible dans plusieurs pays. Certaines fonctionnalités peuvent être limitées ou indisponibles selon la législation locale.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "8. Propriété intellectuelle",
                              "Les contenus publiés restent la propriété de leurs auteurs, mais vous accordez à LocoFest une licence d'utilisation pour l'affichage et la promotion sur l'application. Toute reproduction sans autorisation est interdite.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "9. Sécurité du compte",
                              "Vous êtes responsable de la sécurité de votre compte et devez informer LocoFest en cas de suspicion d'accès non autorisé.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "10. Limitation de responsabilité",
                              "LocoFest ne saurait être tenu responsable en cas de perte de données, bug, indisponibilité du service, ou dommages indirects liés à l'utilisation de l'application.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "11. Suspension et Suppression",
                              "Tout manquement aux règles peut entraîner la suspension ou la suppression de votre compte sans préavis.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "12. Modification des conditions",
                              "Les conditions peuvent évoluer. Vous serez notifié en cas de changement majeur. La poursuite de l'utilisation de l'application vaut acceptation des nouvelles conditions.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "13. Droit applicable et juridiction",
                              "Les présentes conditions sont soumises au droit du pays de résidence de l'utilisateur, sauf disposition contraire. En cas de litige, les tribunaux compétents seront ceux du siège de LocoFest.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "14. Contact",
                              "Pour toute question ou suggestion, utilisez la fonction « Retour / Avis » disponible dans l'application.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "15. Statistiques et données d’usage",
                              "L’application collecte et affiche des statistiques d’utilisation (participations, vues, partages, likes…) sur vos événements. Ces données sont conservées pour une durée maximale de 31 jours et sont accessibles uniquement à l’organisateur concerné.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "16. Publication anonyme",
                              "Certaines fonctionnalités permettent de publier des messages de façon anonyme (ex : chat de ville, canal privé) pour les utilisateurs Premium ou les administrateurs (admins, développeurs de l’application).",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "17. Quotas et limitations",
                              "Certaines fonctionnalités (partage d’événements, nombre d’événements créés, etc.) peuvent être soumises à des quotas ou limitations selon votre type de compte (utilisateur, premium, admin). Ces limites sont précisées dans l’application.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                            _buildTerm(
                              "18. Modération des contenus",
                              "Tout contenu publié (événements, messages, partages, commentaires) peut être modéré ou supprimé par LocoFest en cas de non-respect des règles ou sur signalement d’un utilisateur.",
                              isDark,
                              fontSubtitle,
                              fontNormal,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: screenWidth * 0.06),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: cardPadding),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      onPressed: _hasScrolledToEnd
                          ? () => _acceptTerms(context)
                          : null,
                      label: Text("J'accepte",
                          style: TextStyle(fontSize: buttonFont)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber[700],
                        foregroundColor: Colors.white,
                        minimumSize: Size.fromHeight(buttonHeight * 0.37),
                        textStyle: TextStyle(fontSize: buttonFont),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: screenWidth * 0.04),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _refuseTerms(context),
                      label: Text("Refuser",
                          style: TextStyle(fontSize: buttonFont)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        minimumSize: Size.fromHeight(buttonHeight * 0.37),
                        textStyle: TextStyle(fontSize: buttonFont),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!_hasScrolledToEnd)
              Padding(
                padding: EdgeInsets.only(bottom: cardPadding * 0.5),
                child: Text(
                  "Faites défiler jusqu'en bas pour accepter",
                  style: TextStyle(
                    color: Colors.red[700],
                    fontWeight: FontWeight.bold,
                    fontSize: fontNormal,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerm(String title, String content, bool isDark,
      double fontSubtitle, double fontNormal) {
    return Padding(
      padding: EdgeInsets.only(bottom: fontNormal * 2.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fontSubtitle,
              color: isDark ? Colors.amber[300] : const Color(0xFFB8860B),
            ),
          ),
          SizedBox(height: fontNormal * 0.7),
          Text(
            content,
            style: TextStyle(
              fontSize: fontNormal,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
