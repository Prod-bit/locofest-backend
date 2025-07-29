import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class PremiumPage extends StatefulWidget {
  const PremiumPage({Key? key}) : super(key: key);

  @override
  State<PremiumPage> createState() => _PremiumPageState();
}

class _PremiumPageState extends State<PremiumPage> {
  bool _isLoading = false;
  bool _isPremium = false;
  DateTime? _premiumEnd;

  @override
  void initState() {
    super.initState();
    _checkIfPremium();
  }

  Future<void> _checkIfPremium() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists && doc['role'] == 'premium') {
      DateTime? premiumEnd;
      if (doc.data()!.containsKey('premiumEnd') && doc['premiumEnd'] != null) {
        premiumEnd = (doc['premiumEnd'] as Timestamp).toDate();
      }
      setState(() {
        _isPremium = true;
        _premiumEnd = premiumEnd;
      });
    }
  }

  // Fonction Stripe Checkout
  Future<void> _payWithStripe() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Appelle ton backend pour créer une session Stripe Checkout
      final response = await http.post(
        Uri.parse('https://ton-backend.com/create-checkout-session'),
        body: {'uid': user.uid},
      );
      if (response.statusCode == 200) {
        final url = response.body; // ton backend doit retourner l'URL Checkout
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors du paiement Stripe."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Erreur réseau ou serveur."),
          backgroundColor: Colors.red,
        ),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double padding = screenWidth * 0.06;
    final double iconSize = screenWidth * 0.18;
    final double titleFontSize = screenWidth * 0.065;
    final double cardFontSize = screenWidth * 0.045;
    final double featureTitleSize = screenWidth * 0.048;
    final double buttonFontSize = screenWidth * 0.045;

    String premiumInfo = '';
    if (_isPremium && _premiumEnd != null) {
      premiumInfo =
          "Votre abonnement Premium est actif jusqu'au ${_premiumEnd!.day.toString().padLeft(2, '0')}/${_premiumEnd!.month.toString().padLeft(2, '0')}/${_premiumEnd!.year}";
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text("Passez à Premium"),
        backgroundColor: Colors.amber[700],
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium,
                  color: Colors.amber[700], size: iconSize),
              SizedBox(height: padding * 0.6),
              Text(
                "Débloquez tout le potentiel de LocoFest",
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: padding * 0.6),
              Container(
                padding: EdgeInsets.all(padding * 0.7),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[900] : Colors.amber[50],
                  borderRadius: BorderRadius.circular(padding * 0.7),
                  border: Border.all(color: Colors.amber),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.verified, color: Colors.amber),
                      title: Text(
                        "Certification Premium",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Votre profil est mis en avant avec une étoile dorée sur tous vos événements, commentaires et dans la messagerie publique.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.event_available,
                          color: Colors.amber),
                      title: Text(
                        "Jusqu'à 70 événements publics/mois",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Publiez jusqu'à 70 événements publics chaque mois, dans toutes les villes.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          const Icon(Icons.photo_library, color: Colors.amber),
                      title: Text(
                        "Jusqu'à 5 photos par événement",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Ajoutez jusqu'à 5 photos pour illustrer chaque événement public ou privé.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_open, color: Colors.amber),
                      title: Text(
                        "Calendriers privés illimités",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Créez et gérez un nombre illimité de calendriers privés pour vos groupes ou associations.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          Icon(Icons.visibility_off, color: Colors.amber[300]),
                      title: Text(
                        "Envoyer des messages en anonyme",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Envoyez des messages anonymes dans les chats généraux, tout en gardant votre certification visible.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.bar_chart_rounded,
                          color: Colors.amber[700]),
                      title: Text(
                        "Statistiques avancées",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Accédez à des tableaux de bord détaillés pour suivre la participation et toutes les statistiques de vos événements et calendriers privés.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: padding * 0.5),
                    const Divider(),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.reviews, color: Colors.amber[700]),
                      title: Text(
                        "Recevez des retours et une note",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: featureTitleSize,
                          letterSpacing: 1,
                          color: isDark ? Colors.amber[300] : Colors.amber,
                        ),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          "Après chaque événement, les participants peuvent laisser un retour et une note sur votre organisation.",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: cardFontSize,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: padding * 0.9),
              if (_isPremium)
                Column(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 40),
                    SizedBox(height: padding * 0.3),
                    const Text(
                      "Vous êtes déjà Premium !",
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    if (premiumInfo.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          premiumInfo,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                )
              else ...[
                FractionallySizedBox(
                  widthFactor: 0.9,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _payWithStripe,
                    icon: const Icon(Icons.workspace_premium,
                        color: Colors.white, size: 20),
                    label: _isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  "Activer Premium",
                                  style: TextStyle(
                                      fontSize: buttonFontSize * 0.92),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  "5 €/mois",
                                  style: TextStyle(
                                    fontSize: buttonFontSize * 0.8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[700],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40),
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 10),
                      textStyle: TextStyle(fontSize: buttonFontSize * 0.92),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
                SizedBox(height: padding * 0.3),
                Text(
                  "Paiement sécurisé via Stripe. Activation sous quelques minutes.",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: cardFontSize * 0.95,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: padding * 0.7),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Retour",
                  style: TextStyle(
                    color: isDark ? Colors.amber[200] : Colors.amber[700],
                    fontSize: cardFontSize * 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
