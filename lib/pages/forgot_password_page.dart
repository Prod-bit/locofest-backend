import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class ForgotPasswordPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const ForgotPasswordPage({this.arguments, super.key});

  @override
  _ForgotPasswordPageState createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _isTyping = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message, {Color color = Colors.red}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _resetPassword() async {
    if (_emailController.text.isEmpty) {
      _showErrorSnackBar("Veuillez entrer une adresse email.");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: _emailController.text.trim());
      _showErrorSnackBar(
        "Un email de réinitialisation a été envoyé. Vérifiez votre boîte mail.",
        color: Colors.green,
      );
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      Navigator.pop(context); // Retour à la page précédente
    } catch (e) {
      _showErrorSnackBar("Erreur : $e. Vérifiez l'email ou essayez plus tard.");
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    // Couleurs et design identiques à login_page.dart
    final mainBlue = const Color(0xFF1976D2);
    final mainBlueLight = const Color(0xFFE3F2FD);
    final mainBlueDark = const Color(0xFF0D47A1);
    final accentBlue = const Color(0xFF34AADC);

    final List<Color> backgroundGradient = isDarkMode
        ? [const Color(0xFF0F1419), const Color(0xFF2A2F32)]
        : [mainBlueLight, mainBlue];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Dégradé de fond harmonisé
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: backgroundGradient,
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            Column(
              children: [
                // Header custom corrigé avec Row pour bon espacement
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(
                      top: 36, left: 0, right: 0, bottom: 18),
                  decoration: BoxDecoration(
                    color: isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded,
                              color: isDarkMode ? Colors.white : mainBlue,
                              size: 26),
                          onPressed: () => Navigator.pop(context),
                          tooltip: "Retour",
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Réinitialisation du mot de passe",
                                style: TextStyle(
                                  color: isDarkMode ? Colors.white : mainBlue,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "Recevez un lien de réinitialisation par e-mail",
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white70
                                      : const Color(0xFF424242),
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.left,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2A2F32)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_reset,
                                color: isDarkMode ? accentBlue : mainBlue,
                                size: 48),
                            const SizedBox(height: 18),
                            Text(
                              "Entrez votre adresse e-mail pour recevoir un lien de réinitialisation.",
                              style: TextStyle(
                                fontSize: 16,
                                color: isDarkMode
                                    ? Colors.white70
                                    : const Color(0xFF424242),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _emailController,
                              onChanged: (value) {
                                setState(() {
                                  _isTyping = value.isNotEmpty;
                                });
                              },
                              decoration: InputDecoration(
                                labelText: "Email",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                prefixIcon: Icon(Icons.email,
                                    color: isDarkMode ? accentBlue : mainBlue),
                                labelStyle: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white70
                                      : const Color(0xFF424242),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode ? accentBlue : mainBlue,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDarkMode
                                        ? Colors.grey[600]!
                                        : Colors.grey[400]!,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                suffixIcon: _isTyping
                                    ? const Icon(Icons.edit,
                                        color: Colors.green)
                                    : null,
                              ),
                              style: TextStyle(
                                color:
                                    isDarkMode ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 24),
                            _isLoading
                                ? const CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  )
                                : ElevatedButton(
                                    onPressed: _resetPassword,
                                    child: const Text("Envoyer"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          isDarkMode ? accentBlue : mainBlue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 12),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: Icon(Icons.arrow_back_ios_new_rounded,
                                  color: isDarkMode ? accentBlue : mainBlue,
                                  size: 18),
                              label: Text("Retour",
                                  style: TextStyle(
                                      color:
                                          isDarkMode ? accentBlue : mainBlue)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
