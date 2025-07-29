import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivateProfileFullPage extends StatefulWidget {
  const PrivateProfileFullPage({Key? key}) : super(key: key);

  @override
  State<PrivateProfileFullPage> createState() => _PrivateProfileFullPageState();
}

class _PrivateProfileFullPageState extends State<PrivateProfileFullPage>
    with WidgetsBindingObserver {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pseudoController = TextEditingController();
  DateTime? _birthDate;

  bool _isLogin = true;
  bool _isLoading = false;
  bool _isButtonDisabled = false;
  bool _obscurePassword = true;
  String? _error;
  User? _user;

  DateTime? _pseudoLastUpdated;

  String? _currentCalendarId;
  String? _currentOwnerId;
  bool? _currentIsOwner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      _loadPseudo();
      _checkTermsAccepted(_user!);
      _loadCurrentCalendarInfo();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null) {
      _currentCalendarId = args['calendarId'];
      _currentOwnerId = args['ownerId'];
      _currentIsOwner = args['isOwner'];
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    _pseudoController.dispose();
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  Future<void> _loadPseudo() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .get();
    final data = doc.data();
    if (data != null) {
      if (data['pseudo'] != null) {
        _pseudoController.text = data['pseudo'];
      } else if (_user!.displayName != null) {
        _pseudoController.text = _user!.displayName!;
      }
      if (data['pseudoLastUpdated'] != null) {
        final raw = data['pseudoLastUpdated'];
        if (raw is Timestamp) {
          _pseudoLastUpdated = raw.toDate();
        } else if (raw is int) {
          _pseudoLastUpdated = DateTime.fromMillisecondsSinceEpoch(raw);
        }
      } else {
        _pseudoLastUpdated = null;
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _changePseudo() async {
    final newPseudo = _pseudoController.text.trim();
    if (newPseudo.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = "Le pseudo ne peut pas être vide.";
      });
      _showSnackBar("Le pseudo ne peut pas être vide.", Colors.redAccent);
      return;
    }
    if (_pseudoLastUpdated != null &&
        DateTime.now().difference(_pseudoLastUpdated!).inDays < 7) {
      if (!mounted) return;
      setState(() {
        _error = "Vous ne pouvez changer votre pseudo que tous les 7 jours.";
      });
      _showSnackBar("Vous ne pouvez changer votre pseudo que tous les 7 jours.",
          Colors.orange[700]);
      return;
    }

    // Vérification unicité du pseudo
    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('pseudo', isEqualTo: newPseudo)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty && existing.docs.first.id != _user!.uid) {
      if (!mounted) return;
      setState(() {
        _error = "Ce pseudo est déjà utilisé. Merci d'en choisir un autre.";
      });
      _showSnackBar("Ce pseudo est déjà utilisé. Merci d'en choisir un autre.",
          Colors.redAccent);
      return;
    }

    if (!mounted) return;
    setState(() {
      _isButtonDisabled = true;
      _error = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .update({
        'pseudo': newPseudo,
        'pseudoLastUpdated': Timestamp.now(),
      });
      await _user!.updateDisplayName(newPseudo);
      _pseudoLastUpdated = DateTime.now();
      if (!mounted) return;
      _showSnackBar("Pseudo mis à jour !", Colors.green[700]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur lors du changement de pseudo : $e";
      });
      _showSnackBar(
          "Erreur lors du changement de pseudo : $e", Colors.redAccent);
    } finally {
      if (!mounted) return;
      setState(() {
        _isButtonDisabled = false;
      });
    }
  }

  void _showSnackBar(String message, Color? color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              color == Colors.green[700]
                  ? Icons.check_circle
                  : color == Colors.orange[700]
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline,
              color: Colors.white,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontFamily: 'Roboto',
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color ?? Colors.deepPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _checkTermsAccepted(User user) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final termsAccepted = doc.data()?['termsAccepted'] ?? false;
    if (termsAccepted != true) {
      Navigator.pushReplacementNamed(
        context,
        '/terms',
        arguments: {'city': null, 'fromPrivate': true},
      );
    }
  }

  Future<void> _loadCurrentCalendarInfo() async {
    if (_user == null) return;
    final query = await FirebaseFirestore.instance
        .collection('private_calendars')
        .where('members', arrayContains: _user!.uid)
        .limit(1)
        .get();
    if (query.docs.isNotEmpty) {
      final data = query.docs.first.data();
      if (!mounted) return;
      setState(() {
        _currentCalendarId = query.docs.first.id;
        _currentOwnerId = data['ownerId'];
        _currentIsOwner = data['ownerId'] == _user!.uid;
      });
    }
  }

  Future<void> _signIn() async {
    if (!mounted) return;
    setState(() {
      _isButtonDisabled = true;
      _isLoading = true;
      _error = null;
    });
    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _user = userCredential.user;
      await _user?.reload();
      _user = FirebaseAuth.instance.currentUser;
      if (_user != null) {
        if (!_user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() {
            _error =
                "Merci de valider votre adresse e-mail via le lien reçu avant de vous connecter.";
          });
          _user = null;
          _showSnackBar(
              "Merci de valider votre adresse e-mail via le lien reçu avant de vous connecter.",
              Colors.orange[700]);
          return;
        }
        await _loadPseudo();
        await _checkTermsAccepted(_user!);
        await _loadCurrentCalendarInfo();
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _formatError(e);
      });
      _showSnackBar(_formatError(e), Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de connexion : ${_formatError(e)}";
      });
      _showSnackBar(
          "Erreur de connexion : ${_formatError(e)}", Colors.redAccent);
    } finally {
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
      _error = null;
    });

    // Vérification du pseudo
    final pseudo = _pseudoController.text.trim();
    if (pseudo.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = "Veuillez choisir un pseudo.";
        _isButtonDisabled = false;
        _isLoading = false;
      });
      _showSnackBar("Veuillez choisir un pseudo.", Colors.redAccent);
      return;
    }
    // Vérification unicité du pseudo
    final existing = await FirebaseFirestore.instance
        .collection('users')
        .where('pseudo', isEqualTo: pseudo)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _error = "Ce pseudo est déjà utilisé. Merci d'en choisir un autre.";
        _isButtonDisabled = false;
        _isLoading = false;
      });
      _showSnackBar("Ce pseudo est déjà utilisé. Merci d'en choisir un autre.",
          Colors.redAccent);
      return;
    }

    // Vérification de la date de naissance
    if (_birthDate == null) {
      if (!mounted) return;
      setState(() {
        _error = "Veuillez sélectionner votre date de naissance.";
        _isButtonDisabled = false;
        _isLoading = false;
      });
      _showSnackBar(
          "Veuillez sélectionner votre date de naissance.", Colors.orange[700]);
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
      if (!mounted) return;
      setState(() {
        _error = "Vous devez avoir au moins 16 ans pour vous inscrire.";
        _isButtonDisabled = false;
        _isLoading = false;
      });
      _showSnackBar("Vous devez avoir au moins 16 ans pour vous inscrire.",
          Colors.orange[700]);
      return;
    }

    try {
      final UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _user = userCredential.user;
      await FirebaseFirestore.instance.collection('users').doc(_user!.uid).set({
        'email': _emailController.text.trim(),
        'pseudo': pseudo,
        'birthDate': _birthDate,
        'pseudoLastUpdated': Timestamp.now(),
        'termsAccepted': false,
      });
      await _user!.updateDisplayName(pseudo);
      await _user!.sendEmailVerification();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _isLogin = true;
        _user = null;
        _error =
            "Un e-mail de vérification a été envoyé à ${_emailController.text.trim()}.\nClique sur le lien reçu avant de te connecter.";
      });
      _showSnackBar(
          "Un e-mail de vérification a été envoyé à ${_emailController.text.trim()}.\nClique sur le lien reçu avant de te connecter.",
          Colors.green[700]);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _formatError(e);
      });
      _showSnackBar(_formatError(e), Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur d'inscription : ${_formatError(e)}";
      });
      _showSnackBar(
          "Erreur d'inscription : ${_formatError(e)}", Colors.redAccent);
    } finally {
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final _isDarkMode = themeProvider.isDarkMode;
    final primaryColor = const Color(0xFF1976D2);
    final backgroundColor = const Color(0xFFE0F7FA);
    final accentColor = const Color(0xFF64B5F6);
    final errorColor = const Color(0xFFF44336);

    int daysLeft = 0;
    if (_pseudoLastUpdated != null) {
      daysLeft = 7 - DateTime.now().difference(_pseudoLastUpdated!).inDays;
      if (daysLeft < 0) daysLeft = 0;
    }

    if (_user != null &&
        (_currentCalendarId == null ||
            _currentOwnerId == null ||
            _currentIsOwner == null)) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                "Chargement des informations du calendrier...",
                style:
                    TextStyle(color: _isDarkMode ? Colors.white : primaryColor),
              ),
              Text(
                'DEBUG: _currentCalendarId=$_currentCalendarId, _currentOwnerId=$_currentOwnerId, _currentIsOwner=$_currentIsOwner',
                style: TextStyle(
                    color: Colors.red, fontSize: 12, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 3,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Accueil'),
            BottomNavigationBarItem(
                icon: Icon(Icons.lock_clock), label: 'Calendrier'),
            BottomNavigationBarItem(icon: Icon(Icons.forum), label: 'Canal'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profil'),
          ],
          onTap: (_) {},
          backgroundColor: _isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
        ),
      );
    }

    return Scaffold(
      backgroundColor: _isDarkMode ? const Color(0xFF1A252F) : backgroundColor,
      appBar: AppBar(
        backgroundColor: _isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
        elevation: 0,
        leading: null,
        automaticallyImplyLeading: false,
        title: Text(
          _user == null ? "Mon compte" : "Profil",
          style: TextStyle(
            color: _isDarkMode ? Colors.white : primaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: 1,
          ),
        ),
        centerTitle: true,
        actions: [
          Switch(
            value: _isDarkMode,
            onChanged: (value) {
              themeProvider.toggleTheme(value);
            },
            activeColor: primaryColor,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.grey,
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: Container(
            width: 400,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _isDarkMode ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: _isDarkMode
                      ? Colors.black38
                      : primaryColor.withOpacity(0.08),
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: _user == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_outline,
                          color: _isDarkMode ? Colors.white : primaryColor,
                          size: 80),
                      const SizedBox(height: 24),
                      Text(
                        _isLogin ? "Connexion" : "Inscription",
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _isDarkMode ? Colors.white : primaryColor,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Adresse email",
                          labelStyle: TextStyle(
                              color: _isDarkMode
                                  ? Colors.white70
                                  : Colors.grey[700]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: _isDarkMode
                                    ? Colors.white70
                                    : Colors.grey[400]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color:
                                    _isDarkMode ? Colors.white : primaryColor,
                                width: 2),
                          ),
                          prefixIcon: Icon(Icons.email,
                              color:
                                  _isDarkMode ? Colors.white70 : primaryColor),
                        ),
                        style: TextStyle(
                            color: _isDarkMode ? Colors.white : Colors.black87),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Mot de passe",
                          labelStyle: TextStyle(
                              color: _isDarkMode
                                  ? Colors.white70
                                  : Colors.grey[700]),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color: _isDarkMode
                                    ? Colors.white70
                                    : Colors.grey[400]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                                color:
                                    _isDarkMode ? Colors.white : primaryColor,
                                width: 2),
                          ),
                          prefixIcon: Icon(Icons.lock,
                              color:
                                  _isDarkMode ? Colors.white70 : primaryColor),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color:
                                  _isDarkMode ? Colors.white70 : primaryColor,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ),
                        style: TextStyle(
                            color: _isDarkMode ? Colors.white : Colors.black87),
                      ),
                      if (!_isLogin)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: TextField(
                            controller: _pseudoController,
                            decoration: InputDecoration(
                              labelText: "Pseudo",
                              labelStyle: TextStyle(
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : Colors.grey[700]),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                    color: _isDarkMode
                                        ? Colors.white70
                                        : Colors.grey[400]!),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                    color: _isDarkMode
                                        ? Colors.white
                                        : primaryColor,
                                    width: 2),
                              ),
                              prefixIcon: Icon(Icons.person,
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : primaryColor),
                            ),
                            style: TextStyle(
                                color: _isDarkMode
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                        ),
                      if (!_isLogin)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: GestureDetector(
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
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: "Date de naissance",
                                  hintText: "JJ/MM/AAAA",
                                  prefixIcon: Icon(Icons.cake,
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : primaryColor),
                                  filled: true,
                                  fillColor: _isDarkMode
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
                                  color: _isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            _error!,
                            style: TextStyle(
                                color:
                                    _isDarkMode ? Colors.red[300] : errorColor,
                                fontSize: 14),
                          ),
                        ),
                      if (_isLoading)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: CircularProgressIndicator(
                              color: _isDarkMode ? Colors.white : primaryColor),
                        ),
                      if (!_isLoading)
                        Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isButtonDisabled
                                    ? null
                                    : (_isLogin ? _signIn : _signUp),
                                child: Text(
                                  _isLogin ? "Se connecter" : "S'inscrire",
                                  style: const TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _isDarkMode ? primaryColor : primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 40, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  elevation: 4,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _isButtonDisabled
                                  ? null
                                  : () {
                                      setState(() {
                                        _isLogin = !_isLogin;
                                      });
                                    },
                              child: Text(
                                _isLogin
                                    ? "Pas de compte ? Inscrivez-vous"
                                    : "Déjà inscrit ? Connectez-vous",
                                style: TextStyle(
                                  fontSize: 15,
                                  color:
                                      _isDarkMode ? Colors.white : primaryColor,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              _isDarkMode
                                  ? primaryColor.withOpacity(0.5)
                                  : primaryColor.withOpacity(0.3),
                              _isDarkMode ? primaryColor : primaryColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isDarkMode
                                  ? Colors.black26
                                  : primaryColor.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Icon(Icons.account_circle,
                            size: 80, color: Colors.white),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _pseudoController.text.isNotEmpty
                            ? _pseudoController.text
                            : (_user!.email ?? _user!.uid),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _isDarkMode ? Colors.white : primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _user!.email ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          color:
                              _isDarkMode ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Card(
                        elevation: 0,
                        color: _isDarkMode
                            ? Colors.grey[800]
                            : backgroundColor.withOpacity(0.7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Modifier mon pseudo",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      _isDarkMode ? Colors.white : primaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _pseudoController,
                                decoration: InputDecoration(
                                  labelText: "Pseudo",
                                  labelStyle: TextStyle(
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : Colors.grey[700]),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: _isDarkMode
                                            ? Colors.white70
                                            : Colors.grey[400]!),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                        color: _isDarkMode
                                            ? Colors.white
                                            : primaryColor,
                                        width: 2),
                                  ),
                                  errorText: _error,
                                  prefixIcon: Icon(Icons.person,
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : primaryColor),
                                  helperText: _pseudoLastUpdated == null
                                      ? "Vous pouvez choisir votre pseudo."
                                      : (daysLeft > 0
                                          ? "Vous pourrez le changer dans $daysLeft jour${daysLeft > 1 ? 's' : ''}."
                                          : "Vous pouvez changer votre pseudo."),
                                  helperStyle: TextStyle(
                                    color: _isDarkMode
                                        ? Colors.white70
                                        : Colors.grey,
                                  ),
                                ),
                                enabled: !_isButtonDisabled &&
                                    (_pseudoLastUpdated == null ||
                                        DateTime.now()
                                                .difference(_pseudoLastUpdated!)
                                                .inDays >=
                                            7),
                                style: TextStyle(
                                    color: _isDarkMode
                                        ? Colors.white
                                        : Colors.black87),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isButtonDisabled ||
                                          (_pseudoLastUpdated != null &&
                                              DateTime.now()
                                                      .difference(
                                                          _pseudoLastUpdated!)
                                                      .inDays <
                                                  7)
                                      ? null
                                      : _changePseudo,
                                  icon: Icon(Icons.edit,
                                      size: 18,
                                      color: _isDarkMode
                                          ? accentColor
                                          : accentColor),
                                  label: const Text("Mettre à jour",
                                      style: TextStyle(fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isDarkMode
                                        ? primaryColor
                                        : primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Card(
                        elevation: 0,
                        color: _isDarkMode
                            ? Colors.grey[800]
                            : backgroundColor.withOpacity(0.7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Actions",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color:
                                      _isDarkMode ? Colors.white : primaryColor,
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pushNamed(context, '/feedback');
                                  },
                                  icon: Icon(Icons.feedback,
                                      size: 18,
                                      color: _isDarkMode
                                          ? accentColor
                                          : accentColor),
                                  label: const Text("Donner un avis",
                                      style: TextStyle(fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isDarkMode
                                        ? primaryColor
                                        : primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (!mounted) return;
                                    await FirebaseAuth.instance.signOut();
                                    setState(() {
                                      _user = null;
                                    });
                                  },
                                  icon: Icon(Icons.logout,
                                      size: 18,
                                      color: _isDarkMode
                                          ? accentColor
                                          : accentColor),
                                  label: const Text("Se déconnecter",
                                      style: TextStyle(fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isDarkMode
                                        ? Colors.white
                                        : Colors.white,
                                    foregroundColor: _isDarkMode
                                        ? primaryColor
                                        : primaryColor,
                                    side: BorderSide(
                                        color: primaryColor, width: 2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(14)),
                                    elevation: 2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 3,
        onTap: (index) async {
          if (index == 0) {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Retour à l'accueil"),
                content: const Text(
                    "Voulez-vous vraiment quitter et revenir à l'accueil ?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text("Annuler",
                        style: TextStyle(
                            color: _isDarkMode ? Colors.white : primaryColor)),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Oui"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isDarkMode ? primaryColor : primaryColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
                backgroundColor:
                    _isDarkMode ? const Color(0xFF23272F) : Colors.white,
              ),
            );
            if (confirm == true) {
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (route) => false);
            }
          } else if (index == 1) {
            if (_currentCalendarId != null && _currentOwnerId != null) {
              Navigator.pushReplacementNamed(
                context,
                '/private_calendar',
                arguments: {
                  'calendarId': _currentCalendarId,
                  'calendarName': 'Calendrier privé',
                  'ownerId': _currentOwnerId,
                },
              );
            } else {
              _showSnackBar(
                  "Impossible d'accéder au calendrier : informations manquantes.",
                  Colors.redAccent);
            }
          } else if (index == 2) {
            if (_currentCalendarId != null &&
                _currentOwnerId != null &&
                _currentIsOwner != null) {
              Navigator.pushReplacementNamed(
                context,
                '/canal',
                arguments: {
                  'calendarId': _currentCalendarId,
                  'ownerId': _currentOwnerId,
                  'isOwner': _currentIsOwner,
                },
              );
            } else {
              _showSnackBar(
                  "Impossible d'accéder au canal : informations manquantes.",
                  Colors.redAccent);
            }
          } else if (index == 3) {
            // On reste sur la page profil
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Accueil',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.lock_clock),
            label: 'Calendrier',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.forum),
            label: 'Canal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
        selectedItemColor: primaryColor,
        unselectedItemColor: _isDarkMode ? Colors.grey : Colors.grey,
        type: BottomNavigationBarType.fixed,
        backgroundColor: _isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
      ),
      floatingActionButton: _user != null
          ? FloatingActionButton(
              heroTag: "premium_fab_profile",
              backgroundColor: Colors.amber[700],
              onPressed: () {
                Navigator.pushNamed(context, '/premium');
              },
              child: const Icon(Icons.workspace_premium,
                  color: Colors.white, size: 32),
              tooltip: "Passer Premium (certification)",
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}
