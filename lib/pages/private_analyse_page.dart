import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PrivateAnalysePage extends StatefulWidget {
  final String? calendarId;
  final String? calendarName;

  const PrivateAnalysePage({Key? key, this.calendarId, this.calendarName})
      : super(key: key);

  @override
  State<PrivateAnalysePage> createState() => _PrivateAnalysePageState();
}

class _PrivateAnalysePageState extends State<PrivateAnalysePage> {
  int _totalEntries = 0;
  int _eventLikes = 0;
  int _eventParticipants = 0;
  int _eventViews = 0;
  bool _loading = true;
  String? _calendarName;
  String? _role;

  int _selectedPeriod = 1; // 0: aujourd'hui, 1: 7j, 2: 30j

  @override
  void initState() {
    super.initState();
    _calendarName = widget.calendarName;
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    if (widget.calendarId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final role = userDoc['role'] ?? '';

    DateTime now = DateTime.now();
    DateTime minDate;
    if (_selectedPeriod == 0) {
      minDate = DateTime(now.year, now.month, now.day);
    } else if (_selectedPeriod == 1) {
      minDate = now.subtract(Duration(days: 6));
    } else {
      minDate = now.subtract(Duration(days: 29));
    }

    final calendarDoc = await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .get();
    final eventsSnap = await calendarDoc.reference.collection('events').get();

    int totalEntries = 0;
    int eventLikes = 0;
    int eventParticipants = 0;
    int eventViews = 0;

    // Accès validés (Entrées)
    if (calendarDoc.exists && calendarDoc.data()!.containsKey('entries')) {
      final entries = calendarDoc.data()!['entries'] as List;
      totalEntries = entries.where((entry) {
        if (entry is Map && entry.containsKey('timestamp')) {
          DateTime date = (entry['timestamp'] as Timestamp).toDate();
          return !date.isBefore(minDate);
        }
        return _selectedPeriod == 0 ? false : true;
      }).length;
    }

    // Pour chaque événement du calendrier privé
    for (final eventDoc in eventsSnap.docs) {
      final eventData = eventDoc.data();
      // Likes
      if (eventData.containsKey('likes') && eventData['likes'] is List) {
        final likes = eventData['likes'] as List;
        eventLikes += likes.where((like) {
          if (like is Map && like.containsKey('createdAt')) {
            DateTime date = (like['createdAt'] as Timestamp).toDate();
            return !date.isBefore(minDate);
          }
          return _selectedPeriod == 0 ? false : true;
        }).length;
      }
      // Participants
      if (eventData.containsKey('participants') &&
          eventData['participants'] is List) {
        final participants = eventData['participants'] as List;
        eventParticipants += participants.where((part) {
          if (part is Map && part.containsKey('timestamp')) {
            DateTime date = (part['timestamp'] as Timestamp).toDate();
            return !date.isBefore(minDate);
          }
          return _selectedPeriod == 0 ? false : true;
        }).length;
      }
      // Vues (sous-collection views)
      final viewsSnap = await eventDoc.reference.collection('views').get();
      eventViews += viewsSnap.docs.where((viewDoc) {
        final viewData = viewDoc.data();
        if (viewData.containsKey('timestamp')) {
          DateTime date = (viewData['timestamp'] as Timestamp).toDate();
          return !date.isBefore(minDate);
        }
        return _selectedPeriod == 0 ? false : true;
      }).length;
    }

    if (!mounted) return;
    setState(() {
      _role = role;
      _calendarName = widget.calendarName;
      _totalEntries = totalEntries;
      _eventLikes = eventLikes;
      _eventParticipants = eventParticipants;
      _eventViews = eventViews;
      _loading = false;
    });
  }

  Color get _mainColor {
    switch (_role) {
      case 'boss':
        return Colors.blue;
      case 'premium':
        return Colors.amber[800]!;
      default:
        return Colors.blueAccent;
    }
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    Color? bgColor,
    Color? valueColor,
    bool animate = true,
    required double cardFontSize,
    required double valueFontSize,
    required double iconSize,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark
          ? const Color(0xFF23272F)
          : (bgColor ?? color.withOpacity(0.08)),
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: cardFontSize * 1.1, horizontal: cardFontSize * 0.8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.18),
              child: Icon(icon, color: color, size: iconSize),
              radius: iconSize * 0.93,
            ),
            SizedBox(width: cardFontSize * 1.1),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: cardFontSize,
                  color: isDark ? Colors.white : color,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value.toDouble()),
              duration:
                  animate ? const Duration(milliseconds: 700) : Duration.zero,
              builder: (context, val, _) => Text(
                val.toInt().toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: valueFontSize,
                  color: isDark ? Colors.white : (valueColor ?? color),
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _periodSelector(double chipFontSize, double chipPadding) {
    final labels = ["Aujourd'hui", "7 jours", "30 jours"];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: chipPadding * 2,
      runSpacing: chipPadding,
      children: List.generate(
        3,
        (i) => ChoiceChip(
          label: Text(labels[i], style: TextStyle(fontSize: chipFontSize)),
          selected: _selectedPeriod == i,
          onSelected: (_) {
            setState(() {
              _selectedPeriod = i;
              _loading = true;
            });
            _fetchStats();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainColor = _mainColor;
    final bgColor = isDark ? const Color(0xFF181C20) : const Color(0xFFF7F8FA);

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.04;
    final double cardFontSize = screenWidth * 0.038;
    final double valueFontSize = screenWidth * 0.065;
    final double iconSize = screenWidth * 0.09;
    final double chipFontSize = screenWidth * 0.032;
    final double chipPadding = screenWidth * 0.012;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: "Retour",
        ),
        title: Text(
          _calendarName != null && _calendarName!.isNotEmpty
              ? _calendarName!
              : "Analyse calendrier",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: cardFontSize * 1.3,
            letterSpacing: 0.2,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(cardPadding * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: cardPadding * 0.5),
                  CircleAvatar(
                    radius: screenWidth * 0.11,
                    backgroundColor: mainColor.withOpacity(0.13),
                    child: Icon(
                      Icons.analytics,
                      size: screenWidth * 0.12,
                      color: mainColor,
                    ),
                  ),
                  SizedBox(height: cardPadding * 1.2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _calendarName != null && _calendarName!.isNotEmpty
                              ? _calendarName!
                              : "Calendrier privé",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: cardFontSize * 1.5,
                            color: isDark ? Colors.white : mainColor,
                            letterSpacing: 0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 10),
                      if (_role == 'boss' || _role == 'premium')
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: cardPadding * 0.7,
                              vertical: cardPadding * 0.3),
                          decoration: BoxDecoration(
                            color: _role == 'boss'
                                ? mainColor.withOpacity(0.13)
                                : Colors.amber.withOpacity(0.13),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _role == 'boss' ? Icons.verified : Icons.star,
                                color: _role == 'boss'
                                    ? mainColor
                                    : Colors.amber[800],
                                size: cardFontSize * 1.1,
                              ),
                              SizedBox(width: 4),
                              Text(
                                _role == 'boss' ? "Boss" : "Premium",
                                style: TextStyle(
                                  color: _role == 'boss'
                                      ? mainColor
                                      : Colors.amber[800],
                                  fontWeight: FontWeight.bold,
                                  fontSize: cardFontSize * 0.95,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 2),
                  _periodSelector(chipFontSize, chipPadding),
                  SizedBox(height: cardPadding * 1.5),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: screenWidth < 400 ? 1 : 2,
                      mainAxisSpacing: cardPadding * 1.1,
                      crossAxisSpacing: cardPadding * 1.1,
                      childAspectRatio: 2.1,
                    ),
                    children: [
                      _statCard(
                        icon: Icons.login,
                        label: "Accès validés",
                        value: _totalEntries,
                        color: Colors.blue,
                        bgColor:
                            isDark ? const Color(0xFF222A2F) : Colors.blue[50],
                        cardFontSize: cardFontSize,
                        valueFontSize: valueFontSize,
                        iconSize: iconSize,
                      ),
                      _statCard(
                        icon: Icons.favorite,
                        label: "Likes sur les events",
                        value: _eventLikes,
                        color: Colors.pink[400]!,
                        bgColor:
                            isDark ? const Color(0xFF2A2227) : Colors.pink[50],
                        cardFontSize: cardFontSize,
                        valueFontSize: valueFontSize,
                        iconSize: iconSize,
                      ),
                      _statCard(
                        icon: Icons.group,
                        label: "Participants inscrits",
                        value: _eventParticipants,
                        color: Colors.deepPurple,
                        bgColor: isDark
                            ? const Color(0xFF26222F)
                            : Colors.deepPurple[50],
                        cardFontSize: cardFontSize,
                        valueFontSize: valueFontSize,
                        iconSize: iconSize,
                      ),
                      _statCard(
                        icon: Icons.remove_red_eye,
                        label: "Vues sur les events",
                        value: _eventViews,
                        color: Colors.teal,
                        bgColor:
                            isDark ? const Color(0xFF22302F) : Colors.teal[50],
                        cardFontSize: cardFontSize,
                        valueFontSize: valueFontSize,
                        iconSize: iconSize,
                      ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 2.2),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: cardPadding * 1.2,
                        vertical: cardPadding * 1.1),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF23272F) : Colors.blue[50],
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: mainColor, size: cardFontSize * 1.2),
                        SizedBox(width: cardPadding * 0.7),
                        Expanded(
                          child: Text(
                            "Ces statistiques sont calculées sur les événements de ce calendrier privé. "
                            "Seuls les utilisateurs connectés sont comptés comme accès validés. "
                            "Invitez vos membres à se connecter ou créer un compte pour apparaître ici. "
                            "Les données sont conservées 31 jours maximum.",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey[700],
                              fontSize: cardFontSize * 0.98,
                            ),
                            textAlign: TextAlign.left,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: cardPadding * 1.5),
                ],
              ),
            ),
    );
  }
}
