import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:locofest_new/pages/feedback_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';
import 'city_chat_page.dart';
import 'my_stats_page.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const ProfilePage({Key? key, this.arguments}) : super(key: key);

  @override
  _ProfilePageState createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _requestStatus;
  DateTime? _pendingSince;
  DateTime? _rejectedAt;

  String? _organizerPseudo;
  DateTime? _organizerPseudoLastUpdated;
  final TextEditingController _organizerPseudoController =
      TextEditingController();
  String? _pseudoError;
  bool _isSavingPseudo = false;
  bool _editPseudo = false;

  String _city = '';

  int _pinResetCount = 0;
  DateTime? _lastPinReset;

  static const Color mainBlue = Color(0xFF2196F3);
  static const Color mainBlueLight = Color(0xFFBBDEFB);
  static const Color mainBlueDark = Color(0xFF1565C0);
  static const Color dangerRed = Color(0xFFE53935);
  static const Color greyBg = Color(0xFFF5F5F5);
  static const Color darkBg = Color(0xFF1A252F);

  final Key _futureKey = ValueKey('profile');

  final TextEditingController _eventTitleController = TextEditingController();
  final TextEditingController _eventDateController = TextEditingController();
  final TextEditingController _eventTimeController = TextEditingController();
  final TextEditingController _eventLocationController =
      TextEditingController();
  final TextEditingController _eventDescController = TextEditingController();
  final TextEditingController _eventCategoryController =
      TextEditingController();
  final TextEditingController _eventCityController = TextEditingController();
  DateTime? _selectedEventDate;
  TimeOfDay? _selectedEventTime;
  bool _isAddEventButtonDisabled = false;
  bool _isRecurrent = false;
  String _recurrenceType = 'hebdo';
  int _recurrenceWeekday = DateTime.monday;
  DateTime? _recurrenceEndDate;
  bool _showAddEventDialog = false;

  List<XFile> _selectedImages = [];

  Future<Map<String, dynamic>?> _fetchUserData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        if (data['role'] == 'premium' &&
            data['subscriptionStatus'] != 'active') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'role': 'organizer',
            'subscriptionStatus': 'active',
          });
          data['role'] = 'organizer';
          data['subscriptionStatus'] = 'active';
        }
        return data;
      }
    }
    return null;
  }

  Future<void> _loadRequestStatus(Map<String, dynamic> userData) async {
    if (userData.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _requestStatus = userData['organizerRequestStatus'];
        if (_requestStatus == "pending" &&
            userData['organizerRequestDate'] != null) {
          final raw = userData['organizerRequestDate'];
          if (raw is Timestamp) {
            _pendingSince = raw.toDate();
          } else if (raw is int) {
            _pendingSince = DateTime.fromMillisecondsSinceEpoch(raw);
          }
        }
        if (_requestStatus == "rejected" &&
            userData['organizerRejectedAt'] != null) {
          final raw = userData['organizerRejectedAt'];
          if (raw is Timestamp) {
            _rejectedAt = raw.toDate();
          } else if (raw is int) {
            _rejectedAt = DateTime.fromMillisecondsSinceEpoch(raw);
          }
        }
        if (userData['lastPinReset'] != null) {
          final raw = userData['lastPinReset'];
          if (raw is Timestamp) {
            _lastPinReset = raw.toDate();
          } else if (raw is int) {
            _lastPinReset = DateTime.fromMillisecondsSinceEpoch(raw);
          }
        }
        _pinResetCount = userData['pinResetCount'] ?? 0;
      });
    }
  }

  Future<void> _loadOrganizerPseudo(Map<String, dynamic> userData) async {
    if (!mounted) return;
    setState(() {
      _organizerPseudo = userData['pseudo'] ?? '';
      _organizerPseudoController.text = _organizerPseudo ?? '';
      _organizerPseudoLastUpdated =
          (userData['pseudoLastUpdated'] as Timestamp?)?.toDate();
    });
  }

  Future<bool> _isPseudoUnique(String pseudo) async {
    final user = FirebaseAuth.instance.currentUser;
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('pseudo', isEqualTo: pseudo)
        .limit(1)
        .get();
    for (final doc in query.docs) {
      if (doc.id != user?.uid) {
        return false;
      }
    }
    return true;
  }

  Future<void> _saveOrganizerPseudo() async {
    if (!mounted) return;
    setState(() {
      _isSavingPseudo = true;
      _pseudoError = null;
    });
    final pseudo = _organizerPseudoController.text.trim();
    if (pseudo.isEmpty || pseudo.length < 3) {
      if (!mounted) return;
      setState(() {
        _pseudoError = "Le pseudonyme doit faire au moins 3 caractères.";
        _isSavingPseudo = false;
      });
      return;
    }
    if (!RegExp(r"^[a-zA-Z0-9_\-]+$").hasMatch(pseudo)) {
      if (!mounted) return;
      setState(() {
        _pseudoError = "Utilisez uniquement lettres, chiffres, _ ou -";
        _isSavingPseudo = false;
      });
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user!.uid)
        .get();
    final userData = userDoc.data() ?? {};
    final role = userData['role'] ?? '';
    final subscriptionStatus = userData['subscriptionStatus'] ?? '';

    if (pseudo != _organizerPseudo) {
      final isUnique = await _isPseudoUnique(pseudo);
      if (!isUnique) {
        if (!mounted) return;
        setState(() {
          _pseudoError = "Ce pseudonyme est déjà pris.";
          _isSavingPseudo = false;
        });
        return;
      }
    }

    if (!((role == 'premium' && subscriptionStatus == 'active') ||
        role == 'boss')) {
      if (_organizerPseudoLastUpdated != null &&
          DateTime.now().difference(_organizerPseudoLastUpdated!).inDays < 14) {
        if (!mounted) return;
        setState(() {
          final nextDate = _organizerPseudoLastUpdated!.add(Duration(days: 14));
          _pseudoError =
              "Vous ne pouvez changer votre pseudonyme que tous les 14 jours.\nProchain changement possible le ${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}.";
          _isSavingPseudo = false;
        });
        return;
      }
    }

    try {
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'pseudo': pseudo,
          'pseudoLastUpdated': Timestamp.now(),
        });
        if (!mounted) return;
        setState(() {
          _organizerPseudo = pseudo;
          _organizerPseudoLastUpdated = DateTime.now();
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Pseudonyme mis à jour"),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pseudoError = "Erreur lors de la mise à jour : $e";
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSavingPseudo = false;
      });
    }
  }

  String _roleToFrench(String role) {
    switch (role) {
      case 'boss':
        return 'Boss';
      case 'organizer':
        return 'Organisateur';
      case 'premium':
        return 'Premium';
      case 'user':
      default:
        return 'Utilisateur';
    }
  }

  @override
  void initState() {
    super.initState();
    final args = widget.arguments;
    String city = '';
    if (args != null) {
      city = args['ville'] ?? args['city'] ?? '';
    }
    _city = city;
    _eventCityController.text = city;
  }

  @override
  void dispose() {
    _organizerPseudoController.dispose();
    _eventTitleController.dispose();
    _eventDateController.dispose();
    _eventTimeController.dispose();
    _eventLocationController.dispose();
    _eventDescController.dispose();
    _eventCategoryController.dispose();
    _eventCityController.dispose();
    super.dispose();
  }

  Future<void> _confirmAndSignOut() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final bool _isDarkMode = themeProvider.isDarkMode;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Êtes-vous sûr de vouloir vous déconnecter ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Se déconnecter"),
            style: ElevatedButton.styleFrom(
              backgroundColor: dangerRed,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  bool _canResendRequest() {
    if (_requestStatus == "rejected" && _rejectedAt != null) {
      return DateTime.now().difference(_rejectedAt!).inHours >= 24;
    }
    return false;
  }

  bool _isPendingExpired() {
    if (_requestStatus == "pending" && _pendingSince != null) {
      return DateTime.now().difference(_pendingSince!).inHours >= 12;
    }
    return false;
  }

  Future<void> _handlePinReset(
      BuildContext context, String email, String uid) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? lastReset = _lastPinReset;
    int resetCount = _pinResetCount;

    if (lastReset == null || lastReset.isBefore(today)) {
      resetCount = 0;
    }

    if (resetCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text("Vous avez déjà demandé 2 réinitialisations aujourd'hui."),
          backgroundColor: dangerRed,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirmation"),
        content: const Text(
          "Un email de réinitialisation de mot de passe va être envoyé à votre adresse. Continuer",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Envoyer"),
            style: ElevatedButton.styleFrom(
              backgroundColor: mainBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'lastPinReset': Timestamp.fromDate(today),
        'pinResetCount': resetCount + 1,
      });

      if (!mounted) return;
      setState(() {
        _lastPinReset = today;
        _pinResetCount = resetCount + 1;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Un email de réinitialisation a été envoyé."),
          backgroundColor: mainBlue,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de l'envoi de l'email : $e"),
          backgroundColor: dangerRed,
        ),
      );
    }
  }

  Future<List<String>> _uploadEventImages(String eventId) async {
    List<String> urls = [];
    for (int i = 0; i < _selectedImages.length; i++) {
      final file = File(_selectedImages[i].path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('event_images')
          .child('$eventId-$i.jpg');
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();
      urls.add(url);
    }
    return urls;
  }

  Future<void> _addEvent() async {
    setState(() {
      _isAddEventButtonDisabled = true;
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isAddEventButtonDisabled = false;
      });
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() ?? {};
    final String creatorRole = userData['role'] ?? 'user';

    final String title = _eventTitleController.text.trim();
    final String city = _eventCityController.text.trim().isNotEmpty
        ? _eventCityController.text.trim()
        : _city;
    final DateTime? date = _selectedEventDate;
    final TimeOfDay? time = _selectedEventTime;
    final String location = _eventLocationController.text.trim();
    final String description = _eventDescController.text.trim();
    final String category = _eventCategoryController.text.trim();

    if (title.isEmpty ||
        city.isEmpty ||
        date == null ||
        time == null ||
        location.isEmpty ||
        description.isEmpty ||
        category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Merci de remplir tous les champs obligatoires."),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isAddEventButtonDisabled = false;
      });
      return;
    }

    DateTime eventDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    final eventData = {
      'title': title,
      'city': city,
      'date': Timestamp.fromDate(eventDateTime),
      'location': location,
      'description': description,
      'category': category,
      'creatorId': user.uid,
      'createdAt': Timestamp.now(),
      'isRecurrent': _isRecurrent,
      'recurrenceType': _isRecurrent ? _recurrenceType : null,
      'recurrenceWeekday': _isRecurrent && _recurrenceType == 'hebdo'
          ? _recurrenceWeekday
          : null,
      'recurrenceEndDate': _isRecurrent && _recurrenceEndDate != null
          ? Timestamp.fromDate(_recurrenceEndDate!)
          : null,
      'images': [],
      'status': 'approved', // <-- Correction ici pour affichage direct
      'creatorRole': creatorRole,
    };

    try {
      final docRef =
          await FirebaseFirestore.instance.collection('events').add(eventData);

      List<String> imageUrls = [];
      if (_selectedImages.isNotEmpty) {
        imageUrls = await _uploadEventImages(docRef.id);
        await docRef.update({'images': imageUrls});
      }

      if (!mounted) return;
      setState(() {
        _showAddEventDialog = false;
        _eventTitleController.clear();
        _eventDateController.clear();
        _eventTimeController.clear();
        _eventLocationController.clear();
        _eventDescController.clear();
        _eventCategoryController.clear();
        _eventCityController.clear();
        _selectedEventDate = null;
        _selectedEventTime = null;
        _isRecurrent = false;
        _recurrenceEndDate = null;
        _selectedImages.clear();
        _isAddEventButtonDisabled = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Événement ajouté avec succès !"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isAddEventButtonDisabled = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de l'ajout : $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool _isDarkMode = themeProvider.isDarkMode;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.07;
    final double cardFontSize = screenWidth * 0.042;
    final double iconSize = screenWidth * 0.06;
    final double buttonFontSize = screenWidth * 0.045;
    final double avatarRadius = screenWidth * 0.13;
    final double fabSize = screenWidth * 0.12;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: _isDarkMode ? darkBg : greyBg,
        appBar: AppBar(
          title: const Text('Profil'),
          backgroundColor: _isDarkMode ? darkBg : mainBlue,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: iconSize * 2, color: Colors.grey),
              SizedBox(height: cardPadding * 1.5),
              Text(
                "Vous devez être connecté pour accéder à cette page.",
                style: TextStyle(fontSize: cardFontSize * 1.2),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: cardPadding * 1.5),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                child: Text("Se connecter",
                    style: TextStyle(fontSize: buttonFontSize)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: mainBlue,
                  foregroundColor: Colors.white,
                  minimumSize: Size(screenWidth * 0.7, screenHeight * 0.06),
                ),
              ),
              SizedBox(height: cardPadding),
              TextButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/home');
                },
                child: Text("Retour à l'accueil",
                    style: TextStyle(fontSize: cardFontSize)),
              ),
            ],
          ),
        ),
      );
    }

    final List<Color> backgroundGradient =
        _isDarkMode ? [Color(0xFF0F1419), Color(0xFF2A2F32)] : [greyBg, greyBg];
    final Color containerColor = _isDarkMode ? Color(0xFF2A2F32) : Colors.white;

    return Scaffold(
      backgroundColor: _isDarkMode ? darkBg : greyBg,
      appBar: !_showAddEventDialog
          ? PreferredSize(
              preferredSize: Size.fromHeight(screenHeight * 0.13),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isDarkMode
                        ? [Color(0xFF0F1419), Color(0xFF2A2F32)]
                        : [mainBlue, mainBlueDark],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(cardRadius * 2),
                    bottomRight: Radius.circular(cardRadius * 2),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _isDarkMode ? Colors.black38 : Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: cardPadding, vertical: cardPadding * 0.5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: iconSize * 1.1,
                          backgroundColor: mainBlueLight,
                          child: Icon(Icons.person,
                              color: mainBlue, size: iconSize),
                        ),
                        SizedBox(width: cardPadding * 0.7),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Profil',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'SansSerif',
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_on,
                                      color: Colors.amber,
                                      size: iconSize * 0.7),
                                  SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _city.isNotEmpty
                                          ? _city
                                          : "Ville inconnue",
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: (screenWidth * 0.042)
                                            .clamp(13, 16)
                                            .toDouble(),
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'SanFrancisco',
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.visible,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _isDarkMode,
                          onChanged: (val) => themeProvider.toggleTheme(val),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : null,
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
            FutureBuilder<Map<String, dynamic>?>(
              key: _futureKey,
              future: _fetchUserData(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data == null) {
                  return Center(child: CircularProgressIndicator());
                }
                final userData = snapshot.data!;
                final String email = userData['email'] ?? '';
                final String role = userData['role'] ?? 'user';
                final String subscriptionStatus =
                    userData['subscriptionStatus'] ?? 'inactive';
                final String abonnement =
                    subscriptionStatus == 'active' ? 'Actif' : 'Inactif';
                final bool isOrganizer =
                    (role == 'organizer' || role == 'boss');
                final int maxImages = (role == 'boss')
                    ? 5
                    : (role == 'premium' && subscriptionStatus == 'active')
                        ? 3
                        : 1;

                final bool canAddEvent = (role == 'boss') ||
                    (role == 'organizer' && subscriptionStatus == 'active') ||
                    (role == 'premium' && subscriptionStatus == 'active');
                final bool canGoPremium =
                    (role == 'organizer' && subscriptionStatus == 'active') ||
                        role == 'premium' ||
                        role == 'boss';
                final bool isPremiumOrBoss =
                    (role == 'premium' && subscriptionStatus == 'active') ||
                        role == 'boss';

                return Center(
                  child: SingleChildScrollView(
                    child: Container(
                      margin: EdgeInsets.symmetric(
                          horizontal: cardPadding, vertical: cardPadding * 1.5),
                      padding: EdgeInsets.all(cardPadding * 1.5),
                      decoration: BoxDecoration(
                        color: containerColor,
                        borderRadius: BorderRadius.circular(cardRadius * 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: avatarRadius,
                                backgroundColor: mainBlueLight,
                                child: Icon(Icons.person,
                                    size: avatarRadius * 1.15, color: mainBlue),
                              ),
                              SizedBox(height: cardPadding),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        userData['pseudo']
                                                    ?.toString()
                                                    .isNotEmpty ==
                                                true
                                            ? userData['pseudo']
                                            : "Utilisateur",
                                        style: TextStyle(
                                          color: mainBlue,
                                          fontWeight: FontWeight.bold,
                                          fontSize: titleFontSize * 0.8,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  if (userData['role'] == 'premium' &&
                                      userData['subscriptionStatus'] ==
                                          'active')
                                    Icon(Icons.verified,
                                        color: Colors.amber[700],
                                        size: iconSize),
                                  if (userData['role'] == 'boss')
                                    Icon(Icons.verified,
                                        color: Colors.blue, size: iconSize),
                                  IconButton(
                                    icon: Icon(Icons.edit,
                                        size: iconSize * 0.7,
                                        color: mainBlueDark),
                                    tooltip: "Changer mon pseudo",
                                    onPressed: () {
                                      setState(() {
                                        _editPseudo = !_editPseudo;
                                        _organizerPseudoController.text =
                                            userData['pseudo'] ?? '';
                                        _pseudoError = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              if (_editPseudo) ...[
                                SizedBox(height: cardPadding * 0.5),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: screenWidth * 0.85,
                                  ),
                                  child: TextField(
                                    controller: _organizerPseudoController,
                                    style: TextStyle(fontSize: cardFontSize),
                                    decoration: InputDecoration(
                                      labelText: "Nouveau pseudo",
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      contentPadding: EdgeInsets.symmetric(
                                          vertical: 10, horizontal: 12),
                                      counterText: "",
                                    ),
                                    enabled: !_isSavingPseudo,
                                    maxLines: 1,
                                    maxLength: 20,
                                    textAlign: TextAlign.left,
                                  ),
                                ),
                                if (_pseudoError != null &&
                                    _pseudoError!.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    margin: EdgeInsets.only(top: 8, bottom: 8),
                                    padding: EdgeInsets.symmetric(
                                        vertical: 10, horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.red[50],
                                      borderRadius:
                                          BorderRadius.circular(cardRadius),
                                      border:
                                          Border.all(color: Colors.redAccent),
                                    ),
                                    child: Text(
                                      _pseudoError!,
                                      style: TextStyle(
                                        color: Colors.red[900],
                                        fontWeight: FontWeight.w600,
                                        fontSize: (screenWidth * 0.042)
                                            .clamp(13, 16)
                                            .toDouble(),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton(
                                      onPressed: _isSavingPseudo
                                          ? null
                                          : () async {
                                              await _saveOrganizerPseudo();
                                              if (_pseudoError == null) {
                                                setState(() {
                                                  _editPseudo = false;
                                                });
                                              }
                                            },
                                      child: _isSavingPseudo
                                          ? SizedBox(
                                              width: iconSize,
                                              height: iconSize,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : Text("OK",
                                              style: TextStyle(
                                                  fontSize:
                                                      cardFontSize * 0.95)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: mainBlue,
                                        foregroundColor: Colors.white,
                                        minimumSize: Size(44, 36),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 18, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius * 0.7)),
                                      ),
                                    ),
                                    SizedBox(width: cardPadding * 0.5),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _editPseudo = false;
                                          _pseudoError = null;
                                        });
                                      },
                                      child: Text("Annuler",
                                          style: TextStyle(
                                              fontSize: cardFontSize * 0.95)),
                                      style: TextButton.styleFrom(
                                        minimumSize: Size(44, 36),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              SizedBox(height: cardPadding),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.email,
                                      size: iconSize * 0.7, color: mainBlue),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(email,
                                          style: TextStyle(
                                              color: _isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black87,
                                              fontSize: cardFontSize)),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: cardPadding * 0.5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_user,
                                      size: iconSize * 0.7, color: mainBlue),
                                  SizedBox(width: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text("Rôle: ${_roleToFrench(role)}",
                                        style: TextStyle(
                                            color: _isDarkMode
                                                ? Colors.white70
                                                : Colors.black87,
                                            fontSize: cardFontSize)),
                                  ),
                                ],
                              ),
                              SizedBox(height: cardPadding * 0.5),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.subscriptions,
                                      size: iconSize * 0.7, color: mainBlue),
                                  SizedBox(width: 8),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text("Abonnement: $abonnement",
                                        style: TextStyle(
                                            color: _isDarkMode
                                                ? Colors.white70
                                                : Colors.black87,
                                            fontSize: cardFontSize)),
                                  ),
                                ],
                              ),
                              SizedBox(height: cardPadding),
                              if (!(role == 'boss' ||
                                  (role == 'organizer' &&
                                      subscriptionStatus == 'active') ||
                                  (role == 'premium' &&
                                      subscriptionStatus == 'active')))
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/organizer_request',
                                      arguments: {'city': _city},
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: mainBlue,
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(
                                        double.infinity, screenHeight * 0.055),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(cardRadius)),
                                    elevation: 4,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text("Demander à être organisateur",
                                        style: TextStyle(
                                            fontSize: buttonFontSize)),
                                  ),
                                ),
                              if (role == 'boss' ||
                                  (role == 'organizer' &&
                                      subscriptionStatus == 'active') ||
                                  (role == 'premium' &&
                                      subscriptionStatus == 'active'))
                                SizedBox(height: 0)
                              else
                                SizedBox(height: cardPadding),
                              ElevatedButton.icon(
                                onPressed: () {
                                  _handlePinReset(context, email,
                                      FirebaseAuth.instance.currentUser!.uid);
                                },
                                icon: Icon(Icons.lock_reset,
                                    size: iconSize * 0.8),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("Changer mon mot de passe",
                                      style:
                                          TextStyle(fontSize: buttonFontSize)),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mainBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(
                                      double.infinity, screenHeight * 0.055),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(cardRadius)),
                                ),
                              ),
                              SizedBox(height: cardPadding * 0.5),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => FeedbackPage(
                                            isOrganizer: isOrganizer)),
                                  );
                                },
                                icon: Icon(Icons.chat, size: iconSize * 0.8),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("Donner un avis / suggestion",
                                      style:
                                          TextStyle(fontSize: buttonFontSize)),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mainBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(
                                      double.infinity, screenHeight * 0.055),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(cardRadius)),
                                ),
                              ),
                              SizedBox(height: cardPadding * 0.5),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pushNamed(
                                      context, '/private_calendar_management');
                                },
                                icon: Icon(Icons.event, size: iconSize * 0.8),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("Gérer mes événements privés",
                                      style:
                                          TextStyle(fontSize: buttonFontSize)),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: mainBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(
                                      double.infinity, screenHeight * 0.055),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(cardRadius)),
                                ),
                              ),
                              SizedBox(height: cardPadding),
                              ElevatedButton(
                                onPressed: () async {
                                  await _confirmAndSignOut();
                                },
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text("Se déconnecter",
                                      style:
                                          TextStyle(fontSize: buttonFontSize)),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: dangerRed,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(
                                      double.infinity, screenHeight * 0.055),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(cardRadius)),
                                ),
                              ),
                              SizedBox(height: cardPadding),
                              if (!(role == 'boss' ||
                                  (role == 'organizer' &&
                                      subscriptionStatus == 'active') ||
                                  (role == 'premium' &&
                                      subscriptionStatus == 'active')))
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    double fontSize = (screenWidth * 0.038)
                                        .clamp(11, 14)
                                        .toDouble();
                                    if (constraints.maxWidth < 350)
                                      fontSize = 11;
                                    return Container(
                                      margin: EdgeInsets.only(
                                          top: cardPadding * 0.7),
                                      padding: EdgeInsets.symmetric(
                                        vertical: cardPadding * 0.5,
                                        horizontal: cardPadding * 0.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue[50],
                                        borderRadius: BorderRadius.circular(
                                            cardRadius * 1.2),
                                        border: Border.all(
                                            color: mainBlue, width: 1),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(Icons.info_outline,
                                              color: mainBlue, size: iconSize),
                                          SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              "En mode organisateur, vous pourrez gérer vos événements après validation.",
                                              style: TextStyle(
                                                color: mainBlueDark,
                                                fontSize: fontSize,
                                                fontWeight: FontWeight.w600,
                                                fontFamily: 'SanFrancisco',
                                                letterSpacing: 0.1,
                                              ),
                                              textAlign: TextAlign.left,
                                              softWrap: true,
                                              maxLines: null,
                                              overflow: TextOverflow.visible,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                          if (!_showAddEventDialog)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (canGoPremium)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: cardPadding * 0.3),
                                      child: SizedBox(
                                        width: fabSize,
                                        height: fabSize,
                                        child: FloatingActionButton(
                                          heroTag: "premiumBtn",
                                          onPressed: () {
                                            Navigator.pushNamed(
                                                context, '/premium');
                                          },
                                          backgroundColor: Colors.amber[700],
                                          child: Icon(Icons.verified,
                                              color: Colors.white,
                                              size: iconSize),
                                          tooltip:
                                              "Passer Premium (certification)",
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius * 0.8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (canAddEvent)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: cardPadding * 0.3),
                                      child: SizedBox(
                                        width: fabSize,
                                        height: fabSize,
                                        child: FloatingActionButton(
                                          heroTag: "addEventBtn",
                                          onPressed: () {
                                            setState(() {
                                              _showAddEventDialog = true;
                                            });
                                          },
                                          backgroundColor: mainBlue,
                                          child: Icon(Icons.add,
                                              color: Colors.white,
                                              size: iconSize),
                                          tooltip: "Ajouter un événement",
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius * 0.8),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (isPremiumOrBoss)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                          vertical: cardPadding * 0.3),
                                      child: SizedBox(
                                        width: fabSize,
                                        height: fabSize,
                                        child: FloatingActionButton(
                                          heroTag: "statsBtn",
                                          backgroundColor: Colors.deepPurple,
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (context) =>
                                                      MyStatsPage()),
                                            );
                                          },
                                          child: Icon(Icons.bar_chart,
                                              color: Colors.white,
                                              size: iconSize),
                                          tooltip: "Voir mes statistiques",
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius * 0.8),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (_showAddEventDialog)
              GestureDetector(
                onTap: () {
                  setState(() {
                    _showAddEventDialog = false;
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(0.45),
                  width: double.infinity,
                  height: double.infinity,
                  child: Center(
                    child: GestureDetector(
                      onTap: () {},
                      child: SingleChildScrollView(
                        child: Container(
                          width: screenWidth < 400 ? screenWidth * 0.95 : 370,
                          padding: EdgeInsets.only(
                              left: cardPadding * 1.5,
                              top: cardPadding * 1.5,
                              bottom: cardPadding * 1.5,
                              right: cardPadding * 0.5),
                          decoration: BoxDecoration(
                            color: containerColor,
                            borderRadius:
                                BorderRadius.circular(cardRadius * 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 16,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Ajouter un événement",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: titleFontSize * 0.7)),
                              SizedBox(height: cardPadding),
                              FutureBuilder<Map<String, dynamic>?>(
                                future: _fetchUserData(),
                                builder: (context, snapshot) {
                                  final userData = snapshot.data ?? {};
                                  final String role =
                                      userData['role'] ?? 'user';
                                  final String subscriptionStatus =
                                      userData['subscriptionStatus'] ??
                                          'inactive';
                                  final int maxImages = (role == 'boss')
                                      ? 5
                                      : (role == 'premium' &&
                                              subscriptionStatus == 'active')
                                          ? 3
                                          : 1;
                                  return Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (role == 'organizer' &&
                                          subscriptionStatus == 'active')
                                        Container(
                                          margin: EdgeInsets.only(
                                              bottom: cardPadding * 0.7),
                                          padding:
                                              EdgeInsets.all(cardPadding * 0.7),
                                          decoration: BoxDecoration(
                                            color: Colors.orange[100],
                                            borderRadius: BorderRadius.circular(
                                                cardRadius),
                                            border: Border.all(
                                                color: Colors.orange),
                                          ),
                                          child: Text(
                                            "Attention : vous êtes limité à 4 événements par mois. Chaque occurrence d'un événement récurrent compte dans cette limite. Si vous atteignez la limite, vous ne pourrez plus créer d'événements ce mois-ci.",
                                            style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w600,
                                                fontSize: cardFontSize * 0.95),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      if (role == 'premium' &&
                                          subscriptionStatus == 'active')
                                        Container(
                                          margin: EdgeInsets.only(
                                              bottom: cardPadding * 0.7),
                                          padding:
                                              EdgeInsets.all(cardPadding * 0.7),
                                          decoration: BoxDecoration(
                                            color: Colors.yellow[100],
                                            borderRadius: BorderRadius.circular(
                                                cardRadius),
                                            border:
                                                Border.all(color: Colors.amber),
                                          ),
                                          child: Text(
                                            "En tant que Premium, vous pouvez créer jusqu'à 70 événements publics par mois (et pas plus d'un an à l'avance).",
                                            style: TextStyle(
                                                color: Colors.orange,
                                                fontWeight: FontWeight.w600,
                                                fontSize: cardFontSize * 0.95),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      TextField(
                                        controller: _eventTitleController,
                                        style:
                                            TextStyle(fontSize: cardFontSize),
                                        decoration: InputDecoration(
                                          labelText: "Titre de l'événement",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      if (role == 'boss') ...[
                                        TextField(
                                          controller: _eventCityController,
                                          style:
                                              TextStyle(fontSize: cardFontSize),
                                          decoration: InputDecoration(
                                            labelText: "Ville",
                                            border: OutlineInputBorder(),
                                          ),
                                        ),
                                        SizedBox(height: cardPadding * 0.7),
                                      ],
                                      GestureDetector(
                                        onTap: () async {
                                          DateTime? picked =
                                              await showDatePicker(
                                            context: context,
                                            initialDate: _selectedEventDate ??
                                                DateTime.now(),
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime(2030),
                                            locale: const Locale('fr', 'FR'),
                                          );
                                          if (picked != null) {
                                            setState(() {
                                              _selectedEventDate = picked;
                                              _eventDateController.text =
                                                  "${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}";
                                            });
                                          }
                                        },
                                        child: AbsorbPointer(
                                          child: TextField(
                                            controller: _eventDateController,
                                            style: TextStyle(
                                                fontSize: cardFontSize),
                                            decoration: InputDecoration(
                                              labelText: "Date (AAAA/MM/JJ)",
                                              border: OutlineInputBorder(),
                                              suffixIcon:
                                                  Icon(Icons.calendar_today),
                                            ),
                                            readOnly: true,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      GestureDetector(
                                        onTap: () async {
                                          TimeOfDay? picked =
                                              await showTimePicker(
                                            context: context,
                                            initialTime: _selectedEventTime ??
                                                TimeOfDay.now(),
                                            builder: (context, child) {
                                              return Localizations.override(
                                                context: context,
                                                locale:
                                                    const Locale('fr', 'FR'),
                                                child: child!,
                                              );
                                            },
                                          );
                                          if (picked != null) {
                                            setState(() {
                                              _selectedEventTime = picked;
                                              _eventTimeController.text =
                                                  picked.format(context);
                                            });
                                          }
                                        },
                                        child: AbsorbPointer(
                                          child: TextField(
                                            controller: _eventTimeController,
                                            style: TextStyle(
                                                fontSize: cardFontSize),
                                            decoration: InputDecoration(
                                              labelText: "Heure (ex: 18:30)",
                                              border: OutlineInputBorder(),
                                              suffixIcon:
                                                  Icon(Icons.access_time),
                                            ),
                                            readOnly: true,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      TextField(
                                        controller: _eventLocationController,
                                        style:
                                            TextStyle(fontSize: cardFontSize),
                                        decoration: InputDecoration(
                                          labelText: "Lieu",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      TextField(
                                        controller: _eventDescController,
                                        style:
                                            TextStyle(fontSize: cardFontSize),
                                        decoration: InputDecoration(
                                          labelText: "Description",
                                          border: OutlineInputBorder(),
                                        ),
                                        maxLines: 2,
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      TextField(
                                        controller: _eventCategoryController,
                                        style:
                                            TextStyle(fontSize: cardFontSize),
                                        decoration: InputDecoration(
                                          labelText:
                                              "Catégorie (concert, soirée, etc.)",
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          "Photos de l'événement (optionnel, max $maxImages)",
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: cardFontSize),
                                        ),
                                      ),
                                      SizedBox(height: cardPadding * 0.3),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          ..._selectedImages.map((img) => Stack(
                                                alignment: Alignment.topRight,
                                                children: [
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            cardRadius),
                                                    child: Image.file(
                                                      File(img.path),
                                                      width: 70,
                                                      height: 70,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      setState(() {
                                                        _selectedImages
                                                            .remove(img);
                                                      });
                                                    },
                                                    child: Container(
                                                      decoration: BoxDecoration(
                                                        color: Colors.black54,
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(Icons.close,
                                                          color: Colors.white,
                                                          size: 18),
                                                    ),
                                                  ),
                                                ],
                                              )),
                                          if (_selectedImages.length <
                                              maxImages)
                                            GestureDetector(
                                              onTap: () async {
                                                final picker = ImagePicker();
                                                final picked =
                                                    await picker.pickImage(
                                                        source: ImageSource
                                                            .gallery);
                                                if (picked != null) {
                                                  setState(() {
                                                    _selectedImages.add(picked);
                                                  });
                                                }
                                              },
                                              child: Container(
                                                width: 70,
                                                height: 70,
                                                decoration: BoxDecoration(
                                                  color: Colors.grey[200],
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          cardRadius * 1.1),
                                                  border: Border.all(
                                                      color: Colors.grey),
                                                ),
                                                child: Icon(Icons.add_a_photo,
                                                    color: Colors.grey[700]),
                                              ),
                                            ),
                                        ],
                                      ),
                                      SizedBox(height: cardPadding * 0.7),
                                      CheckboxListTile(
                                        value: _isRecurrent,
                                        onChanged: (val) {
                                          setState(() {
                                            _isRecurrent = val ?? false;
                                          });
                                        },
                                        title: Text("Événement répété",
                                            style: TextStyle(
                                                fontSize: cardFontSize)),
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                      ),
                                      if (_isRecurrent) ...[
                                        Row(
                                          children: [
                                            Text("Fréquence :",
                                                style: TextStyle(
                                                    fontSize: cardFontSize)),
                                            SizedBox(width: 8),
                                            DropdownButton<String>(
                                              value: _recurrenceType,
                                              items: [
                                                DropdownMenuItem(
                                                    value: 'hebdo',
                                                    child: Text(
                                                        "Chaque semaine",
                                                        style: TextStyle(
                                                            fontSize:
                                                                cardFontSize))),
                                                DropdownMenuItem(
                                                    value: 'quotidien',
                                                    child: Text("Chaque jour",
                                                        style: TextStyle(
                                                            fontSize:
                                                                cardFontSize))),
                                              ],
                                              onChanged: (val) {
                                                setState(() {
                                                  _recurrenceType = val!;
                                                });
                                              },
                                            ),
                                          ],
                                        ),
                                        if (_recurrenceType == 'hebdo')
                                          Row(
                                            children: [
                                              Text("Jour :",
                                                  style: TextStyle(
                                                      fontSize: cardFontSize)),
                                              SizedBox(width: 8),
                                              DropdownButton<int>(
                                                value: _recurrenceWeekday,
                                                items: [
                                                  DropdownMenuItem(
                                                      value: DateTime.monday,
                                                      child: Text("Lundi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.tuesday,
                                                      child: Text("Mardi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.wednesday,
                                                      child: Text("Mercredi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.thursday,
                                                      child: Text("Jeudi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.friday,
                                                      child: Text("Vendredi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.saturday,
                                                      child: Text("Samedi",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                  DropdownMenuItem(
                                                      value: DateTime.sunday,
                                                      child: Text("Dimanche",
                                                          style: TextStyle(
                                                              fontSize:
                                                                  cardFontSize))),
                                                ],
                                                onChanged: (val) {
                                                  setState(() {
                                                    _recurrenceWeekday = val!;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        SizedBox(height: cardPadding * 0.5),
                                        Row(
                                          children: [
                                            Text("Jusqu'au :",
                                                style: TextStyle(
                                                    fontSize: cardFontSize)),
                                            SizedBox(width: 8),
                                            TextButton(
                                              onPressed: () async {
                                                DateTime? picked =
                                                    await showDatePicker(
                                                  context: context,
                                                  initialDate:
                                                      _recurrenceEndDate ??
                                                          DateTime.now().add(
                                                              Duration(
                                                                  days: 30)),
                                                  firstDate:
                                                      _selectedEventDate ??
                                                          DateTime.now(),
                                                  lastDate: DateTime(2030),
                                                  locale:
                                                      const Locale('fr', 'FR'),
                                                );
                                                if (picked != null) {
                                                  setState(() {
                                                    _recurrenceEndDate = picked;
                                                  });
                                                }
                                              },
                                              child: Text(_recurrenceEndDate ==
                                                      null
                                                  ? "Choisir"
                                                  : "${_recurrenceEndDate!.day.toString().padLeft(2, '0')}/${_recurrenceEndDate!.month.toString().padLeft(2, '0')}/${_recurrenceEndDate!.year}"),
                                            ),
                                          ],
                                        ),
                                      ],
                                      SizedBox(height: cardPadding),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton(
                                            onPressed: () {
                                              setState(() {
                                                _showAddEventDialog = false;
                                                _eventTitleController.clear();
                                                _eventDateController.clear();
                                                _eventTimeController.clear();
                                                _eventLocationController
                                                    .clear();
                                                _eventDescController.clear();
                                                _eventCategoryController
                                                    .clear();
                                                _eventCityController.clear();
                                                _selectedEventDate = null;
                                                _selectedEventTime = null;
                                                _isRecurrent = false;
                                                _recurrenceEndDate = null;
                                                _selectedImages.clear();
                                              });
                                            },
                                            child: Text("Annuler",
                                                style: TextStyle(
                                                    fontSize: cardFontSize)),
                                          ),
                                          SizedBox(width: cardPadding * 0.5),
                                          ElevatedButton(
                                            onPressed: _isAddEventButtonDisabled
                                                ? null
                                                : _addEvent,
                                            child: _isAddEventButtonDisabled
                                                ? SizedBox(
                                                    width: iconSize,
                                                    height: iconSize,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            color:
                                                                Colors.white),
                                                  )
                                                : Text("Enregistrer",
                                                    style: TextStyle(
                                                        fontSize:
                                                            cardFontSize)),
                                          ),
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _isDarkMode ? darkBg : greyBg,
        elevation: 2,
        currentIndex: 4,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
        ],
        selectedItemColor: _isDarkMode ? mainBlue : mainBlue,
        unselectedItemColor: _isDarkMode ? Colors.grey[400] : Color(0xFFD3D3D3),
        selectedIconTheme: IconThemeData(
            size: iconSize * 1.1, color: _isDarkMode ? mainBlue : mainBlue),
        unselectedIconTheme: IconThemeData(
          size: iconSize * 1.1,
          color: _isDarkMode ? Colors.grey[400] : Color(0xFFD3D3D3),
        ),
        onTap: (index) async {
          if (index == 0) {
            bool? confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Retour à l'accueil"),
                content: const Text(
                    "Êtes-vous sûr de vouloir retourner à la page d'accueil"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Annuler"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Oui, retourner"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDarkMode ? dangerRed : dangerRed,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              Navigator.pushReplacementNamed(context, '/home');
            }
          } else if (index == 1) {
            Navigator.pushReplacementNamed(
              context,
              '/events_list',
              arguments: {'city': _city, 'isOrganizer': null},
            );
          } else if (index == 2) {
            Navigator.pushReplacementNamed(
              context,
              '/events',
              arguments: {'city': _city, 'isOrganizer': null},
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CityChatPage(city: _city),
              ),
            );
          } else if (index == 4) {}
        },
      ),
    );
  }
}
