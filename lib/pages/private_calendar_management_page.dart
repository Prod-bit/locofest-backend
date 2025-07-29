import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivateCalendarManagementPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const PrivateCalendarManagementPage({Key? key, this.arguments})
      : super(key: key);

  @override
  State<PrivateCalendarManagementPage> createState() =>
      _PrivateCalendarManagementPageState();
}

class _PrivateCalendarManagementPageState
    extends State<PrivateCalendarManagementPage> {
  int _selectedTab = 0; // 0: Créer, 1: Accès
  final TextEditingController _calendarNameController = TextEditingController();
  bool _isCreating = false;
  String? _createError;

  late final Stream<User?> _authStream;

  @override
  void initState() {
    super.initState();
    _authStream = FirebaseAuth.instance.authStateChanges();
  }

  Future<String> _getUserPseudo(String userId) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return (doc.data()?['pseudo'] ?? '') as String;
  }

  Future<String> _getUserRole(String userId) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    return (doc.data()?['role'] ?? 'user') as String;
  }

  Future<int> _getMaxPrivateEvents(String userId) async {
    final role = await _getUserRole(userId);
    if (role == 'boss') return 9999;
    if (role == 'premium') return 9999;
    if (role == 'organizer') return 10;
    return 3;
  }

  Future<int> _getPrivateCalendarsCount(String userId) async {
    final query = await FirebaseFirestore.instance
        .collection('private_calendars')
        .where('ownerId', isEqualTo: userId)
        .get();
    return query.docs.length;
  }

  Future<void> _createPrivateCalendar(User? user) async {
    final name = _calendarNameController.text.trim();
    final userId = user?.uid ?? '';
    if (name.isEmpty) {
      if (!mounted) return;
      setState(() => _createError = "Le nom est obligatoire.");
      return;
    }
    if (userId.isEmpty) {
      if (!mounted) return;
      setState(() =>
          _createError = "Vous devez être connecté pour créer un groupe.");
      return;
    }

    final count = await _getPrivateCalendarsCount(userId);
    final maxPrivateEvents = await _getMaxPrivateEvents(userId);

    if (count >= maxPrivateEvents) {
      if (!mounted) return;
      setState(() => _createError =
          "Le nombre maximum de groupes ($maxPrivateEvents) est atteint. Supprimez-en un pour pouvoir en créer un nouveau.");
      return;
    }

    if (!mounted) return;
    setState(() {
      _isCreating = true;
      _createError = null;
    });
    try {
      final inviteCode = const Uuid().v4();
      final docRef =
          await FirebaseFirestore.instance.collection('private_calendars').add({
        'name': name,
        'ownerId': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'inviteCode': inviteCode,
        'canalAllowMembers': true,
        'ville': widget.arguments?['city'] ?? '',
        'bossIds': <String>[],
        'entries': [],
      });
      await docRef.collection('members').doc(userId).set({
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });
      _calendarNameController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Groupe créé "), backgroundColor: Colors.green),
      );
      setState(() {
        _selectedTab = 1;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _createError = "Erreur : $e");
    } finally {
      if (!mounted) return;
      setState(() => _isCreating = false);
    }
  }

  Future<void> _deletePrivateCalendar(
      String calendarId, String calendarName) async {
    bool confirmed = false;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Supprimer \"$calendarName\" ?",
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        content: Text(
            "Cette action supprimera définitivement ce groupe et toutes ses données associées (membres, commentaires, canal, etc).",
            style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.8))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Annuler",
                style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              confirmed = true;
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Supprimer"),
          ),
        ],
        backgroundColor: Theme.of(context).dialogBackgroundColor,
      ),
    );
    if (!confirmed) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('private_calendars')
          .doc(calendarId);

      final members = await docRef.collection('members').get();
      for (var doc in members.docs) {
        await doc.reference.delete();
      }
      final comments = await docRef.collection('comments').get();
      for (var doc in comments.docs) {
        await doc.reference.delete();
      }
      final canal = await docRef.collection('canal').get();
      for (var doc in canal.docs) {
        await doc.reference.delete();
      }

      await docRef.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Groupe \"$calendarName\" supprimé."),
            backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erreur lors de la suppression : $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  Widget _buildHeader(User? user, bool isDark, Color mainBlue, double iconSize,
      double titleFontSize) {
    final userId = user?.uid ?? '';
    return FutureBuilder<DocumentSnapshot>(
      future: userId.isNotEmpty
          ? FirebaseFirestore.instance.collection('users').doc(userId).get()
          : Future.value(null),
      builder: (context, snapshot) {
        String pseudo = '';
        if (snapshot.hasData && snapshot.data != null) {
          pseudo = snapshot.data!.get('pseudo') ?? '';
        }
        return Padding(
          padding: EdgeInsets.all(iconSize * 0.7),
          child: Row(
            children: [
              CircleAvatar(
                radius: iconSize * 1.1,
                backgroundColor: isDark ? mainBlue : Colors.grey[200],
                child: Icon(Icons.person,
                    color: isDark ? Colors.white : mainBlue,
                    size: iconSize * 1.2),
              ),
              SizedBox(width: iconSize * 0.7),
              Expanded(
                child: Text(
                  pseudo.isNotEmpty
                      ? "Connecté en tant que : $pseudo"
                      : "Connecté",
                  style: TextStyle(
                    fontSize: titleFontSize * 0.82,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : mainBlue,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final mainBlue = const Color(0xFF2196F3);
    final mainBlueLight = const Color(0xFFE3F2FD);
    final accentBlue = const Color(0xFF34AADC);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.05;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.048;
    final double buttonFontSize = screenWidth * 0.042;
    final double buttonPadding = screenHeight * 0.012;
    final double infoFontSize = screenWidth * 0.034;
    final double infoIconSize = screenWidth * 0.06;

    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        final user = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            leading: Container(
              margin: EdgeInsets.only(left: 8, top: 4, bottom: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : mainBlueLight,
                borderRadius: BorderRadius.circular(cardRadius * 1.2),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black38 : mainBlue.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: IconButton(
                icon: Icon(Icons.arrow_back,
                    color: isDark ? Colors.white70 : mainBlue,
                    size: iconSize * 1.3),
                tooltip: "Retour",
                onPressed: () => Navigator.pop(context),
              ),
            ),
            title: Text(
              "Gestion des groupes",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: titleFontSize * 1.1,
                color: Colors.white,
              ),
            ),
            backgroundColor: isDark ? const Color(0xFF2A2F32) : mainBlue,
            elevation: 4,
            shadowColor: isDark ? Colors.black38 : const Color(0xFF0D47A1),
            centerTitle: true,
          ),
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF181C24), const Color(0xFF232A36)]
                    : [Color(0xFFF7FBFF), Color(0xFFB3E5FC)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Onglets
                  Container(
                    margin: EdgeInsets.symmetric(
                        vertical: cardPadding * 0.6,
                        horizontal: cardPadding * 1.2),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[900] : Colors.white,
                      borderRadius: BorderRadius.circular(cardRadius * 1.7),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black26
                              : Colors.blue.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _selectedTab == 0
                                    ? (isDark ? mainBlue : mainBlue)
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(cardRadius * 1.7),
                              ),
                              padding:
                                  EdgeInsets.symmetric(vertical: buttonPadding),
                              alignment: Alignment.center,
                              child: Text(
                                "Créer",
                                style: TextStyle(
                                  color: _selectedTab == 0
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : mainBlue),
                                  fontWeight: FontWeight.bold,
                                  fontSize: buttonFontSize * 0.95,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedTab = 1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _selectedTab == 1
                                    ? (isDark ? mainBlue : mainBlue)
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(cardRadius * 1.7),
                              ),
                              padding:
                                  EdgeInsets.symmetric(vertical: buttonPadding),
                              alignment: Alignment.center,
                              child: Text(
                                "Accès",
                                style: TextStyle(
                                  color: _selectedTab == 1
                                      ? Colors.white
                                      : (isDark ? Colors.white70 : mainBlue),
                                  fontWeight: FontWeight.bold,
                                  fontSize: buttonFontSize * 0.95,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (user != null)
                    _buildHeader(
                        user, isDark, mainBlue, iconSize, titleFontSize),
                  // Afficher la phrase explicative seulement dans l'onglet "Créer"
                  if (_selectedTab == 0)
                    Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: cardPadding * 0.7,
                          vertical: cardPadding * 0.15),
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF23272F) : Colors.white,
                          borderRadius: BorderRadius.circular(cardRadius * 1.1),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withOpacity(0.07)
                                  : Colors.blue.withOpacity(0.06),
                              blurRadius: 7,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: isDark
                                ? Colors.blueGrey[800]!
                                : Colors.blue[50]!,
                            width: 1,
                          ),
                        ),
                        padding: EdgeInsets.symmetric(
                            vertical: cardPadding * 0.35,
                            horizontal: cardPadding * 0.4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: infoIconSize * 1.1,
                              height: infoIconSize * 1.1,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.blue[200]
                                    : Colors.blue[100],
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  "i",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.blue[900]
                                        : Colors.blue[700],
                                    fontWeight: FontWeight.w600,
                                    fontSize: infoFontSize * 1.1,
                                    fontFamily: 'SF Pro Display',
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: cardPadding * 0.25),
                            Expanded(
                              child: Text(
                                "Un groupe vous permet de gérer un calendrier d’événements privé, accessible uniquement sur invitation. Partagez le code à vos membres pour qu’ils puissent rejoindre votre groupe.",
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.grey[800],
                                  fontSize: infoFontSize * 0.85,
                                  fontWeight: FontWeight.w400,
                                  height: 1.25,
                                  fontFamily: 'SF Pro Display',
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: _selectedTab == 0
                          ? _buildCreateTab(
                              user,
                              isDark,
                              mainBlue,
                              cardPadding,
                              cardRadius,
                              titleFontSize,
                              cardFontSize,
                              iconSize,
                              buttonFontSize,
                              buttonPadding)
                          : _buildAccessTab(
                              user,
                              isDark,
                              mainBlue,
                              mainBlueLight,
                              accentBlue,
                              cardPadding,
                              cardRadius,
                              titleFontSize,
                              cardFontSize,
                              iconSize,
                              buttonFontSize,
                              buttonPadding),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCreateTab(
      User? user,
      bool isDark,
      Color mainBlue,
      double cardPadding,
      double cardRadius,
      double titleFontSize,
      double cardFontSize,
      double iconSize,
      double buttonFontSize,
      double buttonPadding) {
    final userId = user?.uid ?? '';
    return FutureBuilder<int>(
      future: userId.isNotEmpty
          ? _getPrivateCalendarsCount(userId)
          : Future.value(0),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return FutureBuilder<int>(
          future: userId.isNotEmpty
              ? _getMaxPrivateEvents(userId)
              : Future.value(3),
          builder: (context, maxSnapshot) {
            final maxPrivateEvents = maxSnapshot.data ?? 3;
            final isLimitReached = count >= maxPrivateEvents;
            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: cardPadding * 2),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: cardPadding * 1.2, vertical: cardPadding * 0.7),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(cardRadius * 1.5)),
                  color: isDark
                      ? Colors.grey[850]
                      : Colors.white.withOpacity(0.97),
                  child: Padding(
                    padding: EdgeInsets.all(cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.group,
                                color: isDark ? mainBlue : mainBlue,
                                size: iconSize * 1.2),
                            SizedBox(width: cardPadding * 0.5),
                            Flexible(
                              child: Text(
                                "Créer un groupe",
                                style: TextStyle(
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? mainBlue : mainBlue,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: cardPadding * 1.1),
                        TextField(
                          controller: _calendarNameController,
                          decoration: InputDecoration(
                            labelText: "Nom du groupe",
                            labelStyle: TextStyle(
                                color: isDark ? Colors.white70 : mainBlue),
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(cardRadius * 0.8),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.white70 : mainBlue),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(cardRadius * 0.8),
                              borderSide: BorderSide(
                                  color: isDark ? Colors.white : mainBlue,
                                  width: 2),
                            ),
                            enabled: !isLimitReached,
                          ),
                          style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: cardFontSize * 1.1),
                        ),
                        if (_createError != null)
                          Padding(
                            padding: EdgeInsets.only(top: cardPadding * 0.3),
                            child: Text(
                              _createError!,
                              style: TextStyle(
                                  color: isDark ? Colors.red[300] : Colors.red,
                                  fontSize: cardFontSize),
                            ),
                          ),
                        if (isLimitReached)
                          Padding(
                            padding: EdgeInsets.only(top: cardPadding * 0.3),
                            child: Builder(
                              builder: (context) {
                                if (maxPrivateEvents == 3) {
                                  // User simple
                                  return Text(
                                    "Le nombre maximum de groupes ($maxPrivateEvents) est atteint. Pour en créer plus, demandez à devenir organisateur.",
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.orange[300]
                                            : Colors.orange,
                                        fontSize: cardFontSize),
                                  );
                                } else if (maxPrivateEvents == 10) {
                                  // Organizer actif
                                  return Text(
                                    "Limite atteinte pour les organisateurs actifs ($maxPrivateEvents). Passez Premium pour créer plus de groupes.",
                                    style: TextStyle(
                                        color: isDark
                                            ? Colors.orange[300]
                                            : Colors.orange,
                                        fontSize: cardFontSize),
                                  );
                                } else {
                                  // Premium ou boss : pas de limite
                                  return const SizedBox.shrink();
                                }
                              },
                            ),
                          ),
                        SizedBox(height: cardPadding * 1.1),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCreating || isLimitReached
                                ? null
                                : () => _createPrivateCalendar(user),
                            icon: _isCreating
                                ? SizedBox(
                                    width: iconSize * 0.9,
                                    height: iconSize * 0.9,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Icon(Icons.add, size: iconSize),
                            label: Text(
                              "Créer le groupe",
                              style: TextStyle(fontSize: buttonFontSize),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark ? mainBlue : mainBlue,
                              foregroundColor: Colors.white,
                              padding:
                                  EdgeInsets.symmetric(vertical: buttonPadding),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(cardRadius),
                              ),
                              elevation: 6,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAccessTab(
      User? user,
      bool isDark,
      Color mainBlue,
      Color mainBlueLight,
      Color accentBlue,
      double cardPadding,
      double cardRadius,
      double titleFontSize,
      double cardFontSize,
      double iconSize,
      double buttonFontSize,
      double buttonPadding) {
    final userId = user?.uid ?? '';
    if (userId.isEmpty) {
      return const Center(
        child: Text(
          "Vous devez être connecté pour voir vos groupes.",
          style: TextStyle(color: Colors.red),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('private_calendars')
          .where('ownerId', isEqualTo: userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final calendars = snapshot.data?.docs ?? [];
        return calendars.isEmpty
            ? const Center(
                child: Text(
                  "Aucun groupe créé pour l’instant.",
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.all(cardPadding * 0.8),
                itemCount: calendars.length,
                separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[800] : Colors.blue[50]),
                itemBuilder: (context, index) {
                  final calendar = calendars[index];
                  final name = calendar['name'] ?? 'Sans nom';
                  final inviteCode = calendar['inviteCode'] ?? '';
                  return Card(
                    elevation: 10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(cardRadius * 1.5),
                      side: BorderSide(
                          color: isDark ? Colors.grey[700]! : mainBlueLight,
                          width: 1),
                    ),
                    color: isDark
                        ? Colors.grey[900]
                        : Colors.white.withOpacity(0.97),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(cardPadding * 0.9),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontSize: titleFontSize * 0.9,
                          fontWeight: FontWeight.bold,
                          color: isDark ? mainBlue : mainBlue,
                        ),
                      ),
                      subtitle: Text(
                        "Appuyez pour voir les options",
                        style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                            fontSize: cardFontSize),
                      ),
                      onTap: () {
                        _showCalendarAccessDialog(
                          calendar.id,
                          name,
                          inviteCode,
                          isDark,
                          mainBlue,
                          accentBlue,
                          cardPadding,
                          cardRadius,
                          titleFontSize,
                          cardFontSize,
                          iconSize,
                          buttonFontSize,
                          buttonPadding,
                        );
                      },
                      trailing: IconButton(
                        icon: Icon(Icons.delete,
                            color: isDark ? Colors.red[300] : Colors.red,
                            size: iconSize * 1.1),
                        tooltip: "Supprimer",
                        onPressed: () =>
                            _deletePrivateCalendar(calendar.id, name),
                      ),
                    ),
                  );
                },
              );
      },
    );
  }

  void _showCalendarAccessDialog(
    String calendarId,
    String name,
    String inviteCode,
    bool isDark,
    Color mainBlue,
    Color accentBlue,
    double cardPadding,
    double cardRadius,
    double titleFontSize,
    double cardFontSize,
    double iconSize,
    double buttonFontSize,
    double buttonPadding,
  ) {
    String codeShort =
        inviteCode.length > 5 ? "${inviteCode.substring(0, 5)}..." : inviteCode;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius * 2),
        ),
        elevation: 16,
        backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
        child: Padding(
          padding: EdgeInsets.all(cardPadding * 1.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.groups,
                  color: isDark ? accentBlue : mainBlue, size: iconSize * 2.2),
              SizedBox(height: cardPadding * 0.5),
              Text(
                "Groupe",
                style: TextStyle(
                  fontSize: titleFontSize * 1.2,
                  fontWeight: FontWeight.bold,
                  color: isDark ? accentBlue : mainBlue,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: cardPadding * 0.2),
              Text(
                name,
                style: TextStyle(
                  fontSize: cardFontSize * 1.2,
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              SizedBox(height: cardPadding * 0.8),
              Text(
                "Code d'invitation",
                style: TextStyle(
                  fontSize: cardFontSize * 1.05,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: cardPadding * 0.2),
              Container(
                margin: EdgeInsets.symmetric(vertical: cardPadding * 0.1),
                padding: EdgeInsets.symmetric(
                    vertical: cardPadding * 0.35,
                    horizontal: cardPadding * 0.8),
                decoration: BoxDecoration(
                  color: isDark
                      ? accentBlue.withOpacity(0.13)
                      : mainBlue.withOpacity(0.09),
                  borderRadius: BorderRadius.circular(cardRadius * 1.2),
                ),
                child: Text(
                  codeShort,
                  style: TextStyle(
                    fontSize: cardFontSize * 1.25,
                    fontWeight: FontWeight.bold,
                    color: isDark ? accentBlue : mainBlue,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
              SizedBox(height: cardPadding * 0.7),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Code copié !",
                                style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87)),
                            backgroundColor:
                                isDark ? Colors.green[700] : Colors.green,
                          ),
                        );
                      },
                      icon: Icon(Icons.copy, size: iconSize * 0.95),
                      label: Text("Copier",
                          style: TextStyle(fontSize: buttonFontSize)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? accentBlue.withOpacity(0.18)
                            : mainBlue.withOpacity(0.13),
                        foregroundColor: isDark ? accentBlue : mainBlue,
                        elevation: 0,
                        padding:
                            EdgeInsets.symmetric(vertical: buttonPadding * 0.9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(cardRadius * 1.1),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: cardPadding * 0.7),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          '/private_calendar',
                          arguments: {
                            'calendarId': calendarId,
                            'calendarName': name,
                          },
                        );
                      },
                      icon: Icon(Icons.lock_clock, size: iconSize * 0.95),
                      label: Text("S'y rendre",
                          style: TextStyle(fontSize: buttonFontSize)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? mainBlue : mainBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            EdgeInsets.symmetric(vertical: buttonPadding * 0.9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(cardRadius * 1.1),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: cardPadding * 0.5),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Fermer",
                  style: TextStyle(
                    color: isDark ? accentBlue : mainBlue,
                    fontSize: buttonFontSize,
                    fontWeight: FontWeight.w600,
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
