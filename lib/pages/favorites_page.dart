import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class FavoritesPage extends StatefulWidget {
  final String city;
  const FavoritesPage({required this.city, Key? key}) : super(key: key);

  @override
  _FavoritesPageState createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  late List<dynamic> _favoriteEvents = [];
  List<String> _favoriteEventIds = [];
  bool _isOrganizer = false;
  Map<String, int> _eventRatings = {}; // eventId -> rating

  @override
  void initState() {
    super.initState();
    _loadFavoriteEvents();
    _checkOrganizerStatus();
    _loadRatings();
  }

  Future<void> _checkOrganizerStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
      if (userData != null && mounted) {
        setState(() {
          _isOrganizer = userData['isOrganizer'] ?? false;
        });
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
        final favoriteEventsRaw = List<String>.from(userData['favoriteEvents']);
        _favoriteEventIds = favoriteEventsRaw;
        List<QueryDocumentSnapshot> publicEvents = [];
        List<DocumentSnapshot> privateEvents = [];

        // Sépare les IDs simples (publics) et les chemins complets (privés)
        final publicIds = <String>[];
        final privatePaths = <String>[];
        for (final fav in favoriteEventsRaw) {
          if (fav.contains('/')) {
            privatePaths.add(fav);
          } else {
            publicIds.add(fav);
          }
        }

        // Public events
        if (publicIds.isNotEmpty) {
          final eventDocs = await FirebaseFirestore.instance
              .collection('events')
              .where(FieldPath.documentId, whereIn: publicIds)
              .where('status', isEqualTo: 'approved')
              .get();
          publicEvents = eventDocs.docs;
        }

        // Private events
        for (final path in privatePaths) {
          try {
            final doc = await FirebaseFirestore.instance.doc(path).get();
            if (doc.exists) privateEvents.add(doc);
          } catch (_) {}
        }

        // Nettoyage des events trop anciens
        DateTime now = DateTime.now();
        List<String> toRemove = [];
        List<dynamic> validEvents = [];
        for (var doc in [...publicEvents, ...privateEvents]) {
          DateTime eventDate = (doc['date'] as Timestamp).toDate();
          if (eventDate.isBefore(now.subtract(const Duration(days: 2)))) {
            // On retire l'ID ou le chemin complet
            if (doc.reference.path.startsWith('events/')) {
              toRemove.add(doc.id);
            } else {
              toRemove.add(doc.reference.path);
            }
          } else {
            validEvents.add(doc);
          }
        }
        if (toRemove.isNotEmpty) {
          _favoriteEventIds.removeWhere((id) => toRemove.contains(id));
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({'favoriteEvents': _favoriteEventIds});
        }
        if (!mounted) return;
        setState(() {
          _favoriteEvents = validEvents;
        });
      } else {
        if (!mounted) return;
        setState(() => _favoriteEvents = []);
      }
    } else {
      if (!mounted) return;
      setState(() => _favoriteEvents = []);
      _showLoginPrompt();
    }
  }

  Future<void> _toggleFavorite(dynamic event) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String favId;
      // Si event vient d'une collection privée, on stocke le chemin complet
      if (event.reference.path.startsWith('events/')) {
        favId = event.id;
      } else {
        favId = event.reference.path;
      }
      setState(() {
        if (_favoriteEventIds.contains(favId)) {
          _favoriteEventIds.remove(favId);
        } else {
          _favoriteEventIds.add(favId);
        }
      });
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'favoriteEvents': _favoriteEventIds});
      _loadFavoriteEvents();
    } else {
      _showLoginPrompt();
    }
  }

  Future<void> _toggleParticipation(dynamic event) async {
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
      _showStyledDialog(
        "Désinscription",
        "Vous êtes désinscrit de l'événement.",
        error: false,
      );
    } else {
      await FirebaseFirestore.instance.collection('event_participations').add({
        'eventId': event.id,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _showStyledDialog(
        "Participation",
        "Inscription à l'événement effectuée",
        error: false,
      );
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<bool> _isParticipating(dynamic event) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final participations = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: event.id)
        .where('userId', isEqualTo: user.uid)
        .get();
    return participations.docs.isNotEmpty;
  }

  void _showLoginPrompt() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    final primaryColor = isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isDarkMode ? Color(0xFF23272F) : Colors.white,
        title: Row(
          children: [
            Icon(Icons.lock, color: isDarkMode ? Colors.amber : primaryColor),
            SizedBox(width: 8),
            Text(
              "Connexion requise",
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          "Veuillez vous connecter pour voir vos favoris.",
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black54,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacementNamed(context, '/home');
            },
            child: Text("Annuler",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2))),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              final city = widget.city;
              Navigator.pushReplacementNamed(
                context,
                '/login',
                arguments: {'city': city, 'isOrganizer': false},
              );
            },
            child: Text("Se connecter",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2))),
          ),
        ],
      ),
    );
  }

  void _showStyledDialog(String title, String message, {bool error = false}) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: isDarkMode ? Color(0xFF23272F) : Colors.white,
        title: Row(
          children: [
            Icon(
              error ? Icons.error : Icons.check_circle,
              color: error
                  ? (isDarkMode ? Colors.red[300] : Colors.red)
                  : (isDarkMode ? Colors.green[300] : Colors.green),
            ),
            SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isDarkMode
                    ? (error ? Colors.red[100] : Colors.white)
                    : (error ? Colors.red[800] : Colors.green[800]),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : Colors.black87,
            fontSize: 16,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2))),
          ),
        ],
      ),
    );
  }

  String _formatDateFr(DateTime date) {
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (date.hour != 0 || date.minute != 0) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à $heure:$minute";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Widget _buildCertifBadge(dynamic event) {
    final role = event['creatorRole'] ?? event['role'];
    if (role == 'boss') {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.verified_user, color: Colors.blue, size: 20),
      );
    } else if (role == 'premium') {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Icon(Icons.verified, color: Colors.amber, size: 20),
      );
    }
    return SizedBox.shrink();
  }

  Future<void> _loadRatings() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ratings = await FirebaseFirestore.instance
        .collection('event_ratings')
        .where('userId', isEqualTo: user.uid)
        .get();
    final Map<String, int> map = {};
    for (var doc in ratings.docs) {
      map[doc['eventId']] = doc['rating'];
    }
    if (mounted) {
      setState(() {
        _eventRatings = map;
      });
    }
  }

  Future<void> _rateEvent(String eventId, int rating) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final existing = await FirebaseFirestore.instance
        .collection('event_ratings')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: user.uid)
        .get();
    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update({'rating': rating});
    } else {
      await FirebaseFirestore.instance.collection('event_ratings').add({
        'eventId': eventId,
        'userId': user.uid,
        'rating': rating,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    setState(() {
      _eventRatings[eventId] = rating;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Merci pour votre note"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildRatingStars(String eventId) {
    final int rating = _eventRatings[eventId] ?? 0;
    final bool alreadyRated = rating > 0;
    int hovered = -1;

    return StatefulBuilder(
      builder: (context, setState) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final isActive = i < (hovered >= 0 ? hovered : rating);
            return MouseRegion(
              onEnter: (_) => setState(() => hovered = i + 1),
              onExit: (_) => setState(() => hovered = -1),
              child: GestureDetector(
                onTap: alreadyRated ? null : () => _rateEvent(eventId, i + 1),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 120),
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.star_rounded,
                    color: isActive ? Colors.amber : Colors.grey[350],
                    size: 28,
                    shadows: isActive
                        ? [
                            Shadow(
                                color: Colors.amber.withOpacity(0.3),
                                blurRadius: 8)
                          ]
                        : [],
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  bool _canLeaveFeedback(Map<String, dynamic> eventData) {
    return (eventData['creatorRole'] == 'premium' ||
        eventData['creatorRole'] == 'boss' ||
        eventData['role'] == 'premium' ||
        eventData['role'] == 'boss');
  }

  bool _canShowRating(Map<String, dynamic> eventData) {
    return (eventData['creatorRole'] == 'premium' ||
        eventData['creatorRole'] == 'boss');
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    final primaryColor = isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2);
    final backgroundColor = isDarkMode ? Color(0xFF1A252F) : Color(0xFFF5F6FA);

    final screenWidth = MediaQuery.of(context).size.width;
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.048;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        elevation: 0,
        title: Text(
          "Mes favoris",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: titleFontSize,
            letterSpacing: 0.5,
          ),
        ),
        centerTitle: true,
        shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(bottom: Radius.circular(cardRadius * 1.2)),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        color: backgroundColor,
        child: _favoriteEvents.isEmpty
            ? Center(
                child: Text(
                  "Aucun événement favori",
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                    fontSize: cardFontSize * 1.2,
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.symmetric(
                    vertical: cardPadding * 2, horizontal: cardPadding),
                itemCount: _favoriteEvents.length,
                itemBuilder: (context, index) {
                  final event = _favoriteEvents[index];
                  final eventData = event.data() as Map<String, dynamic>;
                  // Pour l'icône favori, il faut vérifier si c'est un event public ou privé
                  String favId = event.reference.path.startsWith('events/')
                      ? event.id
                      : event.reference.path;
                  final isFavorite = _favoriteEventIds.contains(favId);
                  final eventDate = (eventData['date'] as Timestamp).toDate();
                  final now = DateTime.now();
                  final difference = eventDate.difference(now);
                  final isPast = now.isAfter(eventDate.add(Duration(hours: 4)));

                  return FutureBuilder<bool>(
                    future: _isParticipating(event),
                    builder: (context, snap) {
                      final isParticipating = snap.data ?? false;
                      return GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            barrierDismissible: true,
                            builder: (context) {
                              return Dialog(
                                insetPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 24),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(cardRadius * 1.2),
                                ),
                                backgroundColor: isDarkMode
                                    ? Colors.grey[900]
                                    : Color(0xFFEAF4FF),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: 400,
                                    minWidth: 0,
                                  ),
                                  child: Padding(
                                    padding: EdgeInsets.all(cardPadding),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              // Titre, badge, ville
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            eventData[
                                                                    'title'] ??
                                                                'Sans titre',
                                                            style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize:
                                                                  titleFontSize,
                                                              color: isDarkMode
                                                                  ? Color(
                                                                      0xFF34AADC)
                                                                  : primaryColor,
                                                            ),
                                                          ),
                                                          _buildCertifBadge(
                                                              eventData),
                                                          if (eventData[
                                                                      'city'] !=
                                                                  null &&
                                                              eventData['city']
                                                                  .toString()
                                                                  .isNotEmpty)
                                                            Row(
                                                              children: [
                                                                SizedBox(
                                                                    width: 8),
                                                                Icon(
                                                                    Icons
                                                                        .location_on,
                                                                    size:
                                                                        iconSize *
                                                                            0.7,
                                                                    color: Colors
                                                                        .blue),
                                                                Text(
                                                                  eventData[
                                                                      'city'],
                                                                  style:
                                                                      TextStyle(
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                    fontSize:
                                                                        cardFontSize *
                                                                            1.1,
                                                                    color: isDarkMode
                                                                        ? Colors.blue[
                                                                            100]
                                                                        : Colors
                                                                            .blue[900],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: Icon(Icons.close,
                                                    color: isDarkMode
                                                        ? Colors.white54
                                                        : Colors.grey[700]),
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                tooltip: "Fermer",
                                                padding: EdgeInsets.zero,
                                                constraints: BoxConstraints(),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: cardPadding * 0.7),
                                          if (eventData['images'] != null &&
                                              (eventData['images'] as List)
                                                  .isNotEmpty)
                                            _EventImageCarousel(
                                                images: List<String>.from(
                                                    eventData['images'])),
                                          SizedBox(height: cardPadding * 0.7),
                                          // Date
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.calendar_today,
                                                  size: iconSize * 0.8,
                                                  color: primaryColor),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    "Date : ${_formatDateFr(eventDate)}",
                                                    style: TextStyle(
                                                        fontSize:
                                                            cardFontSize * 1.1,
                                                        color: isDarkMode
                                                            ? Colors.white70
                                                            : Colors.black87,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          // Lieu
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.place,
                                                  size: iconSize * 0.8,
                                                  color: primaryColor),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    "Lieu : ${eventData['location'] ?? 'Non spécifié'}",
                                                    style: TextStyle(
                                                        fontSize:
                                                            cardFontSize * 1.1,
                                                        color: isDarkMode
                                                            ? Colors.white70
                                                            : Colors.black87,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: 4),
                                          // Catégorie
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.category,
                                                  size: iconSize * 0.8,
                                                  color: primaryColor),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    "Catégorie : ${eventData['category'] ?? 'Non spécifiée'}",
                                                    style: TextStyle(
                                                        fontSize:
                                                            cardFontSize * 1.1,
                                                        color: isDarkMode
                                                            ? Colors.white70
                                                            : Colors.black87,
                                                        fontWeight:
                                                            FontWeight.bold),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          SizedBox(height: cardPadding * 0.7),
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
                                          SizedBox(height: 2),
                                          Text(
                                            eventData['description'] ??
                                                'Aucune description',
                                            style: TextStyle(
                                              fontSize: cardFontSize,
                                              color: isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black87,
                                            ),
                                          ),
                                          SizedBox(height: cardPadding),
                                          if (isPast) ...[
                                            Row(
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red[100],
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                  ),
                                                  child: Text(
                                                    "Événement terminé",
                                                    style: TextStyle(
                                                      color: Colors.red,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize:
                                                          cardFontSize * 0.9,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 4),
                                            if (_canShowRating(eventData)) ...[
                                              Row(
                                                children: [
                                                  _buildRatingStars(event.id),
                                                ],
                                              ),
                                              if (_canLeaveFeedback(eventData))
                                                SizedBox(height: 8),
                                              if (_canLeaveFeedback(eventData))
                                                _FeedbackField(
                                                    eventId: event.id),
                                            ],
                                          ] else ...[
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: difference.inHours < 24
                                                      ? SizedBox.shrink()
                                                      : Text(
                                                          "Les organisateurs ont hâte de vous accueillir",
                                                          style: TextStyle(
                                                            color: Colors
                                                                .blue[800],
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize:
                                                                cardFontSize *
                                                                    0.9,
                                                          ),
                                                        ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          SizedBox(height: cardPadding),
                                          if (!isPast)
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: ElevatedButton.icon(
                                                icon: Icon(
                                                  isParticipating
                                                      ? Icons.cancel
                                                      : Icons.event_available,
                                                  size: iconSize * 0.9,
                                                ),
                                                label: Text(isParticipating
                                                    ? "Se désinscrire"
                                                    : "Participer"),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: primaryColor,
                                                  foregroundColor: Colors.white,
                                                  padding: EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                      vertical: 12),
                                                  textStyle: TextStyle(
                                                      fontSize:
                                                          cardFontSize * 1.1,
                                                      fontWeight:
                                                          FontWeight.w600),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            cardRadius * 0.8),
                                                  ),
                                                ),
                                                onPressed: () async {
                                                  await _toggleParticipation(
                                                      event);
                                                  Navigator.pop(context);
                                                },
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
                        child: Card(
                          margin: EdgeInsets.symmetric(
                              horizontal: cardPadding * 0.5,
                              vertical: cardPadding * 0.7),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(cardRadius * 1.1)),
                          elevation: 6,
                          color: isDarkMode ? Colors.grey[850] : Colors.white,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(cardPadding * 1.2,
                                cardPadding, cardPadding * 1.2, cardPadding),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            eventData['title'] ?? 'Sans titre',
                                            style: TextStyle(
                                              color: isDarkMode
                                                  ? Color(0xFF34AADC)
                                                  : primaryColor,
                                              fontSize: titleFontSize,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'Roboto',
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          _buildCertifBadge(eventData),
                                          if (eventData['city'] != null &&
                                              eventData['city']
                                                  .toString()
                                                  .isNotEmpty)
                                            Container(
                                              margin: EdgeInsets.only(left: 10),
                                              padding: EdgeInsets.symmetric(
                                                  horizontal: 10, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isDarkMode
                                                    ? Colors.blueGrey[900]
                                                    : Colors.blue[50],
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: isDarkMode
                                                      ? Colors.blue[200]!
                                                      : Colors.blue,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.location_on,
                                                      color: isDarkMode
                                                          ? Colors.blue[200]
                                                          : Colors.blue,
                                                      size: iconSize * 0.7),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    eventData['city'],
                                                    style: TextStyle(
                                                      color: isDarkMode
                                                          ? Colors.blue[100]
                                                          : Colors.blue[900],
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize:
                                                          cardFontSize * 0.95,
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
                                                : Colors.red)
                                            : (isDarkMode
                                                ? Colors.grey
                                                : Colors.grey),
                                        size: iconSize * 1.2,
                                      ),
                                      onPressed: () => _toggleFavorite(event),
                                    ),
                                  ],
                                ),
                                SizedBox(height: cardPadding * 0.7),
                                if (eventData['images'] != null &&
                                    (eventData['images'] as List).isNotEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.photo_library,
                                          color: primaryColor,
                                          size: iconSize * 0.8),
                                      SizedBox(width: 4),
                                      Text(
                                        "${(eventData['images'] as List).length} image${(eventData['images'] as List).length > 1 ? 's' : ''} disponible${(eventData['images'] as List).length > 1 ? 's' : ''}",
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
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: iconSize * 0.7,
                                        color: primaryColor),
                                    SizedBox(width: 4),
                                    Text(
                                      _formatDateFr(eventDate),
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white70
                                            : Color(0xFF333333),
                                        fontSize: cardFontSize,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.place,
                                        size: iconSize * 0.7,
                                        color: primaryColor),
                                    SizedBox(width: 4),
                                    Text(
                                      eventData['location'] ?? 'Non spécifié',
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white70
                                            : Color(0xFF333333),
                                        fontSize: cardFontSize,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.category,
                                        size: iconSize * 0.7,
                                        color: primaryColor),
                                    SizedBox(width: 4),
                                    Text(
                                      eventData['category'] ?? 'Non spécifiée',
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white70
                                            : Color(0xFF333333),
                                        fontSize: cardFontSize,
                                        fontFamily: 'Roboto',
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Description : ${eventData['description'] ?? 'Aucune description'}",
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Color(0xFF333333),
                                    fontSize: cardFontSize,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                SizedBox(height: cardPadding * 0.7),
                                if (isPast) ...[
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          "Événement terminé",
                                          style: TextStyle(
                                            color: Colors.red,
                                            fontWeight: FontWeight.bold,
                                            fontSize: cardFontSize * 0.9,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  if (_canShowRating(eventData)) ...[
                                    Row(
                                      children: [
                                        _buildRatingStars(event.id),
                                      ],
                                    ),
                                    if (_canLeaveFeedback(eventData))
                                      Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          "Vous pouvez laisser un avis à l'organisateur dans le détail",
                                          style: TextStyle(
                                            color: Colors.blue[700],
                                            fontSize: cardFontSize * 0.9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ] else ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: difference.inHours < 24
                                            ? SizedBox.shrink()
                                            : Text(
                                                "Les organisateurs ont hâte de vous accueillir",
                                                style: TextStyle(
                                                  color: Colors.blue[800],
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: cardFontSize * 0.9,
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ],
                                SizedBox(height: cardPadding * 0.7),
                                if (!isPast)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton.icon(
                                      icon: Icon(
                                        isParticipating
                                            ? Icons.cancel
                                            : Icons.event_available,
                                        size: iconSize * 0.8,
                                      ),
                                      label: Text(isParticipating
                                          ? "Se désinscrire"
                                          : "Participer"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryColor,
                                        foregroundColor: Colors.white,
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius)),
                                      ),
                                      onPressed: () =>
                                          _toggleParticipation(event),
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
              ),
      ),
    );
  }
}

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

class _FeedbackField extends StatefulWidget {
  final String eventId;
  const _FeedbackField({required this.eventId});

  @override
  State<_FeedbackField> createState() => _FeedbackFieldState();
}

class _FeedbackFieldState extends State<_FeedbackField> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;
  String? _savedText;

  @override
  void initState() {
    super.initState();
    _loadFeedback();
  }

  Future<void> _loadFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('event_feedbacks')
        .doc('${widget.eventId}_${user.uid}')
        .get();
    if (doc.exists) {
      setState(() {
        _controller.text = doc['feedback'] ?? '';
        _savedText = doc['feedback'] ?? '';
      });
    }
  }

  Future<void> _saveFeedback() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loading = true);
    await FirebaseFirestore.instance
        .collection('event_feedbacks')
        .doc('${widget.eventId}_${user.uid}')
        .set({
      'eventId': widget.eventId,
      'userId': user.uid,
      'feedback': _controller.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    setState(() {
      _loading = false;
      _savedText = _controller.text.trim();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Merci pour votre retour !")),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double cardFontSize = screenWidth * 0.038;
    return Container(
      margin: EdgeInsets.only(top: 10),
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.blueGrey[900] : Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? Colors.blueGrey[700]! : Color(0xFFE0E6F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Votre retour pour l'organisateur",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: cardFontSize,
              color: isDarkMode ? Colors.white : Colors.blue[900],
            ),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  minLines: 1,
                  maxLines: 3,
                  enabled: !_loading,
                  decoration: InputDecoration(
                    hintText: "Laissez un commentaire...",
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: isDarkMode
                            ? Colors.blueGrey[700]!
                            : Colors.blue[100]!,
                      ),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(width: 8),
              _loading
                  ? SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Material(
                      color: Colors.blue,
                      shape: CircleBorder(),
                      child: IconButton(
                        icon: Icon(Icons.send, color: Colors.white),
                        onPressed: _controller.text.trim().isEmpty || _loading
                            ? null
                            : _saveFeedback,
                        tooltip: "Envoyer",
                      ),
                    ),
            ],
          ),
          if (_savedText != null && _savedText!.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text(
                    "Commentaire enregistré",
                    style: TextStyle(
                        color: Colors.green[700],
                        fontSize: cardFontSize * 0.9,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
