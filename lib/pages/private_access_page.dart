import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivateAccessPage extends StatefulWidget {
  const PrivateAccessPage({Key? key}) : super(key: key);

  @override
  State<PrivateAccessPage> createState() => _PrivateAccessPageState();
}

class _PrivateAccessPageState extends State<PrivateAccessPage> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  final Color mainBlue = const Color(0xFF2196F3);
  final Color mainBlueLight = const Color(0xFFE3F2FD);
  final Color mainBlueDark = const Color(0xFF1976D2);

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _checkInviteCode() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final code = _codeController.text.trim();
    if (code.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      _showErrorBanner(
        "Veuillez entrer un code de validation.",
        isWarning: true,
      );
      return;
    }

    try {
      final query = await FirebaseFirestore.instance
          .collection('private_calendars')
          .where('inviteCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        final user = FirebaseAuth.instance.currentUser;

        // Vérifie si l'utilisateur est connecté
        if (user != null) {
          final userRef =
              FirebaseFirestore.instance.collection('users').doc(user.uid);
          final userSnap = await userRef.get();
          final userData = userSnap.data();
          List<String> visited =
              List<String>.from(userData?['visitedPrivateCalendars'] ?? []);
          if (!visited.contains(doc.id)) {
            visited.add(doc.id);
            await userRef.update({'visitedPrivateCalendars': visited});
          }

          // Ajoute l'utilisateur dans entries du calendrier privé (PAS dans chaque event)
          final calendarRef = FirebaseFirestore.instance
              .collection('private_calendars')
              .doc(doc.id);

          final calendarSnap = await calendarRef.get();
          final entries = (calendarSnap.data()?['entries'] ?? []) as List;
          final already =
              entries.any((e) => e is Map && e['userId'] == user.uid);
          if (!already) {
            await calendarRef.update({
              'entries': FieldValue.arrayUnion([
                {
                  'userId': user.uid,
                  'pseudo': user.displayName ?? '',
                  'timestamp': Timestamp.now(),
                }
              ])
            });
          }
        }

        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(
          '/private_calendar',
          arguments: {
            'calendarId': doc.id,
            'calendarName': doc['name'] ?? 'Calendrier privé',
            'ownerId': doc['ownerId'],
          },
        );
      } else {
        if (!mounted) return;
        _showErrorBanner(
          "Code invalide ou calendrier privé supprimé.",
          isWarning: false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorBanner(
        "Erreur lors de la vérification : $e",
        isWarning: false,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showErrorBanner(String message, {bool isWarning = false}) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDarkMode = themeProvider.isDarkMode;
    final Color bgColor = isWarning
        ? (isDarkMode ? Colors.amber[800]! : Colors.amber[200]!)
        : (isDarkMode ? Colors.red[700]! : Colors.red[400]!);
    final Color textColor = isDarkMode ? Colors.black : Colors.black87;
    final IconData icon = isWarning ? Icons.info_rounded : Icons.error_rounded;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: textColor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'SF Pro Text',
                  ),
                ),
              ),
            ],
          ),
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive variables
    final double padding = screenWidth * 0.06; // ~24 sur 400px
    final double cardPadding = screenWidth * 0.06;
    final double cardRadius = screenWidth * 0.06;
    final double iconSize = screenWidth * 0.12; // ~48 sur 400px
    final double titleFontSize = screenWidth * 0.06; // ~24 sur 400px
    final double textFontSize = screenWidth * 0.038; // ~15 sur 400px
    final double buttonFontSize = screenWidth * 0.04; // ~16 sur 400px
    final double buttonPadding = screenWidth * 0.035; // ~14 sur 400px
    final double margin = screenWidth * 0.06; // ~24 sur 400px

    final Color background =
        isDarkMode ? const Color(0xFF181C20) : mainBlueLight;
    final Color cardColor = isDarkMode ? const Color(0xFF2A2F32) : Colors.white;
    final Color textColor = isDarkMode ? Colors.white : Colors.black87;
    final Color labelColor = isDarkMode ? Colors.white70 : mainBlue;

    final List<Color> backgroundGradient = isDarkMode
        ? [const Color(0xFF0F1419), const Color(0xFF2A2F32)]
        : [mainBlueLight, mainBlue];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: backgroundGradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(padding),
                child: Container(
                  padding: EdgeInsets.all(cardPadding),
                  constraints: BoxConstraints(
                    maxWidth: 430,
                    minWidth: 0,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(cardRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: cardPadding * 0.7,
                        offset: Offset(0, cardPadding * 0.33),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: mainBlue.withOpacity(isDarkMode ? 0.2 : 0.08),
                          shape: BoxShape.circle,
                        ),
                        padding: EdgeInsets.all(cardPadding * 0.75),
                        child: Icon(
                          Icons.lock,
                          size: iconSize,
                          color: isDarkMode ? mainBlue : mainBlueDark,
                          semanticLabel: "Icône cadenas",
                        ),
                      ),
                      SizedBox(height: cardPadding * 0.5),
                      Text(
                        "Accès privé",
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? mainBlue : mainBlueDark,
                        ),
                      ),
                      SizedBox(height: cardPadding * 0.25),
                      Text(
                        "Entrez le code de validation fourni par l'organisateur pour accéder à un calendrier privé.",
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: textFontSize,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: cardPadding),
                      TextField(
                        controller: _codeController,
                        style: TextStyle(
                          color: textColor,
                          fontFamily: 'Roboto',
                          fontSize: textFontSize,
                        ),
                        decoration: InputDecoration(
                          labelText: "Code de validation",
                          labelStyle: TextStyle(
                            fontFamily: 'Roboto',
                            color: labelColor,
                            fontSize: textFontSize,
                          ),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(cardRadius * 0.5),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDarkMode ? mainBlue : mainBlueDark,
                              width: 1.5,
                            ),
                            borderRadius:
                                BorderRadius.circular(cardRadius * 0.5),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDarkMode ? mainBlue : mainBlueDark,
                              width: 2,
                            ),
                            borderRadius:
                                BorderRadius.circular(cardRadius * 0.5),
                          ),
                          prefixIcon: Icon(Icons.vpn_key,
                              color: isDarkMode ? mainBlue : mainBlueDark),
                          filled: true,
                          fillColor: isDarkMode
                              ? Colors.grey[850]
                              : const Color(0xFFF5F6FA),
                          counterText: "",
                          contentPadding: EdgeInsets.symmetric(
                            vertical: cardPadding * 0.7,
                            horizontal: cardPadding * 0.8,
                          ),
                        ),
                        enabled: !_isLoading,
                        textAlign: TextAlign.center,
                        maxLength: 64,
                        cursorColor: labelColor,
                        onSubmitted: (_) {
                          if (!_isLoading) _checkInviteCode();
                        },
                      ),
                      SizedBox(height: cardPadding),
                      if (_isLoading)
                        Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: cardPadding * 0.7),
                          child: SizedBox(
                            width: iconSize * 0.7,
                            height: iconSize * 0.7,
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      if (!_isLoading)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _checkInviteCode,
                                child: Text(
                                  "Confirmer",
                                  style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: buttonFontSize,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      isDarkMode ? mainBlue : mainBlueDark,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                      vertical: buttonPadding),
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(cardRadius * 0.5),
                                  ),
                                  elevation: 6,
                                  disabledBackgroundColor: isDarkMode
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                ),
                              ),
                            ),
                          ],
                        ),
                      SizedBox(height: cardPadding * 0.7),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.pop(context);
                              },
                        child: Text(
                          "Annuler",
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            color: isDarkMode ? mainBlue : mainBlueDark,
                            fontSize: buttonFontSize,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
