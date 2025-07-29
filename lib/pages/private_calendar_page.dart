import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivateCalendarPage extends StatefulWidget {
  final Map<String, dynamic>? arguments;
  const PrivateCalendarPage({Key? key, this.arguments}) : super(key: key);

  @override
  State<PrivateCalendarPage> createState() => _PrivateCalendarPageState();
}

class _PrivateCalendarPageState extends State<PrivateCalendarPage> {
  late Map<DateTime, List<dynamic>> _events;
  late List<dynamic> _selectedEvents;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  bool _isOwner = false;
  String _calendarId = '';
  String _calendarName = '';
  String? _ownerId;
  int _selectedIndex = 1;
  List<String> _bossIds = [];

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('fr_FR', null);
    _events = {};
    _selectedEvents = [];
    _selectedDay =
        DateTime(_focusedDay.year, _focusedDay.month, _focusedDay.day);

    final args = widget.arguments;
    if (args != null) {
      _calendarId = args['calendarId'] ?? '';
      _calendarName = args['calendarName'] ?? 'Calendrier privé';
      _ownerId = args['ownerId'];
      _fetchOwnerAndBosses();
    }
  }

  Future<void> _fetchOwnerAndBosses() async {
    final user = FirebaseAuth.instance.currentUser;
    final doc = await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .get();
    final data = doc.data();
    if (data != null) {
      _ownerId = data['ownerId'];
      _bossIds = List<String>.from(data['bossIds'] ?? []);
      if (!mounted) return;
      setState(() {
        _isOwner = user != null &&
            (_ownerId == user.uid || _bossIds.contains(user.uid));
      });
    }
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
          .collection('private_calendars')
          .doc(_calendarId)
          .collection('events')
          .doc(eventId)
          .delete();
      refreshEvents();
    } catch (e) {
      _showErrorSnackBar("Erreur lors de la suppression de l'événement : $e");
    }
  }

  void _showErrorSnackBar(String message) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor:
              themeProvider.isDarkMode ? Colors.red[700] : Colors.red),
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

  Future<void> _registerUniqueView(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .collection('events')
        .doc(eventId);

    final viewDoc = await eventRef.collection('views').doc(user.uid).get();
    if (!viewDoc.exists) {
      await eventRef.collection('views').doc(user.uid).set({
        'userId': user.uid,
        'viewedAt': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  Future<void> _handleParticipate(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .collection('events')
        .doc(eventId);

    final eventDoc = await eventRef.get();
    final participants = (eventDoc.data()?['participants'] ?? []) as List;
    final already =
        participants.any((p) => p is Map && p['userId'] == user.uid);

    if (already) return;

    await eventRef.update({
      'participants': FieldValue.arrayUnion([
        {
          'userId': user.uid,
          'pseudo': user.displayName ?? '',
          'timestamp': Timestamp.fromDate(DateTime.now()),
        }
      ])
    });
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handleUnparticipate(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .collection('events')
        .doc(eventId);

    final eventDoc = await eventRef.get();
    final participants = (eventDoc.data()?['participants'] ?? []) as List;
    final newParticipants =
        participants.where((p) => p is Map && p['userId'] != user.uid).toList();

    await eventRef.update({'participants': newParticipants});
    if (!mounted) return;
    setState(() {});
  }

  // --- CORRECTION : Like/Unlike ajoute/retire aussi dans les favoris utilisateur ---
  Future<void> _handleLike(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .collection('events')
        .doc(eventId);

    final eventDoc = await eventRef.get();
    final likes = (eventDoc.data()?['likes'] ?? []) as List;
    final already = likes.any((l) => l is Map && l['userId'] == user.uid);

    if (already) return;

    // Ajoute le like dans l'event (pour les stats)
    await eventRef.update({
      'likes': FieldValue.arrayUnion([
        {
          'userId': user.uid,
          'createdAt': Timestamp.fromDate(DateTime.now()),
        }
      ])
    });

    // Ajoute le chemin complet dans les favoris utilisateur
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final eventPath = 'private_calendars/$_calendarId/events/$eventId';
    await userRef.update({
      'favoriteEvents': FieldValue.arrayUnion([eventPath])
    });

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handleUnlike(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(_calendarId)
        .collection('events')
        .doc(eventId);

    final eventDoc = await eventRef.get();
    final likes = (eventDoc.data()?['likes'] ?? []) as List;
    final newLikes =
        likes.where((l) => l is Map && l['userId'] != user.uid).toList();

    // Retire le like dans l'event (pour les stats)
    await eventRef.update({'likes': newLikes});

    // Retire le chemin complet des favoris utilisateur
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final eventPath = 'private_calendars/$_calendarId/events/$eventId';
    await userRef.update({
      'favoriteEvents': FieldValue.arrayRemove([eventPath])
    });

    if (!mounted) return;
    setState(() {});
  }
  // --- FIN CORRECTION ---

  void _showEventDetailsDialog(
    dynamic event,
    ThemeProvider themeProvider,
    Color mainBlue, {
    required double cardPadding,
    required double cardRadius,
    required double titleFontSize,
    required double cardFontSize,
    required double iconSize,
    required double buttonFontSize,
    required double buttonPadding,
    required double dialogMaxWidth,
  }) async {
    await _registerUniqueView(event.id);

    final user = FirebaseAuth.instance.currentUser;
    final participants = (event.data().containsKey('participants') &&
            event['participants'] != null)
        ? List.from(event['participants'])
        : <dynamic>[];
    final userIsParticipant = user != null &&
        participants.any((p) => p is Map && p['userId'] == user.uid);

    final likes = (event.data().containsKey('likes') && event['likes'] != null)
        ? List.from(event['likes'])
        : <dynamic>[];
    final userHasLiked =
        user != null && likes.any((l) => l is Map && l['userId'] == user.uid);

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height;
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: screenWidth * 0.05,
            vertical: screenHeight * 0.12,
          ),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(cardRadius * 1.2)),
          backgroundColor:
              themeProvider.isDarkMode ? Colors.grey[900] : Color(0xFFEAF4FF),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(cardPadding * 1.2),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            event['title'] ?? 'Sans titre',
                            style: TextStyle(
                              color: mainBlue,
                              fontWeight: FontWeight.bold,
                              fontSize: titleFontSize * 0.9,
                            ),
                            maxLines: 2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          userHasLiked ? Icons.favorite : Icons.favorite_border,
                          color: userHasLiked ? Colors.pink : Colors.grey,
                          size: iconSize * 1.1,
                        ),
                        onPressed: () async {
                          if (userHasLiked) {
                            await _handleUnlike(event.id);
                          } else {
                            await _handleLike(event.id);
                          }
                          Navigator.pop(context);
                        },
                        tooltip: userHasLiked ? "Retirer le like" : "J'aime",
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            size: iconSize * 1.1,
                            color: themeProvider.isDarkMode
                                ? Colors.white70
                                : Colors.black),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: "Fermer",
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 0.5),
                  if (event['images'] != null &&
                      event['images'] is List &&
                      (event['images'] as List).isNotEmpty)
                    _EventImageCarousel(
                        images: List<String>.from(event['images']),
                        height: cardPadding * 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: iconSize * 0.9, color: mainBlue),
                      SizedBox(width: cardPadding * 0.3),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Date : ${_formatDateFr((event['date'] as Timestamp).toDate())}",
                            style: TextStyle(fontSize: cardFontSize * 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 0.2),
                  Row(
                    children: [
                      Icon(Icons.place, size: iconSize * 0.9, color: mainBlue),
                      SizedBox(width: cardPadding * 0.3),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Lieu : ${event['location'] ?? 'Non spécifié'}",
                            style: TextStyle(fontSize: cardFontSize * 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 0.2),
                  Row(
                    children: [
                      Icon(Icons.category,
                          size: iconSize * 0.9, color: mainBlue),
                      SizedBox(width: cardPadding * 0.3),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Catégorie : ${event['category'] ?? 'Non spécifiée'}",
                            style: TextStyle(fontSize: cardFontSize * 0.95),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: cardPadding * 0.5),
                  Text(
                    "Description :",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: cardFontSize * 0.95,
                      color: themeProvider.isDarkMode
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  SizedBox(height: cardPadding * 0.1),
                  Text(
                    event['description'] ?? 'Aucune description',
                    style: TextStyle(
                      fontSize: cardFontSize * 0.95,
                      color: themeProvider.isDarkMode
                          ? Colors.white70
                          : Colors.black87,
                    ),
                  ),
                  SizedBox(height: cardPadding * 0.7),
                  SizedBox(
                    height: buttonPadding * 4.2,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(
                          userIsParticipant
                              ? Icons.cancel
                              : Icons.event_available,
                          size: iconSize * 0.9),
                      label: Text(
                          userIsParticipant ? "Se désinscrire" : "Participer",
                          style: TextStyle(fontSize: buttonFontSize * 0.95)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: mainBlue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: cardPadding, vertical: buttonPadding),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(cardRadius * 1.1)),
                      ),
                      onPressed: () async {
                        if (userIsParticipant) {
                          await _handleUnparticipate(event.id);
                        } else {
                          await _handleParticipate(event.id);
                        }
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  SizedBox(height: cardPadding * 0.5),
                  SizedBox(
                    height: buttonPadding * 4.2,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.comment, size: iconSize * 0.9),
                      label: Text("Commentaires",
                          style: TextStyle(fontSize: buttonFontSize * 0.95)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                            horizontal: cardPadding, vertical: buttonPadding),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(cardRadius * 1.1)),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showCommentsSheet(event);
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
  }

  void _showCommentsSheet(dynamic event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: CommentsOrQuestionsSheet(
            calendarId: _calendarId,
            eventId: event.id,
            isComment: true,
            eventOwnerId:
                event.data().containsKey('createdBy') ? event['createdBy'] : '',
          ),
        );
      },
    );
  }

  Widget _buildCalendarTab(
      ThemeProvider themeProvider,
      double cardPadding,
      double cardRadius,
      double titleFontSize,
      double cardFontSize,
      double iconSize,
      double buttonFontSize,
      double buttonPadding,
      double dialogMaxWidth) {
    final user = FirebaseAuth.instance.currentUser;
    final mainBlue = themeProvider.isDarkMode
        ? const Color(0xFF34AADC)
        : const Color(0xFF1976D2);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('private_calendars')
          .doc(_calendarId)
          .collection('events')
          .orderBy('date')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur Firestore : ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        _events.clear();
        for (var doc in snapshot.data!.docs) {
          DateTime eventDate = (doc['date'] as Timestamp).toDate();
          DateTime eventDay =
              DateTime(eventDate.year, eventDate.month, eventDate.day);
          if (_events[eventDay] == null) _events[eventDay] = [];
          _events[eventDay]!.add(doc);
        }
        if (_selectedDay != null) {
          DateTime normalizedSelectedDay = DateTime(
              _selectedDay!.year, _selectedDay!.month, _selectedDay!.day);
          _selectedEvents = _events[normalizedSelectedDay] ?? [];
        } else {
          _selectedEvents = [];
        }

        final eventsToShow = _selectedEvents;

        return Column(
          children: [
            Container(
              margin: EdgeInsets.symmetric(
                  horizontal: cardPadding * 1.2, vertical: cardPadding * 0.7),
              padding: EdgeInsets.symmetric(
                  horizontal: cardPadding * 1.5, vertical: cardPadding * 0.8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: themeProvider.isDarkMode
                      ? [const Color(0xFF23272F), const Color(0xFF2A2F32)]
                      : [mainBlue, const Color(0xFF64B5F6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(cardRadius * 1.2),
                boxShadow: [
                  BoxShadow(
                    color: themeProvider.isDarkMode
                        ? Colors.black26
                        : Colors.black12.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _calendarName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: titleFontSize,
                        fontFamily: 'Roboto',
                        overflow: TextOverflow.ellipsis,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  if (_isOwner)
                    Padding(
                      padding: EdgeInsets.only(left: cardPadding * 0.7),
                      child: Chip(
                        label: Text("Propriétaire",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: cardFontSize * 0.95)),
                        backgroundColor: mainBlue,
                      ),
                    ),
                ],
              ),
            ),
            TableCalendar(
              locale: 'fr_FR',
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                if (!mounted) return;
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                  DateTime normalizedSelectedDay = DateTime(
                      selectedDay.year, selectedDay.month, selectedDay.day);
                  _selectedEvents = _events[normalizedSelectedDay] ?? [];
                });
              },
              eventLoader: (day) {
                DateTime normalizedDay = DateTime(day.year, day.month, day.day);
                var eventsForDay = _events[normalizedDay] ?? [];
                // Affiche 1 point max s'il y a au moins un event, sinon aucun
                return eventsForDay.isNotEmpty ? [eventsForDay.first] : [];
              },
              calendarFormat: _calendarFormat,
              onFormatChanged: (format) {
                if (!mounted) return;
                setState(() {
                  _calendarFormat = format;
                });
              },
              calendarStyle: CalendarStyle(
                defaultDecoration: BoxDecoration(
                  color: themeProvider.isDarkMode
                      ? const Color(0xFF23272F)
                      : const Color(0xFFF5F6FA),
                  borderRadius: BorderRadius.circular(cardRadius * 0.7),
                ),
                todayDecoration: BoxDecoration(
                  color: themeProvider.isDarkMode
                      ? Colors.orange[700]
                      : const Color(0xFFEF6C00),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: mainBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                markerDecoration: BoxDecoration(
                  color: mainBlue,
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.orange : Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: cardFontSize * 0.95,
                ),
                outsideTextStyle: TextStyle(
                  color: themeProvider.isDarkMode
                      ? Colors.grey[700]
                      : Colors.grey[400],
                  fontSize: cardFontSize * 0.95,
                ),
                defaultTextStyle: TextStyle(
                  color:
                      themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  fontSize: cardFontSize,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: true,
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  color: mainBlue,
                  borderRadius: BorderRadius.circular(cardRadius * 0.7),
                ),
                formatButtonTextStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: cardFontSize,
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: mainBlue),
                rightChevronIcon: Icon(Icons.chevron_right, color: mainBlue),
                titleTextStyle: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.white : mainBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: titleFontSize * 0.9,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: themeProvider.isDarkMode
                      ? Colors.white70
                      : Colors.black54,
                  fontWeight: FontWeight.w600,
                  fontSize: cardFontSize * 0.95,
                  height: 1.3,
                ),
                weekendStyle: TextStyle(
                  color: themeProvider.isDarkMode ? Colors.orange : Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: cardFontSize * 0.95,
                  height: 1.3,
                ),
              ),
            ),
            Expanded(
              child: eventsToShow.isEmpty
                  ? Center(
                      child: Text(
                        "Aucun événement pour ce jour",
                        style: TextStyle(
                          color: themeProvider.isDarkMode
                              ? Colors.white54
                              : Colors.grey[600],
                          fontSize: cardFontSize * 1.1,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.only(bottom: cardPadding * 2),
                      itemCount: eventsToShow.length,
                      itemBuilder: (context, index) {
                        final event = eventsToShow[index];
                        final eventId = event.id;
                        final bool canDelete = user != null &&
                            (_ownerId == user.uid ||
                                _bossIds.contains(user.uid));
                        final participants =
                            (event['participants'] ?? []) as List;
                        final userIsParticipant = user != null &&
                            participants.any(
                                (p) => p is Map && p['userId'] == user.uid);

                        final likes = (event['likes'] ?? []) as List;
                        final userHasLiked = user != null &&
                            likes.any(
                                (l) => l is Map && l['userId'] == user.uid);

                        return GestureDetector(
                          onTap: () {
                            _showEventDetailsDialog(
                              event,
                              themeProvider,
                              mainBlue,
                              cardPadding: cardPadding,
                              cardRadius: cardRadius,
                              titleFontSize: titleFontSize,
                              cardFontSize: cardFontSize,
                              iconSize: iconSize,
                              buttonFontSize: buttonFontSize,
                              buttonPadding: buttonPadding,
                              dialogMaxWidth: dialogMaxWidth,
                            );
                          },
                          child: Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: cardPadding * 2,
                                vertical: cardPadding * 0.8),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(cardRadius * 1.2)),
                            elevation: 6,
                            color: themeProvider.isDarkMode
                                ? Colors.grey[850]
                                : Colors.white,
                            shadowColor: themeProvider.isDarkMode
                                ? Colors.black54
                                : Colors.blue.withOpacity(0.08),
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                  cardPadding * 1.5,
                                  cardPadding * 1.2,
                                  cardPadding * 1.5,
                                  cardPadding * 1.2),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          event['title'] ?? 'Sans titre',
                                          style: TextStyle(
                                            color: themeProvider.isDarkMode
                                                ? Color(0xFF34AADC)
                                                : mainBlue,
                                            fontSize: titleFontSize * 0.95,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'Roboto',
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                      if (canDelete)
                                        IconButton(
                                          icon: Icon(Icons.delete,
                                              color: Colors.red,
                                              size: iconSize * 1.1),
                                          onPressed: () async {
                                            final confirm =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text(
                                                    "Supprimer l'événement"),
                                                content: Text(
                                                    "Voulez-vous vraiment supprimer l'événement '${event['title']}' ?"),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: Text("Annuler",
                                                        style: TextStyle(
                                                            color: themeProvider
                                                                    .isDarkMode
                                                                ? Colors.white
                                                                : mainBlue)),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child:
                                                        const Text("Supprimer"),
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          themeProvider
                                                                  .isDarkMode
                                                              ? Colors.red[700]
                                                              : const Color(
                                                                  0xFFF44336),
                                                      foregroundColor:
                                                          Colors.white,
                                                    ),
                                                  ),
                                                ],
                                                backgroundColor: themeProvider
                                                        .isDarkMode
                                                    ? const Color(0xFF23272F)
                                                    : Colors.white,
                                              ),
                                            );
                                            if (confirm == true) {
                                              deleteEvent(eventId);
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: cardPadding * 0.5),
                                  if (event['images'] != null &&
                                      event['images'] is List &&
                                      (event['images'] as List).isNotEmpty)
                                    Row(
                                      children: [
                                        Icon(Icons.photo_library,
                                            color: mainBlue, size: iconSize),
                                        SizedBox(width: cardPadding * 0.2),
                                        Text(
                                          "${(event['images'] as List).length} image${(event['images'] as List).length > 1 ? 's' : ''} disponible${(event['images'] as List).length > 1 ? 's' : ''}",
                                          style: TextStyle(
                                            color: themeProvider.isDarkMode
                                                ? Colors.white70
                                                : Color(0xFF333333),
                                            fontSize: cardFontSize * 0.95,
                                            fontFamily: 'Roboto',
                                          ),
                                        ),
                                      ],
                                    ),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today,
                                          size: iconSize, color: mainBlue),
                                      SizedBox(width: cardPadding * 0.2),
                                      Text(
                                        _formatDateFr(
                                            (event['date'] as Timestamp)
                                                .toDate()),
                                        style: TextStyle(
                                          color: themeProvider.isDarkMode
                                              ? Colors.white70
                                              : Color(0xFF333333),
                                          fontSize: cardFontSize,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: cardPadding * 0.2),
                                  Row(
                                    children: [
                                      Icon(Icons.place,
                                          size: iconSize, color: mainBlue),
                                      SizedBox(width: cardPadding * 0.2),
                                      Text(
                                        event['location'] ?? 'Non spécifié',
                                        style: TextStyle(
                                          color: themeProvider.isDarkMode
                                              ? Colors.white70
                                              : Color(0xFF333333),
                                          fontSize: cardFontSize,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: cardPadding * 0.2),
                                  Row(
                                    children: [
                                      Icon(Icons.category,
                                          size: iconSize, color: mainBlue),
                                      SizedBox(width: cardPadding * 0.2),
                                      Text(
                                        event['category'] ?? 'Non spécifiée',
                                        style: TextStyle(
                                          color: themeProvider.isDarkMode
                                              ? Colors.white70
                                              : Color(0xFF333333),
                                          fontSize: cardFontSize,
                                          fontFamily: 'Roboto',
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: cardPadding * 0.2),
                                  Text(
                                    "Description : ${event['description'] ?? 'Aucune description'}",
                                    style: TextStyle(
                                      color: themeProvider.isDarkMode
                                          ? Colors.white70
                                          : Color(0xFF333333),
                                      fontSize: cardFontSize,
                                      fontFamily: 'Roboto',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final mainBlue = isDark ? const Color(0xFF34AADC) : const Color(0xFF1976D2);

    // Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.048;
    final double buttonFontSize = screenWidth * 0.042;
    final double buttonPadding = screenHeight * 0.012;
    final double dialogMaxWidth =
        screenWidth < 400 ? screenWidth * 0.97 : 400.0;

    Widget body = _buildCalendarTab(
      themeProvider,
      cardPadding,
      cardRadius,
      titleFontSize,
      cardFontSize,
      iconSize,
      buttonFontSize,
      buttonPadding,
      dialogMaxWidth,
    );

    return Scaffold(
      appBar: null,
      backgroundColor:
          isDark ? const Color(0xFF181C20) : const Color(0xFFF5F6FA),
      body: SafeArea(child: body),
      floatingActionButton: null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        onTap: (index) async {
          if (index == 0) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => Dialog(
                insetPadding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.05,
                  vertical: screenHeight * 0.18,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
                backgroundColor:
                    isDark ? const Color(0xFF23272F) : Colors.white,
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.06,
                    vertical: screenWidth * 0.06,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Retour à l'accueil",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: screenWidth * 0.06,
                          ),
                        ),
                      ),
                      SizedBox(height: screenWidth * 0.03),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "Voulez-vous vraiment quitter ce calendrier et revenir à l'accueil ?",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: screenWidth * 0.045,
                          ),
                        ),
                      ),
                      SizedBox(height: screenWidth * 0.06),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                "Annuler",
                                style: TextStyle(
                                  color: isDark ? Colors.white : mainBlue,
                                  fontSize: screenWidth * 0.045,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: screenWidth * 0.03),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: mainBlue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                    vertical: screenWidth * 0.025),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: Text(
                                "Oui",
                                style: TextStyle(fontSize: screenWidth * 0.045),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
            if (confirm == true) {
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/home', (route) => false);
            }
          } else if (index == 2) {
            Navigator.pushNamed(
              context,
              '/canal',
              arguments: {
                'calendarId': _calendarId,
                'ownerId': _ownerId ?? '',
                'isOwner': _isOwner,
              },
            );
          } else if (_isOwner && index == 3) {
            Navigator.pushNamed(
              context,
              '/private_calendar_settings',
              arguments: {
                'calendarId': _calendarId,
                'calendarName': _calendarName,
                'isOwner': _isOwner,
              },
            );
          } else if (!_isOwner && index == 3) {
            Navigator.pushNamed(
              context,
              '/private_profile_full',
              arguments: {
                'calendarId': _calendarId,
                'calendarName': _calendarName,
                'ownerId': _ownerId ?? '',
                'isOwner': _isOwner,
              },
            );
          } else {
            if (!mounted) return;
            setState(() => _selectedIndex = index);
          }
        },
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.lock_clock),
            label: '',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.forum),
            label: '',
          ),
          if (_isOwner)
            const BottomNavigationBarItem(
              icon: Icon(Icons.settings),
              label: '',
            ),
          if (!_isOwner)
            const BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: '',
            ),
        ],
        selectedItemColor: mainBlue,
        unselectedItemColor: isDark ? Colors.grey[400] : Colors.grey,
        type: BottomNavigationBarType.fixed,
        backgroundColor: isDark ? const Color(0xFF2A2F32) : Colors.white,
      ),
    );
  }
}

class _EventImageCarousel extends StatefulWidget {
  final List<String> images;
  final double? height;
  const _EventImageCarousel({required this.images, this.height, Key? key})
      : super(key: key);

  @override
  State<_EventImageCarousel> createState() => _EventImageCarouselState();
}

class _EventImageCarouselState extends State<_EventImageCarousel> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double height = widget.height ?? screenWidth * 0.45;
    if (widget.images.isEmpty) return SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: height,
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
                    height: height,
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(
                      width: double.infinity,
                      height: height,
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

class CommentsOrQuestionsSheet extends StatefulWidget {
  final String calendarId;
  final String eventId;
  final bool isComment;
  final String eventOwnerId;
  const CommentsOrQuestionsSheet({
    required this.calendarId,
    required this.eventId,
    required this.isComment,
    required this.eventOwnerId,
    Key? key,
  }) : super(key: key);

  @override
  State<CommentsOrQuestionsSheet> createState() =>
      _CommentsOrQuestionsSheetState();
}

class _CommentsOrQuestionsSheetState extends State<CommentsOrQuestionsSheet> {
  final TextEditingController _controller = TextEditingController();
  String? _userRole;
  String? _replyToCommentId;
  final TextEditingController _replyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (!mounted) return;
    setState(() {
      _userRole = userDoc['role'];
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _addEntry() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final pseudo = userDoc['pseudo'] ?? 'Utilisateur';
    final role = userDoc['role'] ?? '';
    final subscriptionStatus = userDoc['subscriptionStatus'] ?? '';
    String? certification;
    if (role == 'premium' && subscriptionStatus == 'active') {
      certification = 'premium';
    } else if (role == 'boss') {
      certification = 'boss';
    }

    final collection = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .doc(widget.eventId)
        .collection('comments');
    await collection.add({
      'text': text,
      'userId': user.uid,
      'userName': pseudo,
      'createdAt': FieldValue.serverTimestamp(),
      'likes': [],
      'certification': certification,
      'isPinned': false,
    });
    if (!mounted) return;
    setState(() {
      _controller.clear();
    });
  }

  Future<void> _addReply(String commentId) async {
    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final pseudo = userDoc['pseudo'] ?? 'Utilisateur';
    final role = userDoc['role'] ?? '';
    final subscriptionStatus = userDoc['subscriptionStatus'] ?? '';
    String? certification;
    if (role == 'premium' && subscriptionStatus == 'active') {
      certification = 'premium';
    } else if (role == 'boss') {
      certification = 'boss';
    }

    final repliesCollection = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .doc(widget.eventId)
        .collection('comments')
        .doc(commentId)
        .collection('replies');
    await repliesCollection.add({
      'text': text,
      'userId': user.uid,
      'userName': pseudo,
      'createdAt': FieldValue.serverTimestamp(),
      'certification': certification,
    });
    if (!mounted) return;
    setState(() {
      _replyController.clear();
      _replyToCommentId = null;
    });
  }

  Future<void> _deleteEntry(String docId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_userRole == 'boss' || user.uid == widget.eventOwnerId) {
      await FirebaseFirestore.instance
          .collection('private_calendars')
          .doc(widget.calendarId)
          .collection('events')
          .doc(widget.eventId)
          .collection('comments')
          .doc(docId)
          .delete();
    } else {
      final doc = await FirebaseFirestore.instance
          .collection('private_calendars')
          .doc(widget.calendarId)
          .collection('events')
          .doc(widget.eventId)
          .collection('comments')
          .doc(docId)
          .get();
      if (doc.exists && doc['userId'] == user.uid) {
        await doc.reference.delete();
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleLike(String docId, List likes) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final collection = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .doc(widget.eventId)
        .collection('comments');
    final alreadyLiked = likes.contains(user.uid);
    if (alreadyLiked) {
      await collection.doc(docId).update({
        'likes': FieldValue.arrayRemove([user.uid])
      });
    } else {
      await collection.doc(docId).update({
        'likes': FieldValue.arrayUnion([user.uid])
      });
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _togglePin(String docId, bool isPinned) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_userRole == 'boss' || user.uid == widget.eventOwnerId) {
      final commentRef = FirebaseFirestore.instance
          .collection('private_calendars')
          .doc(widget.calendarId)
          .collection('events')
          .doc(widget.eventId)
          .collection('comments')
          .doc(docId);
      await commentRef.update({'isPinned': !isPinned});
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double cardFontSize = screenWidth * 0.038;
    final double buttonFontSize = screenWidth * 0.042;
    final double buttonPadding = screenHeight * 0.012;

    final user = FirebaseAuth.instance.currentUser;
    final isConnected = user != null;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final collection = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .doc(widget.eventId)
        .collection('comments')
        .orderBy('createdAt', descending: true);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
            top: cardPadding * 1.2,
            left: cardPadding,
            right: cardPadding,
            bottom: cardPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              margin: EdgeInsets.only(bottom: cardPadding * 0.5),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(cardRadius),
              ),
            ),
            Text(
              "Commentaires",
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: cardFontSize * 1.3),
            ),
            SizedBox(height: cardPadding * 0.7),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: collection.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text("Erreur : ${snapshot.error}"));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return const Center(child: Text("Aucun commentaire"));
                  }
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final docId = docs[index].id;
                      final isMine = isConnected && user!.uid == data['userId'];
                      final isPinned = data['isPinned'] ?? false;
                      final certification = data['certification'];
                      final bgColor = themeProvider.isDarkMode
                          ? const Color(0xFF23272F)
                          : Colors.grey[100];
                      final textColor = themeProvider.isDarkMode
                          ? Colors.white
                          : Colors.black87;
                      final canPinOrDelete = (_userRole == 'boss' ||
                          (user != null && user.uid == widget.eventOwnerId));
                      final likes = (data['likes'] ?? []) as List;
                      final alreadyLiked =
                          user != null && likes.contains(user.uid);

                      return Container(
                        margin: EdgeInsets.symmetric(
                            vertical: cardPadding * 0.5,
                            horizontal: cardPadding * 0.2),
                        padding: EdgeInsets.all(cardPadding),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(cardRadius * 1.1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  data['userName'] ?? 'Utilisateur',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: cardFontSize * 1.1,
                                      color: textColor),
                                ),
                                if (certification == 'premium')
                                  Padding(
                                    padding: EdgeInsets.only(
                                        left: cardPadding * 0.2),
                                    child: Icon(Icons.verified,
                                        color: Colors.amber,
                                        size: cardFontSize * 1.2),
                                  ),
                                if (certification == 'boss')
                                  Padding(
                                    padding: EdgeInsets.only(
                                        left: cardPadding * 0.2),
                                    child: Icon(Icons.verified,
                                        color: Colors.blue,
                                        size: cardFontSize * 1.2),
                                  ),
                                if (isPinned)
                                  Padding(
                                    padding: EdgeInsets.only(
                                        left: cardPadding * 0.2),
                                    child: Icon(Icons.push_pin,
                                        color: Colors.blue,
                                        size: cardFontSize * 1.2),
                                  ),
                                Spacer(),
                                if (data['createdAt'] != null)
                                  Text(
                                    DateFormat('dd/MM HH:mm').format(
                                        (data['createdAt'] as Timestamp)
                                            .toDate()),
                                    style: TextStyle(
                                        fontSize: cardFontSize * 0.85,
                                        color: Colors.grey),
                                  ),
                              ],
                            ),
                            SizedBox(height: cardPadding * 0.2),
                            Text(data['text'] ?? '',
                                style: TextStyle(
                                    fontSize: cardFontSize, color: textColor)),
                            SizedBox(height: cardPadding * 0.5),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: isConnected
                                      ? () => _toggleLike(docId, likes)
                                      : null,
                                  child: Icon(
                                    alreadyLiked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: cardFontSize * 1.2,
                                    color: alreadyLiked
                                        ? Colors.pink
                                        : Colors.grey[600],
                                  ),
                                ),
                                SizedBox(width: cardPadding * 0.2),
                                Text('${likes.length}',
                                    style: TextStyle(
                                        fontSize: cardFontSize * 0.9)),
                                SizedBox(width: cardPadding * 0.5),
                                if (canPinOrDelete)
                                  GestureDetector(
                                    onTap: () => _togglePin(docId, isPinned),
                                    child: Icon(Icons.push_pin,
                                        size: cardFontSize * 1.2,
                                        color: isPinned
                                            ? Colors.blue
                                            : Colors.grey[600]),
                                  ),
                                SizedBox(width: cardPadding * 0.5),
                                if (canPinOrDelete || isMine)
                                  GestureDetector(
                                    onTap: () async {
                                      await _deleteEntry(docId);
                                    },
                                    child: Icon(Icons.delete,
                                        color: Colors.red,
                                        size: cardFontSize * 1.2),
                                  ),
                              ],
                            ),
                            SizedBox(height: cardPadding * 0.3),
                            GestureDetector(
                              onTap: isConnected
                                  ? () {
                                      setState(() {
                                        _replyToCommentId = docId;
                                      });
                                    }
                                  : null,
                              child: Text(
                                "Répondre...",
                                style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                    fontSize: cardFontSize * 0.95),
                              ),
                            ),
                            if (_replyToCommentId == docId)
                              Padding(
                                padding:
                                    EdgeInsets.only(top: cardPadding * 0.5),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: _replyController,
                                        decoration: InputDecoration(
                                          hintText: "Votre réponse...",
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius),
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: cardPadding,
                                              vertical: cardPadding * 0.5),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: cardPadding * 0.5),
                                    ElevatedButton(
                                      onPressed: () async {
                                        await _addReply(docId);
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                cardRadius)),
                                        padding: EdgeInsets.symmetric(
                                            horizontal: cardPadding * 1.2,
                                            vertical: cardPadding * 0.7),
                                      ),
                                      child: Text("Envoyer",
                                          style: TextStyle(
                                              fontSize: buttonFontSize * 0.9)),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close,
                                          size: cardFontSize * 1.1),
                                      onPressed: () {
                                        setState(() {
                                          _replyToCommentId = null;
                                          _replyController.clear();
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            // Affichage des réponses
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance
                                  .collection('private_calendars')
                                  .doc(widget.calendarId)
                                  .collection('events')
                                  .doc(widget.eventId)
                                  .collection('comments')
                                  .doc(docId)
                                  .collection('replies')
                                  .orderBy('createdAt', descending: false)
                                  .snapshots(),
                              builder: (context, replySnapshot) {
                                if (!replySnapshot.hasData ||
                                    replySnapshot.data!.docs.isEmpty) {
                                  return SizedBox.shrink();
                                }
                                return Padding(
                                  padding:
                                      EdgeInsets.only(top: cardPadding * 0.5),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: replySnapshot.data!.docs
                                        .map((replyDoc) {
                                      final replyData = replyDoc.data()
                                          as Map<String, dynamic>;
                                      final replyCertification =
                                          replyData['certification'];
                                      return Container(
                                        margin: EdgeInsets.symmetric(
                                            vertical: cardPadding * 0.3,
                                            horizontal: cardPadding * 0.7),
                                        padding:
                                            EdgeInsets.all(cardPadding * 0.7),
                                        decoration: BoxDecoration(
                                          color: themeProvider.isDarkMode
                                              ? Colors.grey[800]
                                              : Colors.grey[200],
                                          borderRadius:
                                              BorderRadius.circular(cardRadius),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              replyData['userName'] ??
                                                  'Utilisateur',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: cardFontSize * 0.95,
                                                  color: textColor),
                                            ),
                                            if (replyCertification == 'premium')
                                              Padding(
                                                padding: EdgeInsets.only(
                                                    left: cardPadding * 0.2),
                                                child: Icon(Icons.verified,
                                                    color: Colors.amber,
                                                    size: cardFontSize),
                                              ),
                                            if (replyCertification == 'boss')
                                              Padding(
                                                padding: EdgeInsets.only(
                                                    left: cardPadding * 0.2),
                                                child: Icon(Icons.verified,
                                                    color: Colors.blue,
                                                    size: cardFontSize),
                                              ),
                                            SizedBox(width: cardPadding * 0.5),
                                            Expanded(
                                              child: Text(
                                                replyData['text'] ?? '',
                                                style: TextStyle(
                                                    fontSize:
                                                        cardFontSize * 0.95,
                                                    color: textColor),
                                              ),
                                            ),
                                            if (replyData['createdAt'] != null)
                                              Padding(
                                                padding: EdgeInsets.only(
                                                    left: cardPadding * 0.5),
                                                child: Text(
                                                  DateFormat('dd/MM HH:mm')
                                                      .format((replyData[
                                                                  'createdAt']
                                                              as Timestamp)
                                                          .toDate()),
                                                  style: TextStyle(
                                                      fontSize:
                                                          cardFontSize * 0.7,
                                                      color: Colors.grey),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: isConnected,
                    decoration: InputDecoration(
                      hintText: isConnected
                          ? "Ajouter un commentaire..."
                          : "Connectez-vous pour écrire",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(cardRadius * 1.2),
                        borderSide: BorderSide(color: Colors.grey[400]!),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: cardPadding * 1.2,
                          vertical: cardPadding * 0.7),
                    ),
                  ),
                ),
                SizedBox(width: cardPadding * 0.5),
                ElevatedButton(
                  onPressed: isConnected ? _addEntry : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(cardRadius)),
                    padding: EdgeInsets.symmetric(
                        horizontal: cardPadding * 1.2,
                        vertical: cardPadding * 0.7),
                  ),
                  child: Text("Envoyer",
                      style: TextStyle(fontSize: buttonFontSize * 0.9)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
