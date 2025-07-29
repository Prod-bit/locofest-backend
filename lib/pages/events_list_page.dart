import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'city_chat_page.dart';

enum DisplayMode { month, day, week }

class EventsListPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const EventsListPage({Key? key, this.arguments}) : super(key: key);

  @override
  _EventsListPageState createState() => _EventsListPageState();
}

class _EventsListPageState extends State<EventsListPage> {
  DisplayMode _displayMode = DisplayMode.month;
  late List<dynamic> _events;
  String _city = '';
  String _searchQuery = '';
  String _selectedCategory = 'tous';
  bool _isOrganizer = false;
  bool _isBoss = false;
  List<String> _favoriteEvents = [];
  String _searchScope = 'ville';

  final Map<String, TextEditingController> _replyControllers = {};
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    _questionController.dispose();
    _replyControllers.forEach((_, c) => c.dispose());
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _events = [];
    _checkIfBoss();

    final args = widget.arguments;
    if (args != null) {
      setState(() {
        _isOrganizer = args['isOrganizer'] ?? false;
        _city = args['city'] ?? '';
      });
      _checkOrganizerStatus();
      _loadFavoriteEvents();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur de navigation : ville inconnue"),
            backgroundColor: Colors.red,
          ),
        );
      });
    }
  }

  Future<void> _checkIfBoss() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
      if (userData != null && userData['role'] == 'boss') {
        if (!mounted) return;
        setState(() {
          _isBoss = true;
        });
      }
    }
  }

  Future<void> _checkOrganizerStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
      if (userData != null) {
        String subscriptionStatus =
            userData['subscriptionStatus'] ?? 'inactive';
        Timestamp? subscriptionEndDate = userData['subscriptionEndDate'];
        if (subscriptionStatus == 'active' && subscriptionEndDate != null) {
          DateTime endDate = subscriptionEndDate.toDate();
          if (endDate.isAfter(DateTime.now())) {
            if (!mounted) return;
            setState(() {
              _isOrganizer = true;
            });
          }
        }
      }
    }
  }

  Future<void> _loadFavoriteEvents() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
      if (userData != null && userData['favoriteEvents'] != null) {
        if (!mounted) return;
        setState(() {
          _favoriteEvents = List<String>.from(userData['favoriteEvents']);
        });
      }
    }
  }

  Future<void> _toggleFavorite(String eventId) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        if (_favoriteEvents.contains(eventId)) {
          _favoriteEvents.remove(eventId);
        } else {
          _favoriteEvents.add(eventId);
        }
      });
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'favoriteEvents': _favoriteEvents,
      });
      await _loadFavoriteEvents();
    } else {
      _showLoginPrompt();
    }
  }

  void _showLoginPrompt() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding:
            const EdgeInsets.only(top: 18, left: 18, right: 18, bottom: 0),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        actionsPadding: const EdgeInsets.only(bottom: 10, right: 10),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock,
                color: isDarkMode ? Colors.amber : Colors.blue, size: 24),
            SizedBox(width: 8),
            Expanded(
              child: Text("Connexion requise",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isDarkMode ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ],
        ),
        content: Text(
          "Veuillez vous connecter pour utiliser cette fonctionnalité.",
          textAlign: TextAlign.center,
          style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
              fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text("Annuler",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamed(
                context,
                '/login',
                arguments: {
                  'city': _city,
                  'isOrganizer': _isOrganizer,
                },
              );
            },
            child: Text("Se connecter",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
        ],
        backgroundColor: isDarkMode ? Color(0xFF2A2F32) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showStyledDialog(String title, String message,
      {bool error = false, bool appleStyle = false}) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        titlePadding:
            const EdgeInsets.only(top: 18, left: 18, right: 18, bottom: 0),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        actionsPadding: const EdgeInsets.only(bottom: 10, right: 10),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error
                  ? (isDarkMode ? Colors.red[300] : Colors.red)
                  : (isDarkMode ? Colors.green[300] : Colors.green),
              size: 28,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isDarkMode
                        ? (error ? Colors.red[100] : Colors.white)
                        : (error ? Colors.red[800] : Colors.green[800]),
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
              fontSize: 14),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
          ),
        ],
        backgroundColor: isDarkMode ? Color(0xFF23272F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  List<dynamic> _filterEvents(List<dynamic> events) {
    DateTime now = DateTime.now();
    return events.where((event) {
      DateTime eventDate = (event['date'] as Timestamp).toDate();

      bool isFuture = eventDate.isAfter(now);
      bool isToday = eventDate.year == now.year &&
          eventDate.month == now.month &&
          eventDate.day == now.day;

      if (!isFuture && !isToday) return false;

      bool dateMatch = false;
      switch (_displayMode) {
        case DisplayMode.month:
          dateMatch =
              eventDate.year == now.year && eventDate.month == now.month;
          break;
        case DisplayMode.day:
          dateMatch = eventDate.year == now.year &&
              eventDate.month == now.month &&
              eventDate.day == now.day;
          break;
        case DisplayMode.week:
          DateTime startOfWeek = now.subtract(Duration(days: now.weekday - 1));
          DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
          dateMatch = eventDate
                  .isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
              eventDate.isBefore(endOfWeek.add(const Duration(days: 1)));
          break;
      }

      bool categoryMatch = _selectedCategory == 'tous' ||
          (event['category']?.toLowerCase() == _selectedCategory.toLowerCase());

      bool searchMatch = _searchQuery.isEmpty ||
          (event['title']?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false) ||
          (event['description']
                  ?.toLowerCase()
                  .contains(_searchQuery.toLowerCase()) ??
              false) ||
          (event['city']?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
              false);

      return dateMatch && categoryMatch && searchMatch;
    }).toList();
  }

  // Badge certification collé au nom de l'événement
  Widget _buildCertificationBadge(String? role) {
    if (role == 'premium') {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.verified, color: Colors.amber, size: 22),
      );
    } else if (role == 'boss') {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.verified_user, color: Colors.blue, size: 22),
      );
    }
    return SizedBox.shrink();
  }

  String _formatDateFr(DateTime date) {
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (date.hour != 0 || date.minute != 0) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à $heure:$minute";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  void _goToAdminPage() {
    Navigator.pushNamed(context, '/admin_organizer_requests');
  }

  Future<int> getUserSharesThisMonth(User? user, String userRole) async {
    if (user == null) return 0;
    DateTime now = DateTime.now();
    DateTime startOfMonth = DateTime(now.year, now.month, 1);
    QuerySnapshot shares = await FirebaseFirestore.instance
        .collection('event_shares')
        .where('userId', isEqualTo: user.uid)
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .get();
    return shares.docs.length;
  }

  Future<void> participateToEvent(dynamic event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }
    final participations = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: event.id)
        .where('userId', isEqualTo: user.uid)
        .get();
    if (participations.docs.isNotEmpty) {
      for (var doc in participations.docs) {
        await doc.reference.delete();
      }
      if (!mounted) return;
      _showStyledDialog(
          "Désinscription", "Vous êtes désinscrit de l'événement.");
    } else {
      await FirebaseFirestore.instance.collection('event_participations').add({
        'eventId': event.id,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      _showStyledDialog(
          "Participation", "Inscription à l'événement effectuée !");
    }
  }

  Future<bool> isUserParticipating(dynamic event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final participations = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: event.id)
        .where('userId', isEqualTo: user.uid)
        .get();
    return participations.docs.isNotEmpty;
  }

  Future<void> shareEventToCityChat(
      dynamic event, String city, String userRole) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() as Map<String, dynamic>?;

    DateTime now = DateTime.now();
    DateTime limitDate;
    String limitText;
    if (userRole == 'boss') {
      limitDate = now.subtract(const Duration(days: 365));
      limitText = '';
    } else if (userRole == 'premium') {
      limitDate = now.subtract(const Duration(hours: 1));
      limitText =
          "Vous pouvez partager cet événement dans ce city chat une fois par heure.";
    } else {
      limitDate = DateTime(now.year, now.month, now.day);
      limitText =
          "Vous pouvez partager cet événement dans ce city chat une fois par jour.";
    }

    final existingShare = await FirebaseFirestore.instance
        .collection('event_shares')
        .where('eventId', isEqualTo: event.id)
        .where('userId', isEqualTo: user.uid)
        .where('city', isEqualTo: city.toLowerCase())
        .where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(limitDate))
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (existingShare.docs.isNotEmpty && userRole != 'boss') {
      final lastShare = existingShare.docs.first['timestamp'] as Timestamp;
      final nextAllowed = userRole == 'premium'
          ? lastShare.toDate().add(const Duration(hours: 1))
          : DateTime(lastShare.toDate().year, lastShare.toDate().month,
              lastShare.toDate().day + 1);
      final diff = nextAllowed.difference(now);
      String waitMsg = '';
      if (diff.inSeconds > 0) {
        if (userRole == 'premium') {
          waitMsg = "Vous pourrez repartager dans ${diff.inMinutes} min.";
        } else {
          waitMsg = "Vous pourrez repartager demain.";
        }
      }
      if (!mounted) return;
      _showStyledDialog(
        "Limite atteinte",
        "$limitText\n$waitMsg",
        error: true,
        appleStyle: true,
      );
      return;
    }

    await FirebaseFirestore.instance.collection('event_shares').add({
      'eventId': event.id,
      'userId': user.uid,
      'city': city.toLowerCase(),
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('city_chats')
        .doc(city.toLowerCase())
        .collection('messages')
        .add({
      'text': 'Événement partagé',
      'event': {
        ...(event is DocumentSnapshot
            ? event.data() as Map<String, dynamic>
            : event),
        'id': event.id,
      },
      'sharedEventId': event.id,
      'authorId': user.uid,
      'authorPseudo': userData?['pseudo'] ?? 'Utilisateur',
      'authorRole': userData?['role'] ?? 'user',
      'authorCertif': userData?['role'] == 'boss' ||
              (userData?['role'] == 'premium' &&
                  userData?['subscriptionStatus'] == 'active')
          ? true
          : false,
      'timestamp': FieldValue.serverTimestamp(),
      'likes': <String>[],
    });

    if (!mounted) return;
    _showStyledDialog(
      "Partage réussi",
      "Événement partagé dans le city chat de $city ",
      appleStyle: true,
    );
  }

  int safeGet(dynamic doc, String key) {
    return doc.data().containsKey(key) ? (doc[key] ?? 0) : 0;
  }

  Future<void> _deleteEvent(String eventId) async {
    await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
    if (!mounted) return;
    setState(() {}); // refresh
  }

  Future<void> _reportEvent(BuildContext context, String eventId) async {
    final motifs = [
      "Contenu inapproprié",
      "Spam ou publicité",
      "Fausse information",
      "Autre"
    ];
    String motif = motifs[0];
    final motifController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            titlePadding:
                const EdgeInsets.only(top: 18, left: 18, right: 18, bottom: 0),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            actionsPadding: const EdgeInsets.only(bottom: 10, right: 10),
            title: Text("Signaler l'événement",
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...motifs.map((m) => RadioListTile<String>(
                      title: Text(m, style: TextStyle(fontSize: 14)),
                      value: m,
                      groupValue: motif,
                      onChanged: (val) {
                        setState(() {
                          motif = val!;
                          motifController.clear();
                        });
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    )),
                if (motif == "Autre")
                  TextField(
                    controller: motifController,
                    decoration: InputDecoration(
                      labelText: "Précisez le motif",
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                child: Text("Annuler", style: TextStyle(fontSize: 14)),
                onPressed: () => Navigator.pop(context),
              ),
              ElevatedButton(
                child: Text("Envoyer", style: TextStyle(fontSize: 14)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  final user = FirebaseAuth.instance.currentUser;
                  String motifToSend =
                      motif == "Autre" ? motifController.text.trim() : motif;
                  if (motifToSend.isEmpty) return;
                  if (user == null) {
                    _showLoginPrompt();
                    return;
                  }
                  await FirebaseFirestore.instance
                      .collection('event_reports')
                      .add({
                    'eventId': eventId,
                    'userId': user.uid,
                    'motif': motifToSend,
                    'timestamp': FieldValue.serverTimestamp(),
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Signalement envoyé, merci ")),
                  );
                },
              ),
            ],
            backgroundColor: Theme.of(context).dialogBackgroundColor,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    final user = FirebaseAuth.instance.currentUser;
    final primaryColor =
        isDarkMode ? Color(0xFF34AADC) : const Color(0xFF1976D2);
    final backgroundColor =
        isDarkMode ? Color(0xFF1A252F) : const Color(0xFFF5F6FA);
    final accentColor =
        isDarkMode ? Color(0xFF00C73C) : const Color(0xFFF44336);
    final errorColor = isDarkMode ? Color(0xFFFF3B30) : const Color(0xFFF44336);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive paddings
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.048;
    final double chipFontSize = screenWidth * 0.027;
    final double dialogMaxWidth = screenWidth < 400 ? screenWidth * 0.97 : 400;
    final double buttonFontSize = screenWidth * 0.042;
    final double buttonPadding = screenHeight * 0.009;

    return Scaffold(
      body: Container(
        color: backgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              // HEADER
              Container(
                margin: EdgeInsets.all(cardPadding),
                height: screenHeight * 0.065,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode
                        ? [Color(0xFF0F1419), Color(0xFF1A2F2F)]
                        : [primaryColor, primaryColor.withOpacity(0.7)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: isDarkMode
                          ? Colors.black26
                          : primaryColor.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: cardPadding),
                        child: Text(
                          "Recherche",
                          style: TextStyle(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFamily: 'Roboto',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isBoss)
                          IconButton(
                            icon: Icon(Icons.admin_panel_settings,
                                color: isDarkMode ? Colors.amber : accentColor,
                                size: iconSize * 1.5),
                            tooltip: "Admin demandes organisateur",
                            onPressed: _goToAdminPage,
                          ),
                        if (user != null)
                          IconButton(
                            icon: Icon(Icons.favorite,
                                color: isDarkMode
                                    ? Color(0xFFFF3B30)
                                    : accentColor,
                                size: iconSize * 1.5),
                            tooltip: "Mes favoris",
                            onPressed: () {
                              Navigator.pushNamed(
                                context,
                                '/favorites',
                                arguments: {
                                  'city': _city,
                                  'isOrganizer': _isOrganizer,
                                },
                              );
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // BARRE DE RECHERCHE
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: cardPadding, vertical: cardPadding * 0.5),
                child: Row(
                  children: [
                    Expanded(
                      flex: 7,
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Rechercher...",
                          hintStyle: TextStyle(
                              color: isDarkMode
                                  ? Colors.grey[400]
                                  : Colors.black54,
                              fontSize: cardFontSize),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(cardRadius * 0.8),
                          ),
                          prefixIcon: Icon(Icons.search,
                              color: isDarkMode ? primaryColor : primaryColor,
                              size: iconSize * 0.8),
                          filled: true,
                          fillColor:
                              isDarkMode ? Colors.grey[850] : Colors.white,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: cardPadding * 0.7,
                            horizontal: cardPadding,
                          ),
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                          fontSize: cardFontSize,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // FILTRES VILLE + CATÉGORIE côte à côte, largeur réduite et identique
              Padding(
                padding: EdgeInsets.only(
                    left: cardPadding,
                    right: cardPadding,
                    bottom: cardPadding * 0.5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 110, minWidth: 90),
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          canvasColor:
                              isDarkMode ? Color(0xFF23272F) : Colors.white,
                        ),
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _searchScope,
                          dropdownColor:
                              isDarkMode ? Color(0xFF23272F) : Colors.white,
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: chipFontSize * 0.95,
                          ),
                          icon: Icon(Icons.location_on,
                              color: primaryColor, size: iconSize * 0.8),
                          underline: Container(height: 2, color: primaryColor),
                          items: const [
                            DropdownMenuItem(
                                value: 'ville',
                                child: Text("Ville",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600))),
                            DropdownMenuItem(
                                value: 'partout',
                                child: Text("Partout",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600))),
                          ],
                          onChanged: (val) =>
                              setState(() => _searchScope = val!),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 110, minWidth: 90),
                      child: StreamBuilder<QuerySnapshot>(
                        stream: _searchScope == 'ville'
                            ? FirebaseFirestore.instance
                                .collection('events')
                                .where('city', isEqualTo: _city)
                                .where('status', isEqualTo: 'approved')
                                .snapshots()
                            : FirebaseFirestore.instance
                                .collection('events')
                                .where('status', isEqualTo: 'approved')
                                .snapshots(),
                        builder: (context, snapshot) {
                          List<String> categories = ['tous'];
                          if (snapshot.hasData) {
                            final docs = snapshot.data!.docs;
                            final cats = docs
                                .map((doc) => (doc['category'] ?? '')
                                    .toString()
                                    .toLowerCase())
                                .where((cat) => cat.isNotEmpty)
                                .toSet()
                                .toList();
                            cats.sort();
                            categories.addAll(cats);
                          }
                          categories = categories.toSet().toList();
                          if (!categories.contains(_selectedCategory)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              setState(() {
                                _selectedCategory = 'tous';
                              });
                            });
                          }
                          return Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor:
                                  isDarkMode ? Color(0xFF23272F) : Colors.white,
                            ),
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _selectedCategory,
                              dropdownColor:
                                  isDarkMode ? Color(0xFF23272F) : Colors.white,
                              style: TextStyle(
                                color: isDarkMode ? Colors.white : primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: chipFontSize * 0.95,
                              ),
                              underline:
                                  Container(height: 2, color: primaryColor),
                              icon: Icon(Icons.filter_list,
                                  color: primaryColor, size: iconSize * 0.8),
                              items: categories.map((value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(
                                    value[0].toUpperCase() + value.substring(1),
                                    style: TextStyle(
                                      color: isDarkMode
                                          ? Colors.white
                                          : primaryColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: chipFontSize * 0.95,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: (String? newValue) {
                                if (newValue != null)
                                  setState(() => _selectedCategory = newValue);
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              // SEGMENTED BUTTON (Mois/Semaine/Jour)
              Container(
                width: screenWidth * 0.97,
                margin: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                child: SegmentedButton<DisplayMode>(
                  segments: [
                    ButtonSegment<DisplayMode>(
                      value: DisplayMode.month,
                      label: Text("Mois",
                          style: TextStyle(fontSize: chipFontSize)),
                    ),
                    ButtonSegment<DisplayMode>(
                      value: DisplayMode.week,
                      label: Text("Semaine",
                          style: TextStyle(fontSize: chipFontSize)),
                    ),
                    ButtonSegment<DisplayMode>(
                      value: DisplayMode.day,
                      label: Text("Jour",
                          style: TextStyle(fontSize: chipFontSize)),
                    ),
                  ],
                  selected: {_displayMode},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _displayMode = newSelection.first;
                    });
                  },
                  style: SegmentedButton.styleFrom(
                    backgroundColor:
                        isDarkMode ? Colors.grey[800] : backgroundColor,
                    foregroundColor:
                        isDarkMode ? Color(0xFF34AADC) : primaryColor,
                    selectedForegroundColor: Colors.white,
                    selectedBackgroundColor:
                        isDarkMode ? Color(0xFF34AADC) : primaryColor,
                    side: BorderSide(
                        color: isDarkMode ? Color(0xFF34AADC) : primaryColor,
                        width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(cardRadius * 0.8)),
                    textStyle: TextStyle(
                      fontSize: chipFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // LISTE DES EVENTS
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _searchScope == 'ville'
                      ? FirebaseFirestore.instance
                          .collection('events')
                          .where('city', isEqualTo: _city)
                          .where('status', isEqualTo: 'approved')
                          .snapshots()
                      : FirebaseFirestore.instance
                          .collection('events')
                          .where('status', isEqualTo: 'approved')
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    _events = snapshot.data!.docs;
                    List<dynamic> filteredEvents = _filterEvents(_events);

                    filteredEvents.sort((a, b) {
                      String aTitle =
                          (a['title'] ?? '').toString().toLowerCase();
                      String bTitle =
                          (b['title'] ?? '').toString().toLowerCase();
                      int cmp = aTitle.compareTo(bTitle);
                      if (cmp != 0) return cmp;

                      String? aRole = a.data().containsKey('creatorRole')
                          ? a['creatorRole']
                          : (a.data().containsKey('role') ? a['role'] : null);
                      String? bRole = b.data().containsKey('creatorRole')
                          ? b['creatorRole']
                          : (b.data().containsKey('role') ? b['role'] : null);

                      int rolePriority(String? role) {
                        if (role == 'boss') return 3;
                        if (role == 'premium') return 2;
                        if (role == 'organizer') return 1;
                        return 0;
                      }

                      int aP = rolePriority(aRole);
                      int bP = rolePriority(bRole);
                      if (aP != bP) return bP.compareTo(aP);

                      int aStats = safeGet(a, 'participantsCount') +
                          safeGet(a, 'likesCount') +
                          safeGet(a, 'viewsCount');
                      int bStats = safeGet(b, 'participantsCount') +
                          safeGet(b, 'likesCount') +
                          safeGet(b, 'viewsCount');
                      return bStats.compareTo(aStats);
                    });

                    if (filteredEvents.isEmpty) {
                      return Center(
                          child: Text("Aucun événement pour cette période",
                              style: TextStyle(
                                  color:
                                      isDarkMode ? Colors.white70 : Colors.grey,
                                  fontSize: cardFontSize)));
                    }

                    return ListView.builder(
                      padding: EdgeInsets.only(bottom: screenHeight * 0.08),
                      itemCount: filteredEvents.length,
                      itemBuilder: (context, index) {
                        final event = filteredEvents[index];
                        final eventId = event.id;
                        final isFavorite = _favoriteEvents.contains(eventId);

                        return GestureDetector(
                          onTap: () async {
                            final user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              final viewsRef = FirebaseFirestore.instance
                                  .collection('event_views');
                              final existing = await viewsRef
                                  .where('eventId', isEqualTo: event.id)
                                  .where('userId', isEqualTo: user.uid)
                                  .limit(1)
                                  .get();
                              if (existing.docs.isEmpty) {
                                await viewsRef.add({
                                  'eventId': event.id,
                                  'userId': user.uid,
                                  'timestamp': FieldValue.serverTimestamp(),
                                });
                              }
                            }

                            final userDoc = user != null
                                ? await FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(user.uid)
                                    .get()
                                : null;
                            final userRole = userDoc != null
                                ? (userDoc['role'] ?? 'user')
                                : 'user';

                            final isParticipating = user != null
                                ? await isUserParticipating(event)
                                : false;

                            if (!mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: true,
                              builder: (context) {
                                return Dialog(
                                  shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(cardRadius * 1.2),
                                  ),
                                  backgroundColor: isDarkMode
                                      ? Colors.grey[900]
                                      : Color(0xFFEAF4FF),
                                  child: Container(
                                    width: dialogMaxWidth,
                                    padding: EdgeInsets.all(cardPadding),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Flexible(
                                                      child: Text(
                                                        event['title'] ??
                                                            'Sans titre',
                                                        maxLines: 2,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize:
                                                              titleFontSize,
                                                          color: isDarkMode
                                                              ? Color(
                                                                  0xFF34AADC)
                                                              : primaryColor,
                                                        ),
                                                      ),
                                                    ),
                                                    if ((event['creatorRole'] ??
                                                            event['role']) !=
                                                        null)
                                                      _buildCertificationBadge(
                                                          event['creatorRole'] ??
                                                              event['role']),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.close,
                                                    color: isDarkMode
                                                        ? Colors.white54
                                                        : Colors.grey[700],
                                                    size: iconSize * 1.2),
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                tooltip: "Fermer",
                                              ),
                                            ],
                                          ),
                                          if (event['city'] != null &&
                                              event['city']
                                                  .toString()
                                                  .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 2.0),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.location_on,
                                                      size: iconSize * 0.7,
                                                      color: Colors.blue),
                                                  Text(
                                                    event['city'],
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize:
                                                          cardFontSize * 0.9,
                                                      color: isDarkMode
                                                          ? Colors.blue[100]
                                                          : Colors.blue[900],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          SizedBox(
                                              height: screenHeight * 0.012),
                                          if (event['images'] != null &&
                                              event['images'] is List &&
                                              (event['images'] as List)
                                                  .isNotEmpty)
                                            _EventImageCarousel(
                                              images: List<String>.from(
                                                  event['images']),
                                            ),
                                          SizedBox(
                                              height: screenHeight * 0.012),
                                          _infoRow(
                                            icon: Icons.calendar_today,
                                            label: "Date :",
                                            value: _formatDateFr(
                                                (event['date'] as Timestamp)
                                                    .toDate()),
                                            iconSize: iconSize * 0.8,
                                            fontSize: cardFontSize * 1.18,
                                            color: primaryColor,
                                            isDarkMode: isDarkMode,
                                          ),
                                          _infoRow(
                                            icon: Icons.place,
                                            label: "Lieu :",
                                            value: event['location'] ??
                                                'Non spécifié',
                                            iconSize: iconSize * 0.8,
                                            fontSize: cardFontSize * 1.18,
                                            color: primaryColor,
                                            isDarkMode: isDarkMode,
                                          ),
                                          _infoRow(
                                            icon: Icons.category,
                                            label: "Catégorie :",
                                            value: event['category'] ??
                                                'Non spécifiée',
                                            iconSize: iconSize * 0.8,
                                            fontSize: cardFontSize * 1.18,
                                            color: primaryColor,
                                            isDarkMode: isDarkMode,
                                          ),
                                          SizedBox(
                                              height: screenHeight * 0.012),
                                          Text(
                                            "Description :",
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: cardFontSize,
                                              color: isDarkMode
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          SizedBox(
                                              height: screenHeight * 0.003),
                                          Text(
                                            event['description'] ??
                                                'Aucune description',
                                            style: TextStyle(
                                              fontSize: cardFontSize,
                                              color: isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                            softWrap: true,
                                          ),
                                          SizedBox(
                                              height: screenHeight * 0.018),
                                          // Boutons popup petits et harmonieux
                                          Center(
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                double btnWidth =
                                                    (constraints.maxWidth < 400)
                                                        ? (constraints
                                                                .maxWidth -
                                                            32)
                                                        : 240;
                                                btnWidth = btnWidth < 110
                                                    ? 110
                                                    : btnWidth;
                                                double btnHeight = 34;
                                                double btnFont =
                                                    buttonFontSize * 0.8;
                                                return Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: btnWidth,
                                                      height: btnHeight,
                                                      child:
                                                          ElevatedButton.icon(
                                                        icon: Icon(
                                                            isParticipating
                                                                ? Icons.cancel
                                                                : Icons
                                                                    .event_available,
                                                            size: iconSize *
                                                                0.55),
                                                        label: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            isParticipating
                                                                ? "Se désinscrire"
                                                                : "Participer",
                                                            style: TextStyle(
                                                              fontSize: btnFont,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              isDarkMode
                                                                  ? Color(
                                                                      0xFF34AADC)
                                                                  : primaryColor,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      cardRadius *
                                                                          0.7)),
                                                          minimumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                          maximumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                        ),
                                                        onPressed: () async {
                                                          await participateToEvent(
                                                              event);
                                                          Navigator.pop(
                                                              context);
                                                        },
                                                      ),
                                                    ),
                                                    SizedBox(height: 6),
                                                    SizedBox(
                                                      width: btnWidth,
                                                      height: btnHeight,
                                                      child:
                                                          ElevatedButton.icon(
                                                        icon: Icon(Icons.share,
                                                            size: iconSize *
                                                                0.55),
                                                        label: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            "Partager",
                                                            style: TextStyle(
                                                              fontSize: btnFont,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              isDarkMode
                                                                  ? Colors
                                                                      .blueGrey
                                                                  : Colors.blue[
                                                                      800],
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      cardRadius *
                                                                          0.7)),
                                                          minimumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                          maximumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                        ),
                                                        onPressed: () async {
                                                          final user =
                                                              FirebaseAuth
                                                                  .instance
                                                                  .currentUser;
                                                          if (user == null) {
                                                            _showLoginPrompt();
                                                            return;
                                                          }
                                                          String cityToShare =
                                                              event['city'];
                                                          await shareEventToCityChat(
                                                              event,
                                                              cityToShare,
                                                              userRole);
                                                          Navigator.pop(
                                                              context);
                                                        },
                                                      ),
                                                    ),
                                                    SizedBox(height: 6),
                                                    SizedBox(
                                                      width: btnWidth,
                                                      height: btnHeight,
                                                      child:
                                                          ElevatedButton.icon(
                                                        icon: Icon(Icons.report,
                                                            color: Colors.white,
                                                            size: iconSize *
                                                                0.55),
                                                        label: FittedBox(
                                                          fit: BoxFit.scaleDown,
                                                          child: Text(
                                                            "Signaler",
                                                            style: TextStyle(
                                                              fontSize: btnFont,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                        style: ElevatedButton
                                                            .styleFrom(
                                                          backgroundColor:
                                                              Colors.redAccent,
                                                          foregroundColor:
                                                              Colors.white,
                                                          padding: EdgeInsets
                                                              .symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2),
                                                          shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                      cardRadius *
                                                                          0.7)),
                                                          minimumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                          maximumSize: Size(
                                                              btnWidth,
                                                              btnHeight),
                                                        ),
                                                        onPressed: () async {
                                                          await _reportEvent(
                                                              context,
                                                              event.id);
                                                        },
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          child: Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: cardPadding,
                                vertical: cardPadding / 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(cardRadius),
                            ),
                            elevation: 6,
                            color: isDarkMode ? Colors.grey[850] : Colors.white,
                            shadowColor: isDarkMode
                                ? Colors.black54
                                : Colors.blue.withOpacity(0.08),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                  cardPadding,
                                  cardPadding * 0.9,
                                  cardPadding,
                                  cardPadding * 0.9),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    event['title'] ??
                                                        'Sans titre',
                                                    style: TextStyle(
                                                      color: isDarkMode
                                                          ? Color(0xFF34AADC)
                                                          : primaryColor,
                                                      fontSize: titleFontSize,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontFamily: 'Roboto',
                                                      letterSpacing: 0.2,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    maxLines: 1,
                                                  ),
                                                ),
                                                if ((event['creatorRole'] ??
                                                        event['role']) !=
                                                    null)
                                                  _buildCertificationBadge(
                                                      event['creatorRole'] ??
                                                          event['role']),
                                              ],
                                            ),
                                            if (event['city'] != null &&
                                                event['city']
                                                    .toString()
                                                    .isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2.0),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.location_on,
                                                        color: isDarkMode
                                                            ? Colors.blue[200]
                                                            : Colors.blue,
                                                        size: iconSize * 0.5),
                                                    SizedBox(width: 3),
                                                    Text(
                                                      event['city'],
                                                      style: TextStyle(
                                                        color: isDarkMode
                                                            ? Colors.blue[100]
                                                            : Colors.blue[900],
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize:
                                                            cardFontSize * 0.8,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          isFavorite
                                              ? Icons.favorite
                                              : Icons.favorite_border,
                                          color: isFavorite
                                              ? (isDarkMode
                                                  ? Color(0xFFFF3B30)
                                                  : accentColor)
                                              : (isDarkMode
                                                  ? Colors.grey
                                                  : Colors.grey),
                                          size: iconSize * 1.3,
                                        ),
                                        onPressed: () =>
                                            _toggleFavorite(eventId),
                                      ),
                                      if (user != null &&
                                          (event['creatorId'] == user.uid ||
                                              _isBoss))
                                        IconButton(
                                          icon: Icon(Icons.delete,
                                              color: Colors.red,
                                              size: iconSize * 0.9),
                                          tooltip: "Supprimer l'événement",
                                          onPressed: () async {
                                            bool? confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: Text(
                                                    "Supprimer l'événement"),
                                                content: Text(
                                                    "Voulez-vous vraiment supprimer cet événement ?"),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: Text("Annuler"),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: Text("Supprimer"),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.red,
                                                      foregroundColor:
                                                          Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _deleteEvent(eventId);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: screenHeight * 0.012),
                                  if (event['images'] != null &&
                                      event['images'] is List &&
                                      (event['images'] as List).isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.photo_library,
                                            color: primaryColor,
                                            size: iconSize * 0.7),
                                        SizedBox(width: 4),
                                        Text(
                                          "${(event['images'] as List).length} image${(event['images'] as List).length > 1 ? 's' : ''} disponible${(event['images'] as List).length > 1 ? 's' : ''}",
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.white70
                                                : Color(0xFF333333),
                                            fontSize: cardFontSize * 0.95,
                                            fontFamily: 'Roboto',
                                          ),
                                        ),
                                      ],
                                    ),
                                  _infoRow(
                                    icon: Icons.calendar_today,
                                    label: "",
                                    value: _formatDateFr(
                                        (event['date'] as Timestamp).toDate()),
                                    iconSize: iconSize,
                                    fontSize: cardFontSize,
                                    color: primaryColor,
                                    isDarkMode: isDarkMode,
                                  ),
                                  _infoRow(
                                    icon: Icons.place,
                                    label: "",
                                    value: event['location'] ?? 'Non spécifié',
                                    iconSize: iconSize,
                                    fontSize: cardFontSize,
                                    color: primaryColor,
                                    isDarkMode: isDarkMode,
                                  ),
                                  _infoRow(
                                    icon: Icons.category,
                                    label: "",
                                    value: event['category'] ?? 'Non spécifiée',
                                    iconSize: iconSize,
                                    fontSize: cardFontSize,
                                    color: primaryColor,
                                    isDarkMode: isDarkMode,
                                  ),
                                  SizedBox(height: screenHeight * 0.005),
                                  Text(
                                    "Description : ${event['description'] ?? 'Aucune description'}",
                                    style: TextStyle(
                                      color: isDarkMode
                                          ? Colors.white70
                                          : Color(0xFF333333),
                                      fontSize: cardFontSize,
                                      fontFamily: 'Roboto',
                                    ),
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: isDarkMode ? Color(0xFF1A252F) : backgroundColor,
        elevation: 4,
        currentIndex: 1,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          const BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          const BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today), label: ''),
          const BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble), label: ''),
          const BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
        ],
        selectedItemColor: isDarkMode ? Color(0xFF34AADC) : primaryColor,
        unselectedItemColor: isDarkMode ? Colors.grey : Colors.grey[500],
        selectedIconTheme: IconThemeData(
            size: 28, color: isDarkMode ? Color(0xFF34AADC) : primaryColor),
        unselectedIconTheme: IconThemeData(
            size: 28, color: isDarkMode ? Colors.grey : Colors.grey[500]),
        onTap: (index) async {
          final user = FirebaseAuth.instance.currentUser;
          if (index == 0) {
            bool? confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text("Retour à l'accueil",
                    style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87)),
                content: Text(
                    "Êtes-vous sûr de vouloir retourner à la page d'accueil ?",
                    style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Colors.black54)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text("Annuler",
                        style: TextStyle(
                            color: isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2))),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text("Oui, retourner",
                        style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isDarkMode ? Color(0xFFFF3B30) : errorColor,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
                backgroundColor: isDarkMode ? Color(0xFF2A2F32) : Colors.white,
              ),
            );
            if (confirm == true) {
              Navigator.pushReplacementNamed(context, '/home', arguments: {
                'city': _city,
                'isOrganizer': _isOrganizer,
              });
            }
          } else if (index == 1) {
            // Rester sur EventsListPage
          } else if (index == 2) {
            Navigator.pushReplacementNamed(
              context,
              '/events',
              arguments: {
                'city': _city,
                'isOrganizer': _isOrganizer,
              },
            );
          } else if (index == 3) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CityChatPage(city: _city),
              ),
            );
          } else if (index == 4) {
            if (user != null) {
              Navigator.pushReplacementNamed(
                context,
                '/profile',
                arguments: {
                  'city': _city,
                  'isOrganizer': _isOrganizer,
                },
              );
            } else {
              _showStyledDialog("Connexion requise",
                  "Connectez-vous pour accéder à votre profil.",
                  error: true);
            }
          }
        },
      ),
    );
  }

  // Widget utilitaire pour infos event (évite overflow)
  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required double iconSize,
    required double fontSize,
    required Color color,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconSize, color: color),
          SizedBox(width: 6),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  if (label.isNotEmpty)
                    TextSpan(
                      text: label + " ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  TextSpan(text: value),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

// Carousel avec petits points pour le dialog
class _EventImageCarousel extends StatefulWidget {
  final List<String> images;
  const _EventImageCarousel({required this.images});

  @override
  State<_EventImageCarousel> createState() => _EventImageCarouselState();
}

class _EventImageCarouselState extends State<_EventImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double carouselHeight = screenWidth * 0.45;
    return Column(
      children: [
        SizedBox(
          height: carouselHeight,
          child: PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, i) {
              final url = widget.images[i];
              return GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      child: InteractiveViewer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            url,
                            fit: BoxFit.contain,
                            errorBuilder: (c, e, s) => Container(
                              color: Colors.grey[300],
                              width: 300,
                              height: 300,
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey, size: 60),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    url,
                    width: double.infinity,
                    height: carouselHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: double.infinity,
                      height: carouselHeight,
                      color: Colors.grey[300],
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.images.length,
            (index) => Container(
              margin: EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index ? Colors.blue : Colors.grey[400],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
