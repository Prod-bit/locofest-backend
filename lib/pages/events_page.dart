import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import 'city_chat_page.dart';
import '../widgets/event_card.dart';

class EventsPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const EventsPage({Key? key, this.arguments}) : super(key: key);

  @override
  _EventsPageState createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  late Map<DateTime, List<dynamic>> _events;
  late List<dynamic> _selectedEvents;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _ratingController = TextEditingController();
  final TextEditingController _questionController = TextEditingController();
  final Map<String, TextEditingController> _answerControllers = {};
  final Map<String, TextEditingController> _replyControllers = {};

  bool _isOrganizer = false;
  bool _hasActiveSubscription = false;
  bool _isBoss = false;
  List<String> _favoriteEvents = [];
  String _city = '';
  bool _isAddEventButtonDisabled = false;
  DateTime? _selectedEventDate;
  TimeOfDay? _selectedEventTime;
  final TextEditingController _timeController = TextEditingController();
  bool _isRecurrent = false;
  String _recurrenceType = 'hebdo';
  int _recurrenceWeekday = DateTime.sunday;
  DateTime? _recurrenceEndDate;

  // -------- AJOUTE CES DEUX FONCTIONS ICI --------
  String _monthName(DateTime date) {
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre'
    ];
    return months[date.month - 1];
  }

  Widget _buildFormatButton(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final screenWidth = MediaQuery.of(context).size.width;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          if (_calendarFormat == CalendarFormat.month) {
            _calendarFormat = CalendarFormat.twoWeeks;
          } else if (_calendarFormat == CalendarFormat.twoWeeks) {
            _calendarFormat = CalendarFormat.week;
          } else {
            _calendarFormat = CalendarFormat.month;
          }
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor:
            themeProvider.isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(screenWidth * 0.025),
        ),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        elevation: 0,
      ),
      child: Text(
        _calendarFormat == CalendarFormat.month
            ? "Month"
            : _calendarFormat == CalendarFormat.twoWeeks
                ? "2 weeks"
                : "Week",
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: screenWidth * 0.035,
        ),
      ),
    );
  }
  // -------- FIN AJOUT --------

  @override
  void initState() {
    super.initState();
    _events = {};
    _selectedEvents = [];
    _selectedDay = DateTime(
      _focusedDay.year,
      _focusedDay.month,
      _focusedDay.day,
    );

    final args = widget.arguments;
    if (args != null) {
      _city = args['city'] ?? '';
      _checkOrganizerAndBossStatus();
      _loadFavoriteEvents();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showStyledError(context, "Erreur de navigation : arguments manquants");
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    _categoryController.dispose();
    _commentController.dispose();
    _ratingController.dispose();
    _questionController.dispose();
    _timeController.dispose();
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
    for (final controller in _replyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _checkOrganizerAndBossStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    bool isDeviceOrganizer = false;

    final prefs = await SharedPreferences.getInstance();
    isDeviceOrganizer = prefs.getBool('isOrganizer') ?? false;
    String? deviceUserId = prefs.getString('userId');

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
        bool isOrganizerFromDb = userData['isOrganizer'] ?? false;
        bool hasActiveSubscription = false;

        if (subscriptionStatus == 'active' && subscriptionEndDate != null) {
          DateTime endDate = subscriptionEndDate.toDate();
          if (endDate.isAfter(DateTime.now())) {
            hasActiveSubscription = true;
          }
        }

        bool isBossFromDb = userData['role'] == 'boss';

        if (!mounted) return;
        setState(() {
          _isOrganizer = isOrganizerFromDb;
          _hasActiveSubscription = hasActiveSubscription;
          _isBoss = isBossFromDb;
        });

        await prefs.setBool('isOrganizer', isOrganizerFromDb);
        await prefs.setString('userId', user.uid);
      }
    } else {
      if (deviceUserId != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(deviceUserId)
            .get();
        Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
        if (userData != null) {
          String subscriptionStatus =
              userData['subscriptionStatus'] ?? 'inactive';
          Timestamp? subscriptionEndDate = userData['subscriptionEndDate'];
          bool isOrganizerFromDb = userData['isOrganizer'] ?? false;
          bool hasActiveSubscription = false;

          if (subscriptionStatus == 'active' && subscriptionEndDate != null) {
            DateTime endDate = subscriptionEndDate.toDate();
            if (endDate.isAfter(DateTime.now())) {
              hasActiveSubscription = true;
            }
          }

          bool isBossFromDb = userData['role'] == 'boss';

          if (!mounted) return;
          setState(() {
            _isOrganizer = isDeviceOrganizer && isOrganizerFromDb;
            _hasActiveSubscription = hasActiveSubscription;
            _isBoss = isBossFromDb;
          });
        }
      }
    }

    if (_isBoss) {
      if (!mounted) return;
      setState(() {
        _isOrganizer = true;
        _hasActiveSubscription = true;
      });
    }
  }

  Future<void> _loadFavoriteEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && data['favoriteEvents'] != null) {
        if (!mounted) return;
        setState(() {
          _favoriteEvents = List<String>.from(data['favoriteEvents']);
        });
      }
    }
  }

  Future<void> _toggleFavorite(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showLoginPrompt();
      return;
    }
    final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    if (!mounted) return;
    setState(() {
      if (_favoriteEvents.contains(eventId)) {
        _favoriteEvents.remove(eventId);
      } else {
        _favoriteEvents.add(eventId);
      }
    });

    await docRef.update({'favoriteEvents': _favoriteEvents});
  }

  void refreshEvents() {
    if (!mounted) return;
    setState(() {
      _events.clear();
      _selectedEvents.clear();
    });
  }

  void deleteEvent(String eventId) async {
    try {
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .delete();
      refreshEvents();
    } catch (e) {
      _showStyledError(
          context, "Erreur lors de la suppression de l'événement : $e");
    }
  }

  void _showStyledError(BuildContext context, String message) {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? Color(0xFF23272F) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Icon(Icons.error, color: isDarkMode ? Colors.red[300] : Colors.red),
            SizedBox(width: 8),
            Text("Erreur",
                style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.red[800])),
          ],
        ),
        content: Text(message,
            style:
                TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("OK",
                style: TextStyle(
                    color: isDarkMode ? Colors.blue[200] : Colors.blue)),
          ),
        ],
      ),
    );
  }

  void _showLoginPrompt() {
    final isDarkMode =
        Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: isDarkMode ? Colors.amber : Colors.blue),
            SizedBox(width: 8),
            Text("Connexion requise",
                style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87)),
          ],
        ),
        content: Text(
            "Veuillez vous connecter pour utiliser cette fonctionnalité.",
            style:
                TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text("Annuler",
                style: TextStyle(
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2))),
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
                    color: isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2))),
          ),
        ],
        backgroundColor: isDarkMode ? Color(0xFF2A2F32) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    );
  }

  Future<void> _addComment(String eventId) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _commentController.text.isNotEmpty) {
      try {
        int? rating;
        if (_ratingController.text.isNotEmpty) {
          rating = int.tryParse(_ratingController.text);
          if (rating == null || rating < 1 || rating > 5) {
            _showErrorSnackBar("La note doit être entre 1 et 5.");
            return;
          }
        }
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        final pseudo = doc.data()?['pseudo'] ?? 'Utilisateur';
        final role = doc.data()?['role'] ?? 'user';
        await FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .collection('comments')
            .add({
          'authorId': user.uid,
          'authorName': pseudo,
          'authorRole': role,
          'text': _commentController.text,
          if (rating != null) 'rating': rating,
          'timestamp': FieldValue.serverTimestamp(),
          'likes': [],
          'pinnedAt': null,
        });
        if (!mounted) return;
        setState(() {
          _commentController.clear();
          _ratingController.clear();
        });
      } catch (e) {
        _showErrorSnackBar("Erreur lors de l'ajout du commentaire : $e");
      }
    }
  }

  Future<void> _addReply(
    String eventId,
    String commentId,
    String replyText,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || replyText.trim().isEmpty) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final pseudo = doc.data()?['pseudo'] ?? 'Utilisateur';
    final role = doc.data()?['role'] ?? 'user';
    await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('comments')
        .doc(commentId)
        .collection('replies')
        .add({
      'userId': user.uid,
      'pseudo': pseudo,
      'role': role,
      'reply': replyText.trim(),
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _addQuestion(String eventId) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && _questionController.text.trim().isNotEmpty) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final pseudo = doc.data()?['pseudo'] ?? 'Utilisateur';
      final role = doc.data()?['role'] ?? 'user';
      await FirebaseFirestore.instance
          .collection('events')
          .doc(eventId)
          .collection('questions')
          .add({
        'authorId': user.uid,
        'authorName': pseudo,
        'authorRole': role,
        'text': _questionController.text.trim(),
        'timestamp': FieldValue.serverTimestamp(),
        'answer': '',
      });
      if (!mounted) return;
      setState(() {
        _questionController.clear();
      });
    }
  }

  Future<void> _addAnswer(
    String eventId,
    String questionId,
    String answer,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    await FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('questions')
        .doc(questionId)
        .update({'answer': answer});
    if (!mounted) return;
    setState(() {
      _answerControllers[questionId]?.clear();
    });
  }

  void _showErrorSnackBar(String message) {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isDarkMode ? Color(0xFFFF3B30) : Colors.red,
      ),
    );
  }

  Future<void> _toggleLikeComment(
    String eventId,
    String commentId,
    String userId,
    String? creatorId,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    final ref = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('comments')
        .doc(commentId);

    final doc = await ref.get();
    final data = doc.data() as Map<String, dynamic>;
    List likes = List<String>.from(data['likes'] ?? []);
    bool creatorLiked = data['creatorLiked'] ?? false;

    if (likes.contains(userId)) {
      likes.remove(userId);
      if (userId == creatorId) creatorLiked = false;
    } else {
      likes.add(userId);
      if (userId == creatorId) creatorLiked = true;
    }

    await ref.update({'likes': likes, 'creatorLiked': creatorLiked});
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
      _showStyledError(context, "$limitText\n$waitMsg");
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Événement partagé dans le city chat de $city "),
        backgroundColor: Colors.green,
      ),
    );
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

  Future<void> _togglePinComment(
    String eventId,
    String commentId,
    bool isPinned,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    final ref = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('comments')
        .doc(commentId);

    if (isPinned) {
      await ref.update({'pinnedAt': null});
    } else {
      await ref.update({'pinnedAt': FieldValue.serverTimestamp()});
    }
  }

  Future<void> _deleteCommentWithConfirmation(
    String eventId,
    String commentId,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer le commentaire"),
        content: const Text("Voulez-vous vraiment supprimer ce commentaire ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Supprimer"),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode ? Color(0xFFFF3B30) : Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .collection('comments')
            .doc(commentId)
            .delete();
      } catch (e) {
        _showErrorSnackBar("Erreur lors de la suppression du commentaire : $e");
      }
    }
  }

  Future<void> _deleteQuestionWithConfirmation(
    String eventId,
    String questionId,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer la question"),
        content: const Text("Voulez-vous vraiment supprimer cette question ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Supprimer"),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDarkMode ? Color(0xFFFF3B30) : Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('events')
            .doc(eventId)
            .collection('questions')
            .doc(questionId)
            .delete();
      } catch (e) {
        _showErrorSnackBar("Erreur lors de la suppression de la question : $e");
      }
    }
  }

  bool _canRateEvent(Timestamp eventTimestamp) {
    final eventDate = eventTimestamp.toDate();
    final now = DateTime.now();
    return now.isAfter(eventDate.add(const Duration(hours: 1)));
  }

  String _formatDateFr(DateTime date) {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (date.hour != 0 || date.minute != 0) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à $heure:$minute";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<bool> _checkBossStatus() async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      final prefs = await SharedPreferences.getInstance();
      String? deviceUserId = prefs.getString('userId');
      if (deviceUserId != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(deviceUserId)
            .get();
        Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
        return userData != null && userData['role'] == 'boss';
      }
      return false;
    }
    DocumentSnapshot doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    Map<String, dynamic>? userData = doc.data() as Map<String, dynamic>?;
    return userData != null && userData['role'] == 'boss';
  }

  void _goToAdminPage() async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    bool isBoss = await _checkBossStatus();
    if (isBoss) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/admin_organizer_requests');
    } else {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Accès refusé"),
          content: const Text(
            "Vous n'êtes pas autorisé à accéder à cette page.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _registerUniqueView(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef =
        FirebaseFirestore.instance.collection('events').doc(eventId);
    final viewDoc = await eventRef.collection('views').doc(user.uid).get();
    if (!viewDoc.exists) {
      await eventRef.collection('views').doc(user.uid).set({
        'userId': user.uid,
        'viewedAt': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  Future<void> _handleShareInChat(String eventId, String city) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final role = userDoc.data()?['role'] ?? '';
    final isPremium = userDoc.data()?['subscriptionStatus'] == 'active';
    final now = DateTime.now();

    final shareDocRef = FirebaseFirestore.instance
        .collection('events')
        .doc(eventId)
        .collection('shares')
        .doc(user.uid);

    final shareDoc = await shareDocRef.get();
    int shareCount = 0;
    DateTime? lastShareDate;
    if (shareDoc.exists) {
      shareCount = shareDoc.data()?['count'] ?? 0;
      final ts = shareDoc.data()?['lastShare'] as Timestamp?;
      lastShareDate = ts?.toDate();
    }

    bool canShare = false;
    if (role == 'boss') {
      canShare = true;
    } else if (isPremium) {
      if (lastShareDate == null || !_isSameDay(now, lastShareDate)) {
        shareCount = 0;
      }
      canShare = shareCount < 10;
    } else {
      if (lastShareDate == null || !_isSameDay(now, lastShareDate)) {
        shareCount = 0;
      }
      canShare = shareCount < 1;
    }

    if (!canShare) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Limite de partage atteinte pour aujourd'hui."),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('city_chats')
        .doc(city)
        .collection('messages')
        .add({
      'type': 'event_share',
      'eventId': eventId,
      'userId': user.uid,
      'timestamp': Timestamp.now(),
      'text': "Découvrez cet événement ",
    });

    await shareDocRef.set({
      'count': shareCount + 1,
      'lastShare': Timestamp.fromDate(now),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Événement partagé dans le chat général "),
        backgroundColor: Colors.green,
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime? b) {
    if (b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _handleUnparticipate(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef =
        FirebaseFirestore.instance.collection('events').doc(eventId);
    final eventDoc = await eventRef.get();
    final participants = (eventDoc.data()?['participants'] ?? []) as List;
    final newParticipants =
        participants.where((p) => p is Map && p['userId'] != user.uid).toList();
    await eventRef.update({'participants': newParticipants});
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildCertificationBadge(String? role) {
    if (role == 'premium') {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.verified, color: Colors.amber, size: 18),
      );
    } else if (role == 'boss') {
      return Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.verified_user, color: Colors.blue, size: 18),
      );
    }
    return SizedBox.shrink();
  }

  void _showCommentsSheet(
    BuildContext context,
    String eventId,
    bool canRate,
    User? user,
    String? creatorId,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    bool isBoss = await _checkBossStatus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDarkMode ? Color(0xFF23272F) : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Commentaires",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .doc(eventId)
                      .collection('comments')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final comments = snapshot.data!.docs;
                    if (comments.isEmpty) {
                      return Center(
                        child: Text(
                          "Aucun commentaire.",
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      );
                    }
                    return ListView.builder(
                      itemCount: comments.length,
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        final commentId = comment.id;
                        final data = comment.data() as Map<String, dynamic>;
                        final pseudo = data['authorName'] ??
                            data['pseudo'] ??
                            'Utilisateur';
                        final text = data['text'] ?? data['comment'] ?? '';
                        final authorId = data['authorId'] ?? data['userId'];
                        final authorRole = data['authorRole'] ?? data['role'];
                        final likes = List<String>.from(data['likes'] ?? []);
                        final isPinned = data['pinnedAt'] != null;
                        final isLikedByCreator = data['creatorLiked'] == true;
                        final isMyComment =
                            user != null && authorId == user.uid;
                        return Card(
                          color: isPinned
                              ? (isDarkMode
                                  ? Colors.grey[800]
                                  : Colors.yellow[100])
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      pseudo,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    _buildCertificationBadge(authorRole),
                                    if (isPinned)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Icon(
                                          Icons.push_pin,
                                          size: 16,
                                          color: isDarkMode
                                              ? Colors.orange
                                              : Colors.orange,
                                        ),
                                      ),
                                  ],
                                ),
                                Text(
                                  text,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                                if (isLikedByCreator)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      "L’organisateur a aimé ce commentaire",
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.orange
                                            : Colors.orange,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        likes.contains(user?.uid)
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                        color: likes.contains(user?.uid)
                                            ? (isDarkMode
                                                ? Colors.red
                                                : Colors.red)
                                            : (isDarkMode
                                                ? Colors.grey
                                                : Colors.grey),
                                        size: 20,
                                      ),
                                      onPressed: user == null
                                          ? null
                                          : () => _toggleLikeComment(
                                                eventId,
                                                commentId,
                                                user.uid,
                                                creatorId,
                                              ),
                                    ),
                                    Text(
                                      '${likes.length}',
                                      style: TextStyle(
                                        color: isDarkMode
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                    if (creatorId == user?.uid || isBoss)
                                      IconButton(
                                        icon: Icon(
                                          isPinned
                                              ? Icons.push_pin
                                              : Icons.push_pin_outlined,
                                          color: isDarkMode
                                              ? Colors.orange
                                              : Colors.orange,
                                          size: 20,
                                        ),
                                        onPressed: () => _togglePinComment(
                                          eventId,
                                          commentId,
                                          isPinned,
                                        ),
                                      ),
                                    if (isMyComment ||
                                        creatorId == user?.uid ||
                                        isBoss)
                                      IconButton(
                                        icon: Icon(
                                          Icons.delete,
                                          color: isDarkMode
                                              ? Color(0xFFFF3B30)
                                              : Colors.red,
                                          size: 20,
                                        ),
                                        onPressed: () =>
                                            _deleteCommentWithConfirmation(
                                          eventId,
                                          commentId,
                                        ),
                                      ),
                                  ],
                                ),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('events')
                                      .doc(eventId)
                                      .collection('comments')
                                      .doc(commentId)
                                      .collection('replies')
                                      .orderBy('timestamp')
                                      .snapshots(),
                                  builder: (context, replySnapshot) {
                                    if (!replySnapshot.hasData)
                                      return const SizedBox();
                                    final replies = replySnapshot.data!.docs;
                                    return Column(
                                      children: [
                                        ...replies.map((replyDoc) {
                                          final reply = replyDoc.data()
                                              as Map<String, dynamic>;
                                          final replyRole =
                                              reply['role'] ?? 'user';
                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              left: 16,
                                              top: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                Text(
                                                  "${reply['pseudo'] ?? 'Utilisateur'} :",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                    color: isDarkMode
                                                        ? Colors.white
                                                        : Colors.black87,
                                                  ),
                                                ),
                                                _buildCertificationBadge(
                                                    replyRole),
                                                const SizedBox(width: 4),
                                                Text(
                                                  reply['reply'] ?? '',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: isDarkMode
                                                        ? Colors.white70
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        if (user != null)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              left: 16,
                                              top: 4,
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: _replyControllers[
                                                            commentId] ??=
                                                        TextEditingController(),
                                                    decoration:
                                                        const InputDecoration(
                                                      hintText: "Répondre...",
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.symmetric(
                                                        vertical: 8,
                                                        horizontal: 8,
                                                      ),
                                                    ),
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: isDarkMode
                                                          ? Colors.white70
                                                          : Colors.black54,
                                                    ),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.send,
                                                    size: 18,
                                                    color: isDarkMode
                                                        ? Color(0xFF34AADC)
                                                        : Color(0xFF2196F3),
                                                  ),
                                                  onPressed: () async {
                                                    final replyText =
                                                        _replyControllers[
                                                                    commentId]
                                                                ?.text ??
                                                            '';
                                                    if (replyText
                                                        .trim()
                                                        .isNotEmpty) {
                                                      await _addReply(
                                                        eventId,
                                                        commentId,
                                                        replyText,
                                                      );
                                                      if (!mounted) return;
                                                      setState(() {
                                                        _replyControllers[
                                                                commentId]
                                                            ?.clear();
                                                      });
                                                    }
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Divider(
                color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
              ),
              if (user != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _commentController,
                          decoration: InputDecoration(
                            hintText: "Ajouter un commentaire",
                            labelStyle: TextStyle(
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: 10, horizontal: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        width: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _addComment(eventId);
                            if (!mounted) return;
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isDarkMode ? Color(0xFF34AADC) : Colors.blue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                            padding: EdgeInsets.zero,
                          ),
                          child: Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (user == null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "Connectez-vous pour commenter.",
                    style: TextStyle(
                      color: isDarkMode ? Colors.orange : Colors.red,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showQuestionsSheet(
    BuildContext context,
    String eventId,
    String? creatorId,
    User? user,
  ) async {
    final isDarkMode = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).isDarkMode;
    bool isBoss = await _checkBossStatus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDarkMode ? Color(0xFF23272F) : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                "Questions",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('events')
                      .doc(eventId)
                      .collection('questions')
                      .orderBy('timestamp', descending: false)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final questions = snapshot.data!.docs;
                    if (questions.isEmpty)
                      return Center(
                        child: Text(
                          "Aucune question.",
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      );
                    return ListView.builder(
                      itemCount: questions.length,
                      itemBuilder: (context, index) {
                        final question = questions[index];
                        final questionId = question.id;
                        final data = question.data() as Map<String, dynamic>;
                        final pseudo = data['authorName'] ??
                            data['pseudo'] ??
                            'Utilisateur';
                        final text = data['text'] ?? data['question'] ?? '';
                        final authorId = data['authorId'] ?? data['userId'];
                        final authorRole = data['authorRole'] ?? data['role'];
                        final isCreator = creatorId == user?.uid;
                        final isMyQuestion =
                            user != null && authorId == user.uid;
                        return Card(
                          color: isDarkMode ? Colors.grey[800] : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      pseudo,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    _buildCertificationBadge(authorRole),
                                  ],
                                ),
                                Text(
                                  text,
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                                if ((data['answer'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          color: isDarkMode
                                              ? Color(0xFF00C73C)
                                              : Color(0xFF2196F3),
                                          size: 16,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Réponse : ${data['answer']}",
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Color(0xFF00C73C)
                                                : Color(0xFF2196F3),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isCreator || isBoss)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: TextField(
                                            controller: _answerControllers[
                                                    questionId] ??=
                                                TextEditingController(),
                                            decoration: InputDecoration(
                                              hintText:
                                                  "Répondre à la question...",
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 8,
                                                horizontal: 8,
                                              ),
                                              labelStyle: TextStyle(
                                                color: isDarkMode
                                                    ? Colors.white70
                                                    : Colors.black87,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black54,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: Icon(
                                            Icons.send,
                                            size: 18,
                                            color: isDarkMode
                                                ? Color(0xFF34AADC)
                                                : Color(0xFF2196F3),
                                          ),
                                          onPressed: () async {
                                            final answerText =
                                                _answerControllers[questionId]
                                                        ?.text ??
                                                    '';
                                            if (answerText.trim().isNotEmpty) {
                                              await _addAnswer(
                                                eventId,
                                                questionId,
                                                answerText,
                                              );
                                              if (!mounted) return;
                                              setState(() {
                                                _answerControllers[questionId]
                                                    ?.clear();
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                if (isMyQuestion || isCreator || isBoss)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: isDarkMode
                                            ? Color(0xFFFF3B30)
                                            : Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () =>
                                          _deleteQuestionWithConfirmation(
                                        eventId,
                                        questionId,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              Divider(
                color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
              ),
              if (user != null)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _questionController,
                          decoration: InputDecoration(
                            hintText: "Poser une question",
                            labelStyle: TextStyle(
                              color:
                                  isDarkMode ? Colors.white70 : Colors.black87,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () async {
                          await _addQuestion(eventId);
                          if (!mounted) return;
                        },
                        child: Text(
                          "Envoyer",
                          style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isDarkMode ? Color(0xFF34AADC) : Colors.blue,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              if (user == null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "Connectez-vous pour poser une question.",
                    style: TextStyle(
                      color: isDarkMode ? Colors.orange : Colors.red,
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
    final String city = _city;
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        color: themeProvider.isDarkMode
            ? Color(0xFF1A252F)
            : const Color(0xFFF5F6FA),
        child: SafeArea(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('events')
                .where('city', isEqualTo: city)
                .where('status', isEqualTo: 'approved')
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              _events.clear();
              for (var doc in snapshot.data!.docs) {
                DateTime eventDate = (doc['date'] as Timestamp).toDate();
                DateTime eventDay = DateTime(
                  eventDate.year,
                  eventDate.month,
                  eventDate.day,
                );
                if (_events[eventDay] == null) _events[eventDay] = [];
                _events[eventDay]!.add(doc);
              }
              if (_selectedDay != null) {
                DateTime normalizedSelectedDay = DateTime(
                  _selectedDay!.year,
                  _selectedDay!.month,
                  _selectedDay!.day,
                );
                _selectedEvents = _events[normalizedSelectedDay] ?? [];
              } else {
                _selectedEvents = [];
              }

              return Column(
                children: [
                  Container(
                    margin: EdgeInsets.all(screenWidth * 0.06),
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: themeProvider.isDarkMode
                            ? [Color(0xFF0F1419), Color(0xFF2A2F32)]
                            : [Colors.blue[800]!, Colors.blue[300]!],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: themeProvider.isDarkMode
                              ? Colors.black26
                              : Colors.black12.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Événements à $city",
                              style: TextStyle(
                                fontSize: screenWidth * 0.052,
                                fontWeight: FontWeight.bold,
                                color: themeProvider.isDarkMode
                                    ? Colors.white
                                    : Colors.white,
                                fontFamily: 'Roboto',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow
                                  .visible, // plus besoin d'ellipsis ici
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            if (_isBoss)
                              IconButton(
                                icon: Icon(
                                  Icons.admin_panel_settings,
                                  color: themeProvider.isDarkMode
                                      ? Colors.amber
                                      : Colors.amber,
                                  size: screenWidth * 0.07,
                                ),
                                tooltip: "Admin demandes organisateur",
                                onPressed: _goToAdminPage,
                              ),
                            if (user != null)
                              IconButton(
                                icon: Icon(
                                  Icons.favorite,
                                  color: themeProvider.isDarkMode
                                      ? Colors.red
                                      : Colors.red,
                                  size: screenWidth * 0.07,
                                ),
                                tooltip: "Mes favoris",
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/favorites',
                                    arguments: {
                                      'city': city,
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
                  Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.05,
                        vertical: screenWidth * 0.03,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: screenWidth * 0.04,
                        vertical: screenWidth * 0.025,
                      ),
                      decoration: BoxDecoration(
                        color: themeProvider.isDarkMode
                            ? Color(0xFF23272F)
                            : Colors.white,
                        borderRadius:
                            BorderRadius.circular(screenWidth * 0.045),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.isDarkMode
                                ? Colors.black26
                                : Colors.black12.withOpacity(0.10),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TableCalendar(
                        locale: 'fr_FR',
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                            DateTime normalizedSelectedDay = DateTime(
                              selectedDay.year,
                              selectedDay.month,
                              selectedDay.day,
                            );
                            _selectedEvents =
                                _events[normalizedSelectedDay] ?? [];
                          });
                        },
                        eventLoader: (day) {
                          DateTime normalizedDay =
                              DateTime(day.year, day.month, day.day);
                          var eventsForDay = _events[normalizedDay] ?? [];
                          return eventsForDay.isNotEmpty
                              ? [eventsForDay.first]
                              : [];
                        },
                        calendarFormat: _calendarFormat,
                        onFormatChanged: (format) {
                          setState(() {
                            _calendarFormat = format;
                          });
                        },
                        calendarStyle: CalendarStyle(
                          defaultDecoration: BoxDecoration(
                            color: themeProvider.isDarkMode
                                ? Color(0xFF23272F)
                                : Color(0xFFF5F6FA),
                            borderRadius: BorderRadius.circular(
                                screenWidth < 350 ? 7 : screenWidth * 0.018),
                          ),
                          todayDecoration: BoxDecoration(
                            color: themeProvider.isDarkMode
                                ? Colors.orange[700]
                                : Color(0xFFEF6C00),
                            borderRadius: BorderRadius.circular(
                                screenWidth < 350 ? 7 : screenWidth * 0.018),
                          ),
                          selectedDecoration: BoxDecoration(
                            color: themeProvider.isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            borderRadius: BorderRadius.circular(
                                screenWidth < 350 ? 7 : screenWidth * 0.018),
                          ),
                          markerDecoration: BoxDecoration(
                            color: themeProvider.isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            shape: BoxShape.circle,
                          ),
                          markerSize:
                              screenWidth < 350 ? 8 : screenWidth * 0.018,
                          weekendTextStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.orange
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize:
                                screenWidth < 350 ? 13 : screenWidth * 0.032,
                          ),
                          outsideTextStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.grey[700]
                                : Colors.grey[400],
                            fontSize:
                                screenWidth < 350 ? 13 : screenWidth * 0.032,
                          ),
                          defaultTextStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.black87,
                            fontSize:
                                screenWidth < 350 ? 13 : screenWidth * 0.032,
                          ),
                          selectedTextStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize:
                                screenWidth < 350 ? 14 : screenWidth * 0.035,
                          ),
                          todayTextStyle: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize:
                                screenWidth < 350 ? 14 : screenWidth * 0.035,
                          ),
                        ),
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          leftChevronIcon: Icon(
                            Icons.chevron_left,
                            color: themeProvider.isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            size: screenWidth * 0.07,
                          ),
                          rightChevronIcon: Icon(
                            Icons.chevron_right,
                            color: themeProvider.isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            size: screenWidth * 0.07,
                          ),
                          titleTextStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.white
                                : Color(0xFF1976D2),
                            fontWeight: FontWeight.bold,
                            fontSize: screenWidth * 0.045,
                          ),
                          headerPadding: EdgeInsets.symmetric(
                              vertical: screenWidth * 0.01),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.white70
                                : Colors.black54,
                            fontWeight: FontWeight.w600,
                            fontSize: screenWidth * 0.038,
                            height: 1.3,
                          ),
                          weekendStyle: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.orange
                                : Colors.red,
                            fontWeight: FontWeight.w600,
                            fontSize: screenWidth * 0.038,
                            height: 1.3,
                          ),
                        ),
                        calendarBuilders: CalendarBuilders(),
                      )),
                  Expanded(
                    child: _selectedEvents.isEmpty
                        ? Center(
                            child: Text(
                              "Aucun événement pour ce jour",
                              style: TextStyle(
                                color: themeProvider.isDarkMode
                                    ? Colors.white70
                                    : Colors.grey,
                                fontSize: 18,
                                fontFamily: 'Roboto',
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 64),
                            itemCount: _selectedEvents.length,
                            itemBuilder: (context, index) {
                              final event = _selectedEvents[index];
                              final eventId = event.id;
                              final isFavorite = _favoriteEvents.contains(
                                eventId,
                              );
                              final String? creatorId = event['creatorId'];
                              final String? currentUserId =
                                  FirebaseAuth.instance.currentUser?.uid;
                              final bool canDelete =
                                  _isBoss || creatorId == currentUserId;
                              final eventTimestamp = event['date'] as Timestamp;
                              final bool canRate = _canRateEvent(
                                eventTimestamp,
                              );

                              return EventCard(
                                event: event,
                                isFavorite: isFavorite,
                                canDelete: canDelete,
                                onFavorite: () => _toggleFavorite(eventId),
                                onDelete: () => deleteEvent(eventId),
                                onTap: () {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: true,
                                    builder: (context) {
                                      return Dialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              screenWidth * 0.06),
                                        ),
                                        backgroundColor:
                                            themeProvider.isDarkMode
                                                ? Colors.grey[900]
                                                : Colors.white,
                                        child: Padding(
                                          padding: EdgeInsets.all(
                                              screenWidth * 0.05),
                                          child: SingleChildScrollView(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Titre, badge certif, bouton signaler et croix
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Flexible(
                                                            child: Text(
                                                              event['title'] ??
                                                                  'Sans titre',
                                                              style: TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize:
                                                                    screenWidth *
                                                                        0.052,
                                                                color: themeProvider
                                                                        .isDarkMode
                                                                    ? Color(
                                                                        0xFF34AADC)
                                                                    : Color(
                                                                        0xFF1976D2),
                                                              ),
                                                              maxLines: 2,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                            ),
                                                          ),
                                                          _buildCertificationBadge(
                                                              event['creatorRole'] ??
                                                                  event[
                                                                      'role']),
                                                        ],
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon: Icon(Icons.report,
                                                          color:
                                                              Colors.redAccent,
                                                          size: screenWidth *
                                                              0.055),
                                                      tooltip: "Signaler",
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                      onPressed: () async {
                                                        await _reportEvent(
                                                            context, eventId);
                                                      },
                                                    ),
                                                    IconButton(
                                                      icon: Icon(Icons.close,
                                                          size: screenWidth *
                                                              0.055,
                                                          color: themeProvider
                                                                  .isDarkMode
                                                              ? Colors.white38
                                                              : Colors
                                                                  .grey[600]),
                                                      padding: EdgeInsets.zero,
                                                      constraints:
                                                          const BoxConstraints(),
                                                      tooltip: "Fermer",
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context),
                                                    ),
                                                  ],
                                                ),
                                                // Badge ville
                                                if (event['city'] != null &&
                                                    event['city']
                                                        .toString()
                                                        .isNotEmpty)
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: Container(
                                                      margin: EdgeInsets.only(
                                                        top: screenWidth * 0.01,
                                                        bottom:
                                                            screenWidth * 0.02,
                                                      ),
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                        horizontal:
                                                            screenWidth * 0.03,
                                                        vertical:
                                                            screenWidth * 0.013,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: themeProvider
                                                                .isDarkMode
                                                            ? Colors
                                                                .blueGrey[900]
                                                            : Colors.blue[50],
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(
                                                                    screenWidth *
                                                                        0.035),
                                                        border: Border.all(
                                                          color: themeProvider
                                                                  .isDarkMode
                                                              ? Colors
                                                                  .blue[200]!
                                                              : Colors.blue,
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                              Icons.location_on,
                                                              color: themeProvider
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .blue[200]
                                                                  : Colors.blue,
                                                              size:
                                                                  screenWidth *
                                                                      0.04),
                                                          SizedBox(
                                                              width:
                                                                  screenWidth *
                                                                      0.01),
                                                          Text(
                                                            event['city'],
                                                            style: TextStyle(
                                                              color: themeProvider
                                                                      .isDarkMode
                                                                  ? Colors
                                                                      .blue[100]
                                                                  : Colors.blue[
                                                                      900],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              fontSize:
                                                                  screenWidth *
                                                                      0.035,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                // Carousel images
                                                if (event['images'] != null &&
                                                    event['images'] is List &&
                                                    (event['images'] as List)
                                                        .isNotEmpty)
                                                  Padding(
                                                    padding: EdgeInsets.only(
                                                        bottom:
                                                            screenWidth * 0.03),
                                                    child: _EventImageCarousel(
                                                      images: event['images'],
                                                      height:
                                                          screenWidth * 0.55,
                                                    ),
                                                  ),
                                                // Infos
                                                Row(
                                                  children: [
                                                    Icon(Icons.calendar_today,
                                                        size:
                                                            screenWidth * 0.045,
                                                        color:
                                                            Color(0xFF2196F3)),
                                                    SizedBox(
                                                        width:
                                                            screenWidth * 0.02),
                                                    Flexible(
                                                      child: Text(
                                                        "Date : ${_formatDateFr((event['date'] as Timestamp).toDate())}",
                                                        style: TextStyle(
                                                            fontSize:
                                                                screenWidth *
                                                                    0.038),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(
                                                    height: screenWidth * 0.01),
                                                Row(
                                                  children: [
                                                    Icon(Icons.place,
                                                        size:
                                                            screenWidth * 0.045,
                                                        color:
                                                            Color(0xFF2196F3)),
                                                    SizedBox(
                                                        width:
                                                            screenWidth * 0.02),
                                                    Flexible(
                                                      child: Text(
                                                        "Lieu : ${event['location'] ?? 'Non spécifié'}",
                                                        style: TextStyle(
                                                            fontSize:
                                                                screenWidth *
                                                                    0.038),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(
                                                    height: screenWidth * 0.01),
                                                Row(
                                                  children: [
                                                    Icon(Icons.category,
                                                        size:
                                                            screenWidth * 0.045,
                                                        color:
                                                            Color(0xFF2196F3)),
                                                    SizedBox(
                                                        width:
                                                            screenWidth * 0.02),
                                                    Flexible(
                                                      child: Text(
                                                        "Catégorie : ${event['category'] ?? 'Non spécifiée'}",
                                                        style: TextStyle(
                                                            fontSize:
                                                                screenWidth *
                                                                    0.038),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                SizedBox(
                                                    height:
                                                        screenWidth * 0.025),
                                                Text(
                                                  "Description :",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize:
                                                        screenWidth * 0.038,
                                                    color:
                                                        themeProvider.isDarkMode
                                                            ? Colors.white
                                                            : Colors.black87,
                                                  ),
                                                ),
                                                SizedBox(
                                                    height: screenWidth * 0.01),
                                                Text(
                                                  event['description'] ??
                                                      'Aucune description',
                                                  style: TextStyle(
                                                    fontSize:
                                                        screenWidth * 0.038,
                                                    color:
                                                        themeProvider.isDarkMode
                                                            ? Colors.white70
                                                            : Colors.black87,
                                                  ),
                                                  maxLines: 5,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                SizedBox(
                                                    height:
                                                        screenWidth * 0.045),
                                                // Boutons actions harmonisés et responsive
                                                LayoutBuilder(
                                                  builder:
                                                      (context, constraints) {
                                                    double btnWidth = (constraints
                                                                .maxWidth <
                                                            400)
                                                        ? (constraints
                                                                    .maxWidth -
                                                                32) /
                                                            2
                                                        : 140;
                                                    btnWidth = btnWidth < 90
                                                        ? 90
                                                        : btnWidth;
                                                    double btnHeight = 38;
                                                    double btnFont =
                                                        screenWidth * 0.035;

                                                    return Wrap(
                                                      spacing: 8,
                                                      runSpacing: 8,
                                                      alignment:
                                                          WrapAlignment.center,
                                                      children: [
                                                        SizedBox(
                                                          width: btnWidth,
                                                          height: btnHeight,
                                                          child: FutureBuilder<
                                                              bool>(
                                                            future: () async {
                                                              final user =
                                                                  FirebaseAuth
                                                                      .instance
                                                                      .currentUser;
                                                              if (user == null)
                                                                return false;
                                                              final participations = await FirebaseFirestore
                                                                  .instance
                                                                  .collection(
                                                                      'event_participations')
                                                                  .where(
                                                                      'eventId',
                                                                      isEqualTo:
                                                                          eventId)
                                                                  .where(
                                                                      'userId',
                                                                      isEqualTo:
                                                                          user.uid)
                                                                  .get();
                                                              return participations
                                                                  .docs
                                                                  .isNotEmpty;
                                                            }(),
                                                            builder: (context,
                                                                snapshot) {
                                                              final isParticipating =
                                                                  snapshot.data ??
                                                                      false;
                                                              return ElevatedButton
                                                                  .icon(
                                                                icon: Icon(
                                                                  isParticipating
                                                                      ? Icons
                                                                          .close
                                                                      : Icons
                                                                          .event_available,
                                                                  size: btnFont,
                                                                ),
                                                                label:
                                                                    FittedBox(
                                                                  fit: BoxFit
                                                                      .scaleDown,
                                                                  child: Text(
                                                                    isParticipating
                                                                        ? "Se désinscrire"
                                                                        : "Participer",
                                                                    style:
                                                                        TextStyle(
                                                                      fontSize:
                                                                          btnFont,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                    ),
                                                                  ),
                                                                ),
                                                                style: ElevatedButton
                                                                    .styleFrom(
                                                                  backgroundColor: isParticipating
                                                                      ? Colors
                                                                          .redAccent
                                                                      : (themeProvider
                                                                              .isDarkMode
                                                                          ? Color(
                                                                              0xFF34AADC)
                                                                          : Color(
                                                                              0xFF1976D2)),
                                                                  foregroundColor:
                                                                      Colors
                                                                          .white,
                                                                  padding: EdgeInsets
                                                                      .symmetric(
                                                                          horizontal:
                                                                              6,
                                                                          vertical:
                                                                              2),
                                                                  shape:
                                                                      RoundedRectangleBorder(
                                                                    borderRadius:
                                                                        BorderRadius.circular(screenWidth *
                                                                            0.035),
                                                                  ),
                                                                  elevation: 4,
                                                                ),
                                                                onPressed:
                                                                    () async {
                                                                  final user =
                                                                      FirebaseAuth
                                                                          .instance
                                                                          .currentUser;
                                                                  if (user ==
                                                                      null)
                                                                    return;
                                                                  if (isParticipating) {
                                                                    final participations = await FirebaseFirestore
                                                                        .instance
                                                                        .collection(
                                                                            'event_participations')
                                                                        .where(
                                                                            'eventId',
                                                                            isEqualTo:
                                                                                eventId)
                                                                        .where(
                                                                            'userId',
                                                                            isEqualTo:
                                                                                user.uid)
                                                                        .get();
                                                                    for (var doc
                                                                        in participations
                                                                            .docs) {
                                                                      await doc
                                                                          .reference
                                                                          .delete();
                                                                    }
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text("Vous êtes désinscrit de l'événement."),
                                                                        backgroundColor:
                                                                            Colors.redAccent,
                                                                      ),
                                                                    );
                                                                  } else {
                                                                    await FirebaseFirestore
                                                                        .instance
                                                                        .collection(
                                                                            'event_participations')
                                                                        .add({
                                                                      'eventId':
                                                                          eventId,
                                                                      'userId':
                                                                          user.uid,
                                                                      'timestamp':
                                                                          FieldValue
                                                                              .serverTimestamp(),
                                                                    });
                                                                    ScaffoldMessenger.of(
                                                                            context)
                                                                        .showSnackBar(
                                                                      SnackBar(
                                                                        content:
                                                                            Text("Inscription confirmée à l'événement "),
                                                                        backgroundColor:
                                                                            Colors.green,
                                                                      ),
                                                                    );
                                                                  }
                                                                  if (!mounted)
                                                                    return;
                                                                  Navigator.pop(
                                                                      context);
                                                                },
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: btnWidth,
                                                          height: btnHeight,
                                                          child: ElevatedButton
                                                              .icon(
                                                            icon: Icon(
                                                                Icons.share,
                                                                size: btnFont),
                                                            label: FittedBox(
                                                              fit: BoxFit
                                                                  .scaleDown,
                                                              child: Text(
                                                                "Partager",
                                                                style:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      btnFont,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor:
                                                                  themeProvider
                                                                          .isDarkMode
                                                                      ? Colors
                                                                          .blueGrey
                                                                      : Colors.blue[
                                                                          800],
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding: EdgeInsets
                                                                  .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        screenWidth *
                                                                            0.035),
                                                              ),
                                                              elevation: 4,
                                                            ),
                                                            onPressed:
                                                                () async {
                                                              await shareEventToCityChat(
                                                                event,
                                                                event['city'] ??
                                                                    '',
                                                                event['creatorRole'] ??
                                                                    event[
                                                                        'role'] ??
                                                                    'user',
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: btnWidth,
                                                          height: btnHeight,
                                                          child: ElevatedButton
                                                              .icon(
                                                            icon: Icon(
                                                                Icons.comment,
                                                                size: btnFont),
                                                            label: FittedBox(
                                                              fit: BoxFit
                                                                  .scaleDown,
                                                              child: Text(
                                                                "Commentaires",
                                                                style:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      btnFont,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor: themeProvider
                                                                      .isDarkMode
                                                                  ? Color(
                                                                      0xFF34AADC)
                                                                  : Color(
                                                                      0xFF1976D2),
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding: EdgeInsets
                                                                  .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        screenWidth *
                                                                            0.035),
                                                              ),
                                                              elevation: 4,
                                                            ),
                                                            onPressed: () =>
                                                                _showCommentsSheet(
                                                                    context,
                                                                    eventId,
                                                                    canRate,
                                                                    user,
                                                                    creatorId),
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: btnWidth,
                                                          height: btnHeight,
                                                          child: ElevatedButton
                                                              .icon(
                                                            icon: Icon(
                                                                Icons
                                                                    .help_outline,
                                                                size: btnFont),
                                                            label: FittedBox(
                                                              fit: BoxFit
                                                                  .scaleDown,
                                                              child: Text(
                                                                "Questions",
                                                                style:
                                                                    TextStyle(
                                                                  fontSize:
                                                                      btnFont,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                ),
                                                              ),
                                                            ),
                                                            style:
                                                                ElevatedButton
                                                                    .styleFrom(
                                                              backgroundColor: themeProvider
                                                                      .isDarkMode
                                                                  ? Color(
                                                                      0xFF34AADC)
                                                                  : Color(
                                                                      0xFF1976D2),
                                                              foregroundColor:
                                                                  Colors.white,
                                                              padding: EdgeInsets
                                                                  .symmetric(
                                                                      horizontal:
                                                                          6,
                                                                      vertical:
                                                                          2),
                                                              shape:
                                                                  RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        screenWidth *
                                                                            0.035),
                                                              ),
                                                              elevation: 4,
                                                            ),
                                                            onPressed: () =>
                                                                _showQuestionsSheet(
                                                                    context,
                                                                    eventId,
                                                                    creatorId,
                                                                    user),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                                screenWidth: screenWidth,
                                screenHeight:
                                    MediaQuery.of(context).size.height,
                                isDarkMode: themeProvider.isDarkMode,
                                primaryColor: themeProvider.isDarkMode
                                    ? Color(0xFF34AADC)
                                    : Color(0xFF1976D2),
                                accentColor: themeProvider.isDarkMode
                                    ? Color(0xFFFF3B30)
                                    : Color(0xFFF44336),
                                errorColor: themeProvider.isDarkMode
                                    ? Color(0xFFFF3B30)
                                    : Color(0xFFF44336),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: themeProvider.isDarkMode
            ? Color(0xFF1A252F)
            : const Color(0xFFF5F6FA),
        elevation: 4,
        currentIndex: 2,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: ''),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_today), label: ''),
          BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble), label: ''), // Chat général ville
          BottomNavigationBarItem(icon: Icon(Icons.person), label: ''),
        ],
        selectedItemColor:
            themeProvider.isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
        unselectedItemColor:
            themeProvider.isDarkMode ? Colors.grey : Colors.grey,
        selectedIconTheme: IconThemeData(
          size: screenWidth * 0.07,
          color:
              themeProvider.isDarkMode ? Color(0xFF34AADC) : Color(0xFF1976D2),
        ),
        unselectedIconTheme: IconThemeData(
          size: screenWidth * 0.07,
          color: themeProvider.isDarkMode ? Colors.grey : Colors.grey,
        ),
        onTap: (index) async {
          final user = FirebaseAuth.instance.currentUser;
          if (index == 0) {
            bool? confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(
                  "Retour à l'accueil",
                  style: TextStyle(
                    color: themeProvider.isDarkMode
                        ? Colors.white
                        : Colors.black87,
                  ),
                ),
                content: Text(
                  "Êtes-vous sûr de vouloir retourner à la page d'accueil ?",
                  style: TextStyle(
                    color: themeProvider.isDarkMode
                        ? Colors.white70
                        : Colors.black54,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(
                      "Annuler",
                      style: TextStyle(
                        color: themeProvider.isDarkMode
                            ? Color(0xFF34AADC)
                            : Color(0xFF1976D2),
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      "Oui, retourner",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeProvider.isDarkMode
                          ? Color(0xFFFF3B30)
                          : Color(0xFFF44336),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
                backgroundColor:
                    themeProvider.isDarkMode ? Color(0xFF2A2F32) : Colors.white,
              ),
            );
            if (confirm == true) {
              Navigator.pushReplacementNamed(
                context,
                '/home',
                arguments: {
                  'city': _city,
                  'isOrganizer': _isOrganizer,
                },
              );
            }
          } else if (index == 1) {
            Navigator.pushReplacementNamed(
              context,
              '/events_list',
              arguments: {
                'city': _city,
                'isOrganizer': _isOrganizer,
              },
            );
          } else if (index == 2) {
            // Rester sur EventsPage
          } else if (index == 3) {
            // Aller sur le chat général de la ville
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
              _showStyledError(
                  context, "Connectez-vous pour accéder à votre profil.");
            }
          }
        },
      ),
    );
  }
}

class _EventImageCarousel extends StatefulWidget {
  final List images;
  final double height; // <-- Ajoute ce paramètre

  const _EventImageCarousel({
    required this.images,
    required this.height, // <-- Ajoute ce paramètre
    Key? key,
  }) : super(key: key);

  @override
  State<_EventImageCarousel> createState() => _EventImageCarouselState();
}

class _EventImageCarouselState extends State<_EventImageCarousel> {
  int _current = 0;

  void _showZoom(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (c, e, s) => Container(
              color: Colors.grey[300],
              width: widget.height,
              height: widget.height,
              child: Icon(Icons.broken_image,
                  color: Colors.grey, size: widget.height * 0.27),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final url = widget.images[i];
              return GestureDetector(
                onTap: () => _showZoom(url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.height * 0.07),
                  child: Image.network(
                    url,
                    width: widget.height,
                    height: widget.height,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: widget.height,
                      height: widget.height,
                      color: Colors.grey[300],
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.images.length > 1)
          Padding(
            padding: EdgeInsets.only(top: widget.height * 0.04),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.images.length,
                (i) => Container(
                  margin:
                      EdgeInsets.symmetric(horizontal: widget.height * 0.013),
                  width: widget.height * 0.045,
                  height: widget.height * 0.045,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _current == i ? Colors.blue : Colors.grey[400],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
