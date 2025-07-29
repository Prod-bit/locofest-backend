import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';

class LoginPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const LoginPage({this.arguments, super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pseudoController = TextEditingController();
  DateTime? _birthDate;

  bool _isLogin = true;
  String? _selectedCity;

  bool _isButtonDisabled = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            widget.arguments;
    if (args != null) {
      _selectedCity ??= args['city'] as String?;
      if (args['email'] != null && args['email'].toString().isNotEmpty) {
        _emailController.text = args['email'];
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pseudoController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(String message) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isDarkMode ? Color(0xFFB00020) : Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _saveAccountLocally(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    if (data != null) {
      final prefs = await SharedPreferences.getInstance();
      List<String> accounts = prefs.getStringList('localAccounts') ?? [];
      // Format: uid|pseudo|email|certif
      final certif = (data['role'] ?? data['creatorRole'] ?? '');
      final entry =
          '${user.uid}|${data['pseudo'] ?? ''}|${user.email ?? ''}|$certif';
      // Retire doublon éventuel
      accounts.removeWhere((a) => a.startsWith('${user.uid}|'));
      accounts.add(entry);
      await prefs.setStringList('localAccounts', accounts);
    }
  }

  Future<void> _checkTermsAccepted(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final termsAccepted = doc.data()?['termsAccepted'] ?? false;

    // Correction : si pas de ville, va sur /home
    if (_selectedCity == null || _selectedCity!.isEmpty) {
      Navigator.pushReplacementNamed(context, '/home');
      return;
    }

    if (termsAccepted == true) {
      Navigator.pushReplacementNamed(context, '/profile', arguments: {
        'city': _selectedCity,
      });
    } else {
      Navigator.pushReplacementNamed(
        context,
        '/terms',
        arguments: {
          'city': _selectedCity,
        },
      );
    }
  }

  Future<void> _signIn() async {
    if (!mounted) return;
    setState(() {
      _isButtonDisabled = true;
      _isLoading = true;
    });
    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      User? user = userCredential.user;
      await user?.reload();
      user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        if (!user.emailVerified) {
          _showErrorSnackBar(
            "Merci de valider votre adresse e-mail via le lien reçu avant de vous connecter.",
          );
          await FirebaseAuth.instance.signOut();
          setState(() {
            _isButtonDisabled = false;
            _isLoading = false;
          });
          return;
        } else {
          await _saveAccountLocally(user); // <-- Sauvegarde locale du compte
          await _checkTermsAccepted(user);
        }
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar(_formatError(e));
    } catch (e) {
      _showErrorSnackBar("Erreur de connexion : ${_formatError(e)}");
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _signUp() async {
    if (!mounted) return;
    setState(() {
      _isButtonDisabled = true;
      _isLoading = true;
    });

    final pseudo = _pseudoController.text.trim();
    if (pseudo.isEmpty) {
      _showErrorSnackBar("Veuillez choisir un pseudo.");
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
      return;
    }

    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('pseudo', isEqualTo: pseudo)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      _showErrorSnackBar(
          "Ce pseudo est déjà utilisé. Merci d'en choisir un autre.");
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
      return;
    }

    if (_birthDate == null) {
      _showErrorSnackBar("Veuillez sélectionner votre date de naissance.");
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
      return;
    }
    final now = DateTime.now();
    final age = now.year -
        _birthDate!.year -
        ((now.month < _birthDate!.month ||
                (now.month == _birthDate!.month && now.day < _birthDate!.day))
            ? 1
            : 0);
    if (age < 16) {
      _showErrorSnackBar(
          "Vous devez avoir au moins 16 ans pour vous inscrire.");
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
      return;
    }

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      final User? user = userCredential.user;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': _emailController.text.trim(),
          'pseudo': pseudo,
          'city': _selectedCity,
          'birthDate': _birthDate,
          'subscriptionStatus': 'inactive',
          'subscriptionEndDate': null,
          'favoriteEvents': [],
          'termsAccepted': false,
        });
        await user.sendEmailVerification();
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        _showErrorSnackBar(
          "Un e-mail de vérification a été envoyé à ${_emailController.text.trim()}.\nClique sur le lien reçu avant de te connecter.",
        );
        setState(() {
          _isLogin = true;
        });
      }
    } on FirebaseAuthException catch (e) {
      _showErrorSnackBar(_formatError(e));
    } catch (e) {
      _showErrorSnackBar("Erreur d'inscription : ${_formatError(e)}");
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _isButtonDisabled = false;
        _isLoading = false;
      });
    }
  }

  String _formatError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-email':
          return "L'adresse e-mail n'est pas valide.";
        case 'email-already-in-use':
          return "Cet e-mail est déjà utilisé.";
        case 'weak-password':
          return "Le mot de passe est trop faible (minimum 6 caractères).";
        case 'user-not-found':
          return "Aucun compte trouvé avec cet e-mail.";
        case 'wrong-password':
          return "Mot de passe incorrect.";
        case 'too-many-requests':
          return "Trop de tentatives. Veuillez réessayer plus tard.";
        case 'network-request-failed':
          return "Problème de connexion Internet. Vérifiez votre réseau.";
        case 'missing-email':
          return "Veuillez entrer une adresse e-mail.";
        case 'missing-password':
          return "Veuillez entrer un mot de passe.";
        default:
          return e.message != null && e.message!.isNotEmpty
              ? _firebaseMessageToFrench(e.message!)
              : "Erreur inconnue.";
      }
    }
    return e.toString();
  }

  String _firebaseMessageToFrench(String msg) {
    if (msg.contains("The email address is badly formatted")) {
      return "L'adresse e-mail n'est pas valide.";
    }
    if (msg.contains("Password should be at least 6 characters")) {
      return "Le mot de passe doit contenir au moins 6 caractères.";
    }
    if (msg.contains("There is no user record")) {
      return "Aucun compte trouvé avec cet e-mail.";
    }
    if (msg.contains("The password is invalid")) {
      return "Mot de passe incorrect.";
    }
    if (msg.contains("A network error")) {
      return "Problème de connexion Internet.";
    }
    return msg;
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final List<Color> backgroundGradient = isDarkMode
        ? [Color(0xFF0F1419), Color(0xFF2A2F32)]
        : [Color(0xFFE3F2FD), Color(0xFFBBDEFB)];

    double formMaxWidth = screenWidth < 400 ? screenWidth * 0.97 : 400;
    double iconSize = screenWidth * 0.10;
    double titleFontSize = screenWidth * 0.07;
    double subtitleFontSize = screenWidth * 0.045;
    double fieldFontSize = screenWidth * 0.04;
    double buttonFontSize = screenWidth * 0.045;
    double buttonPadding = screenHeight * 0.012;
    double fieldPadding = screenHeight * 0.012;

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
                child: Container(
                  width: formMaxWidth,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.05,
                    vertical: screenHeight * 0.03,
                  ),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Color(0xFF2A2F32) : Colors.white,
                    borderRadius: BorderRadius.circular(screenWidth * 0.06),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person,
                        color: isDarkMode ? Color(0xFF34AADC) : Colors.blue,
                        size: iconSize,
                        semanticLabel: "Icône utilisateur",
                      ),
                      SizedBox(height: screenHeight * 0.012),
                      Text(
                        _isLogin ? "Connexion" : "Inscription",
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Color(0xFF34AADC) : Colors.blue,
                        ),
                      ),
                      if (_selectedCity != null && _selectedCity!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(
                              vertical: screenHeight * 0.006),
                          child: Text(
                            "Ville : $_selectedCity",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: subtitleFontSize,
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black54,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      SizedBox(height: screenHeight * 0.018),
                      Container(
                        margin: EdgeInsets.only(bottom: fieldPadding),
                        child: TextField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: "Email",
                            labelStyle: TextStyle(
                              fontFamily: 'Roboto',
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black87,
                              fontSize: fieldFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(screenWidth * 0.03),
                            ),
                            prefixIcon: Icon(Icons.email,
                                color: isDarkMode
                                    ? Color(0xFF34AADC)
                                    : Color(0xFF2196F3),
                                size: screenWidth * 0.05),
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.grey[850]
                                : Color(0xFFF5F6FA),
                          ),
                          style: TextStyle(
                            fontSize: fieldFontSize,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      Container(
                        margin: EdgeInsets.only(bottom: fieldPadding),
                        child: TextField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: "Mot de passe",
                            labelStyle: TextStyle(
                              fontFamily: 'Roboto',
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black87,
                              fontSize: fieldFontSize,
                              fontWeight: FontWeight.w600,
                            ),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(screenWidth * 0.03),
                            ),
                            prefixIcon: Icon(Icons.lock,
                                color: isDarkMode
                                    ? Color(0xFF34AADC)
                                    : Color(0xFF2196F3),
                                size: screenWidth * 0.05),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                size: screenWidth * 0.05,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            filled: true,
                            fillColor: isDarkMode
                                ? Colors.grey[850]
                                : Color(0xFFF5F6FA),
                          ),
                          obscureText: _obscurePassword,
                          style: TextStyle(
                            fontSize: fieldFontSize,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      if (!_isLogin) ...[
                        Container(
                          margin: EdgeInsets.only(bottom: fieldPadding),
                          child: TextField(
                            controller: _pseudoController,
                            decoration: InputDecoration(
                              labelText: "Pseudo",
                              labelStyle: TextStyle(
                                fontFamily: 'Roboto',
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black87,
                                fontSize: fieldFontSize,
                                fontWeight: FontWeight.w600,
                              ),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(screenWidth * 0.03),
                              ),
                              prefixIcon: Icon(Icons.person,
                                  color: isDarkMode
                                      ? Color(0xFF34AADC)
                                      : Color(0xFF2196F3),
                                  size: screenWidth * 0.05),
                              filled: true,
                              fillColor: isDarkMode
                                  ? Colors.grey[850]
                                  : Color(0xFFF5F6FA),
                            ),
                            style: TextStyle(
                              fontSize: fieldFontSize,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _isButtonDisabled
                              ? null
                              : () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: DateTime(
                                        now.year - 18, now.month, now.day),
                                    firstDate: DateTime(now.year - 100),
                                    lastDate: now,
                                    helpText:
                                        "Sélectionnez votre date de naissance",
                                    locale: const Locale('fr'),
                                  );
                                  if (picked != null) {
                                    setState(() {
                                      _birthDate = picked;
                                    });
                                  }
                                },
                          child: AbsorbPointer(
                            child: Container(
                              margin: EdgeInsets.only(bottom: fieldPadding),
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: "Date de naissance",
                                  hintText: "JJ/MM/AAAA",
                                  labelStyle: TextStyle(
                                    fontFamily: 'Roboto',
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black87,
                                    fontSize: fieldFontSize,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  prefixIcon: Icon(Icons.cake,
                                      color: isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF2196F3),
                                      size: screenWidth * 0.05),
                                  filled: true,
                                  fillColor: isDarkMode
                                      ? Colors.grey[850]
                                      : Color(0xFFF5F6FA),
                                ),
                                controller: TextEditingController(
                                  text: _birthDate == null
                                      ? ""
                                      : "${_birthDate!.day.toString().padLeft(2, '0')}/"
                                          "${_birthDate!.month.toString().padLeft(2, '0')}/"
                                          "${_birthDate!.year}",
                                ),
                                enabled: false,
                                style: TextStyle(
                                  fontSize: fieldFontSize,
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: screenHeight * 0.008),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _isButtonDisabled
                              ? null
                              : () {
                                  Navigator.pushNamed(
                                      context, '/forgot_password',
                                      arguments: {'city': _selectedCity});
                                },
                          child: Text(
                            "Mot de passe oublié ?",
                            style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: buttonFontSize,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode
                                  ? Color(0xFF34AADC)
                                  : Color(0xFF2196F3),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.012),
                      if (_isLoading)
                        Padding(
                          padding:
                              EdgeInsets.symmetric(vertical: buttonPadding),
                          child: CircularProgressIndicator(),
                        ),
                      if (!_isLoading)
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _isButtonDisabled
                                      ? null
                                      : (_isLogin ? _signIn : _signUp),
                                  child: Text(
                                    _isLogin ? "Connexion" : "Inscription",
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: buttonFontSize,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isDarkMode
                                        ? Color(0xFF34AADC)
                                        : Colors.blue,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      vertical: buttonPadding,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          screenWidth * 0.03),
                                    ),
                                    elevation: 3,
                                  ),
                                ),
                              ),
                              SizedBox(width: screenWidth * 0.03),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isButtonDisabled
                                      ? null
                                      : () {
                                          setState(() {
                                            _isLogin = !_isLogin;
                                          });
                                        },
                                  child: Text(
                                    _isLogin ? "Inscription" : "Connexion",
                                    style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: buttonFontSize,
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF2196F3),
                                    ),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF2196F3),
                                      width: 2,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      vertical: buttonPadding,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(
                                          screenWidth * 0.03),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(height: screenHeight * 0.012),
                      TextButton(
                        onPressed: _isButtonDisabled
                            ? null
                            : () {
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/home',
                                  arguments: {'city': _selectedCity},
                                );
                              },
                        child: Text(
                          "Annuler",
                          style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: buttonFontSize,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF2196F3),
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
