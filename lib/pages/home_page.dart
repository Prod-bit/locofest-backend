import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _selectedCity;
  final TextEditingController _cityController = TextEditingController();

  final List<String> _tips = [
    "💡 Lisez bien ces astuces pour profiter pleinement de LocoFest ! Appuyez ici pour découvrir les autres astuces.",
    "Au-delà des villes, saisissez le nom de votre jeu vidéo préféré ou de votre communauté pour accéder à tous les événements associés, présentés dans un calendrier clair.",
    "Après votre première connexion, il vous suffit de saisir votre ville et de cliquer sur 'Continuer' pour être reconnu en tant qu'utilisateur, et ce, jusqu'à votre prochaine déconnexion.",
    "Ajoutez vos événements en favoris pour les retrouver facilement.",
    "Posez vos questions directement aux organisateurs.",
    "Devenez organisateur et créez vos propres événements !",
    "Consultez le calendrier pour ne rien manquer.",
    "Vous pouvez créer des calendriers privés pour organiser des événements confidentiels.",
    "Certains événements peuvent être privés et n’apparaîtront que si vous y êtes invité.",
    "Vous pouvez envoyer des messages anonymes si vous êtes Premium.",
    "Consultez régulièrement l’appli pour découvrir de nouveaux événements chaque semaine.",
    "Invitez vos amis à rejoindre LocoFest et créez votre propre communauté.",
    "Utilisez le chat général pour poser vos questions ou partager vos bons plans.",
    "Devenez Premium pour profiter de fonctionnalités exclusives et soutenir LocoFest.",
    "Participez à un événement pour rencontrer de nouvelles personnes près de chez vous.",
  ];
  int _currentTipIndex = 0;

  String? _userPseudo;
  List<DocumentSnapshot> _myPrivateCalendars = [];
  List<Map<String, String>> _localAccounts = [];

  void _showNextTip() {
    setState(() {
      _currentTipIndex = (_currentTipIndex + 1) % _tips.length;
    });
  }

  @override
  void initState() {
    super.initState();
    _waitAndRemoveOnline();
    _cityController.addListener(() {
      String currentText = _cityController.text;
      String lowercaseText = currentText.toLowerCase();
      if (currentText != lowercaseText) {
        _cityController.value = _cityController.value.copyWith(
          text: lowercaseText,
          selection: TextSelection.collapsed(offset: lowercaseText.length),
        );
      }
      setState(() {
        _selectedCity = lowercaseText.trim();
      });
    });
    _loadUserPseudoIfConnected();
    _loadMyPrivateCalendarsIfConnected();
    _loadLocalAccounts();
  }

  Future<void> _waitAndRemoveOnline() async {
    int tries = 0;
    while (FirebaseAuth.instance.currentUser == null && tries < 20) {
      await Future.delayed(const Duration(milliseconds: 100));
      tries++;
    }
    await _removeUserFromAllCitiesOnline();
  }

  Future<void> _removeUserFromAllCitiesOnline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final cities =
        await FirebaseFirestore.instance.collection('city_chats').get();
    for (final city in cities.docs) {
      final cityIdBrut = city.id;
      final cityId = cityIdBrut.trim().toLowerCase();
      try {
        await FirebaseFirestore.instance
            .collection('city_chats')
            .doc(cityId)
            .collection('online')
            .doc(user.uid)
            .delete();
      } catch (e) {
        // ignore
      }
    }
  }

  Future<void> _loadUserPseudoIfConnected() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null) {
        if (!mounted) return;
        setState(() {
          _userPseudo = data['pseudo'];
        });
      }
    }
  }

  Future<void> _loadMyPrivateCalendarsIfConnected() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final owned = await FirebaseFirestore.instance
          .collection('private_calendars')
          .where('ownerId', isEqualTo: user.uid)
          .get();
      final memberQuery = await FirebaseFirestore.instance
          .collection('private_calendars')
          .where('members.${user.uid}', isEqualTo: true)
          .get();
      if (!mounted) return;
      setState(() {
        _myPrivateCalendars = [
          ...owned.docs,
          ...memberQuery.docs.where(
              (doc) => !owned.docs.any((ownedDoc) => ownedDoc.id == doc.id))
        ];
      });
    }
  }

  Future<void> _loadLocalAccounts() async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = prefs.getStringList('localAccounts') ?? [];
    setState(() {
      _localAccounts = accounts.map((a) {
        final parts = a.split('|');
        return {
          'uid': parts[0],
          'pseudo': parts.length > 1 ? parts[1] : '',
          'email': parts.length > 2 ? parts[2] : '',
          'certif': parts.length > 3 ? parts[3] : '',
        };
      }).toList();
    });
  }

  Future<void> _forgetAccount(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> accounts = prefs.getStringList('localAccounts') ?? [];
    accounts.removeWhere((a) => a.startsWith('$uid|'));
    await prefs.setStringList('localAccounts', accounts);
    await _loadLocalAccounts();
  }

  Future<void> _showAccountsModal() async {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final double certifIconSize = screenWidth * 0.06;
    final double pseudoFontSize = screenWidth * 0.045;
    final double emailFontSize = screenWidth * 0.032;
    final double buttonFontSize = screenWidth * 0.04;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDarkMode ? Color(0xFF23272F) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.settings,
                      color:
                          isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2)),
                  SizedBox(width: 10),
                  Text(
                    "Comptes enregistrés",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: pseudoFontSize * 1.1,
                      color: isDarkMode ? Colors.white : Color(0xFF1976D2),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              for (final acc in _localAccounts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.account_circle,
                          size: certifIconSize,
                          color:
                              isDarkMode ? Colors.white70 : Color(0xFF1976D2)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  acc['pseudo'] ?? '',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: pseudoFontSize,
                                    color: isDarkMode
                                        ? Colors.white
                                        : Color(0xFF1976D2),
                                  ),
                                ),
                                if ((acc['certif'] ?? '').isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Icon(
                                      acc['certif'] == 'boss'
                                          ? Icons.verified_user
                                          : Icons.verified,
                                      color: acc['certif'] == 'boss'
                                          ? Colors.blue
                                          : Colors.amber,
                                      size: certifIconSize * 0.8,
                                    ),
                                  ),
                              ],
                            ),
                            if ((acc['email'] ?? '').isNotEmpty)
                              Text(
                                acc['email']!,
                                style: TextStyle(
                                  fontSize: emailFontSize,
                                  color: isDarkMode
                                      ? Colors.white54
                                      : Colors.grey[700],
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.remove_circle,
                            color: Colors.red, size: certifIconSize * 0.8),
                        tooltip: "Oublier ce compte",
                        onPressed: () async {
                          await _forgetAccount(acc['uid']!);
                          Navigator.pop(context);
                          await _showAccountsModal();
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.login, // Icône "entrer"
                            color: isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            size: certifIconSize * 0.8),
                        tooltip: "Se connecter avec ce compte",
                        onPressed: () {
                          Navigator.pop(context);
                          Future.delayed(const Duration(milliseconds: 200), () {
                            Navigator.pushReplacementNamed(
                              context,
                              '/login',
                              arguments: {'email': acc['email'] ?? ''},
                            );
                          });
                        },
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 12),
              Divider(),
              SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: Icon(Icons.logout, color: Colors.white),
                  label: Text("Se déconnecter",
                      style: TextStyle(fontSize: buttonFontSize)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (mounted) setState(() {});
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline,
                color: isDarkMode ? Colors.amber : Colors.red, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isDarkMode ? Colors.amber[200] : Colors.white,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Roboto',
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        backgroundColor: isDarkMode ? Color(0xFF222B36) : Color(0xFF1976D2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 8,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _setOnlineInCity(bool online) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _selectedCity == null || _selectedCity!.isEmpty) return;
    final city = _selectedCity!.trim().toLowerCase();
    final ref = FirebaseFirestore.instance
        .collection('city_chats')
        .doc(city)
        .collection('online')
        .doc(user.uid);
    if (online) {
      await ref.set({'at': FieldValue.serverTimestamp()});
    } else {
      await ref.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    final user = FirebaseAuth.instance.currentUser;
    bool isCityEntered = _selectedCity != null && _selectedCity!.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double screenWidth = constraints.maxWidth;
            double screenHeight = constraints.maxHeight;
            double horizontalPadding = screenWidth * 0.01;
            double cardPadding = screenWidth * 0.02;
            double fontTitle = screenWidth * 0.065;
            double fontSubtitle = screenWidth * 0.045;
            double fontNormal = screenWidth * 0.032;
            double buttonHeight = screenHeight * 0.055;
            double buttonFont = screenWidth * 0.038;
            double buttonMinWidth = screenWidth * 0.92;

            return Container(
              width: screenWidth,
              height: screenHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDarkMode
                      ? [Color(0xFF0F1419), Color(0xFF2A2F32)]
                      : [Color(0xFFE3F2FD), Color(0xFFBBDEFB)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      SizedBox(height: screenHeight * 0.012),
                      // Barre du haut : bouton réglages multi-comptes + switch mode sombre
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: Icon(Icons.settings,
                                color: isDarkMode
                                    ? Colors.white
                                    : Color(0xFF1976D2),
                                size: screenWidth * 0.07),
                            onPressed: _showAccountsModal,
                            tooltip: "Comptes enregistrés",
                          ),
                          Row(
                            children: [
                              Icon(Icons.wb_sunny,
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : Color(0xFF1976D2),
                                  size: fontNormal * 1.2),
                              Switch(
                                value: isDarkMode,
                                onChanged: (value) {
                                  Provider.of<ThemeProvider>(context,
                                          listen: false)
                                      .toggleTheme(value);
                                },
                                activeColor: Color(0xFF34AADC),
                                activeTrackColor:
                                    Color(0xFF34AADC).withOpacity(0.5),
                                inactiveThumbColor: Colors.grey[400],
                                inactiveTrackColor: Colors.grey[500],
                              ),
                              Icon(Icons.nightlight_round,
                                  color: isDarkMode
                                      ? Color(0xFF34AADC)
                                      : Colors.grey[500],
                                  size: fontNormal * 1.2),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.008),
                      // Titre et sous-titre
                      Column(
                        children: [
                          Text(
                            "LocoFest",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: fontTitle,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode
                                  ? Color(0xFF34AADC)
                                  : Color(0xFF1976D2),
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  blurRadius: 6,
                                  color: Colors.black26,
                                  offset: const Offset(1, 2),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: screenHeight * 0.008),
                          if (user != null && _userPseudo != null)
                            Text(
                              'Bienvenue, $_userPseudo ',
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: fontSubtitle,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode
                                    ? Colors.white
                                    : Color(0xFF333333),
                              ),
                            )
                          else
                            Text(
                              "Bienvenue sur LocoFest",
                              style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: fontSubtitle,
                                fontWeight: FontWeight.w500,
                                color: isDarkMode
                                    ? Colors.white
                                    : Color(0xFF333333),
                              ),
                            ),
                          SizedBox(height: screenHeight * 0.008),
                          Text(
                            "Découvrez, partagez et vivez vos événements en toute simplicité.",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: fontNormal,
                              color: isDarkMode
                                  ? Colors.white70
                                  : Color(0xFF666666),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.012),
                      // Card ville + boutons
                      Card(
                        elevation: 6,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: isDarkMode
                            ? Colors.black12.withOpacity(0.2)
                            : Colors.white.withOpacity(0.9),
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Choisissez votre ville",
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: fontSubtitle,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode
                                      ? Color(0xFF34AADC)
                                      : Color(0xFF1976D2),
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: screenHeight * 0.008),
                              TextField(
                                controller: _cityController,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Color(0xFF2A2F32)
                                      : Color(0xFFF5F6FA),
                                  hintText: "Entrez votre ville",
                                  hintStyle: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: fontNormal,
                                    color: isDarkMode
                                        ? Colors.grey[400]
                                        : Color(0xFFB0BEC5),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: isDarkMode
                                            ? Color(0xFF34AADC)
                                            : Color(0xFF1976D2),
                                        width: 1.5),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: isDarkMode
                                            ? Color(0xFF34AADC)
                                            : Color(0xFF1976D2),
                                        width: 1.5),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: isDarkMode
                                            ? Color(0xFF34AADC)
                                            : Color(0xFF1976D2),
                                        width: 2),
                                  ),
                                  prefixIcon: Icon(Icons.location_city,
                                      color: isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF1976D2),
                                      size: screenWidth * 0.055),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: fontNormal,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Color(0xFF333333),
                                ),
                              ),
                              SizedBox(height: screenHeight * 0.006),
                              if (user == null) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: Icon(Icons.arrow_forward,
                                        size: buttonFont * 1.1,
                                        color: Colors.white),
                                    label: Text("Continuer sans connexion",
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: buttonFont)),
                                    onPressed: () async {
                                      if (isCityEntered) {
                                        await _setOnlineInCity(true);
                                        Navigator.pushNamed(
                                          context,
                                          '/events',
                                          arguments: {
                                            'city': _selectedCity,
                                          },
                                        );
                                      } else {
                                        _showErrorSnackBar(context,
                                            "Veuillez entrer une ville pour continuer");
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize:
                                          Size(buttonMinWidth, buttonHeight),
                                      backgroundColor: isDarkMode
                                          ? Color(0xFF00C73C)
                                          : Color(0xFF4CAF50),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      elevation: 6,
                                    ),
                                  ),
                                ),
                                SizedBox(height: screenHeight * 0.006),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: Icon(Icons.login,
                                        size: buttonFont * 1.1,
                                        color: Colors.white),
                                    label: Text("Continuer et se connecter",
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: buttonFont)),
                                    onPressed: () {
                                      if (isCityEntered) {
                                        Navigator.pushNamed(
                                          context,
                                          '/login',
                                          arguments: {
                                            'city': _selectedCity,
                                          },
                                        );
                                      } else {
                                        _showErrorSnackBar(context,
                                            "Veuillez entrer une ville pour continuer");
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize:
                                          Size(buttonMinWidth, buttonHeight),
                                      backgroundColor: isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF1976D2),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      elevation: 6,
                                    ),
                                  ),
                                ),
                              ] else ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    icon: Icon(Icons.arrow_forward,
                                        size: buttonFont * 1.1,
                                        color: Colors.white),
                                    label: Text("Continuer",
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: buttonFont)),
                                    onPressed: () async {
                                      if (isCityEntered) {
                                        await _setOnlineInCity(true);
                                        Navigator.pushNamed(
                                          context,
                                          '/events',
                                          arguments: {
                                            'city': _selectedCity,
                                          },
                                        );
                                      } else {
                                        _showErrorSnackBar(context,
                                            "Veuillez entrer une ville pour continuer");
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      minimumSize:
                                          Size(buttonMinWidth, buttonHeight),
                                      backgroundColor: isDarkMode
                                          ? Color(0xFF00C73C)
                                          : Color(0xFF4CAF50),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      elevation: 6,
                                    ),
                                  ),
                                ),
                                if (_myPrivateCalendars.isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(
                                        top: screenHeight * 0.006),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.lock_clock,
                                            size: screenWidth * 0.055,
                                            color: isDarkMode
                                                ? Color(0xFF34AADC)
                                                : Color(0xFF1976D2)),
                                        label: Text("Mes accès privés",
                                            style: TextStyle(
                                                fontFamily: 'Roboto',
                                                fontSize: buttonFont)),
                                        onPressed: () {
                                          Navigator.pushNamed(
                                            context,
                                            '/my_private_calendars',
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: Size(
                                              buttonMinWidth, buttonHeight),
                                          backgroundColor: isDarkMode
                                              ? Colors.grey[800]
                                              : Color(0xFFBBDEFB),
                                          foregroundColor: isDarkMode
                                              ? Color(0xFF34AADC)
                                              : Color(0xFF1976D2),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                          elevation: 6,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                              SizedBox(height: screenHeight * 0.006),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: Icon(Icons.vpn_key,
                                      size: screenWidth * 0.055,
                                      color: Colors.white),
                                  label: Text("Accéder à un événement privé",
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: buttonFont)),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/private_access',
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    minimumSize:
                                        Size(buttonMinWidth, buttonHeight),
                                    backgroundColor: isDarkMode
                                        ? Color(0xFF34AADC)
                                        : Color(0xFF1976D2),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    elevation: 6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.015),
                      // Astuce (s'agrandit dynamiquement)
                      GestureDetector(
                        onTap: _showNextTip,
                        child: Card(
                          elevation: 6,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          color:
                              isDarkMode ? Colors.grey[850] : Color(0xFFFFF3E0),
                          margin: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.03),
                          child: Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                              vertical: screenHeight * 0.03,
                              horizontal: screenWidth * 0.04,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.lightbulb,
                                    color: isDarkMode
                                        ? Color(0xFF00C73C)
                                        : Color(0xFFFF9800),
                                    size: screenWidth * 0.055),
                                SizedBox(width: screenWidth * 0.02),
                                Expanded(
                                  child: Text(
                                    _tips[_currentTipIndex],
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal * 1.1,
                                      color: isDarkMode
                                          ? Colors.white70
                                          : Color(0xFF333333),
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: null,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                                SizedBox(width: screenWidth * 0.02),
                                Icon(Icons.touch_app,
                                    color: isDarkMode
                                        ? Color(0xFF34AADC)
                                        : Color(0xFF1976D2),
                                    size: screenWidth * 0.045),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.02),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
