import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChoosePseudoPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const ChoosePseudoPage({this.arguments, super.key});

  @override
  State<ChoosePseudoPage> createState() => _ChoosePseudoPageState();
}

class _ChoosePseudoPageState extends State<ChoosePseudoPage> {
  final TextEditingController _pseudoController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _city;
  bool _isOrganizer = false;

  @override
  void initState() {
    super.initState();
    if (widget.arguments != null) {
      _city = widget.arguments!['city'] as String?;
      _isOrganizer = widget.arguments!['isOrganizer'] ?? false;
    }
  }

  Future<bool> _isPseudoUnique(String pseudo) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('pseudo', isEqualTo: pseudo)
        .get();
    return query.docs.isEmpty;
  }

  Future<void> _savePseudo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final pseudo = _pseudoController.text.trim();
    if (pseudo.isEmpty) {
      setState(() {
        _error = "Veuillez entrer un pseudonyme.";
        _isLoading = false;
      });
      return;
    }
    if (pseudo.length < 3) {
      setState(() {
        _error = "Le pseudonyme doit faire au moins 3 caractères.";
        _isLoading = false;
      });
      return;
    }
    if (!RegExp(r"^[a-zA-Z0-9_\-]+$").hasMatch(pseudo)) {
      setState(() {
        _error = "Utilisez uniquement lettres, chiffres, _ ou -";
        _isLoading = false;
      });
      return;
    }
    final isUnique = await _isPseudoUnique(pseudo);
    if (!isUnique) {
      setState(() {
        _error = "Ce pseudonyme est déjà pris. Choisissez-en un autre.";
        _isLoading = false;
      });
      return;
    }
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({'pseudo': pseudo});
        // Redirection selon le rôle
        if (_isOrganizer) {
          Navigator.pushReplacementNamed(
            context,
            '/profile',
            arguments: {'city': _city, 'isOrganizer': true},
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            '/profile_user',
            arguments: {'city': _city, 'isOrganizer': false},
          );
        }
      }
    } catch (e) {
      setState(() {
        _error = "Erreur lors de l'enregistrement : $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Choisir un pseudonyme"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.person, color: Color(0xFF2196F3), size: 48),
                const SizedBox(height: 16),
                TextField(
                  controller: _pseudoController,
                  decoration: InputDecoration(
                    labelText: "Pseudonyme",
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.alternate_email),
                    errorText: _error,
                  ),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _savePseudo,
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text("Confirmer"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "Votre pseudonyme sera visible par les autres utilisateurs.",
                  style: TextStyle(color: Colors.black54, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
