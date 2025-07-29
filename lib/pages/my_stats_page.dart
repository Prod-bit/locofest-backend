import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:auto_size_text/auto_size_text.dart';

class MyStatsPage extends StatefulWidget {
  const MyStatsPage({Key? key}) : super(key: key);

  @override
  State<MyStatsPage> createState() => _MyStatsPageState();
}

class _MyStatsPageState extends State<MyStatsPage>
    with SingleTickerProviderStateMixin {
  int _likesOnEvents = 0;
  int _sharesOnEvents = 0;
  int _uniqueViews = 0;
  int _totalParticipations = 0;
  bool _loading = true;
  String? _pseudo;
  String? _role;

  int _selectedPeriod = 1; // 0: aujourd'hui, 1: 7j, 2: 30j

  late TabController _tabController;
  List<Map<String, dynamic>> _finishedEvents = [];
  List<String> _cities = [];
  String? _selectedCity;
  Map<String, double> _eventAverages = {};
  Map<String, int> _eventRatingsCount = {};
  Map<String, List<Map<String, dynamic>>> _eventFeedbacks = {};

  List<Map<String, dynamic>> _allMyEvents = [];
  String _eventSort = 'alpha'; // alpha, likes, vues, partages, participations
  String? _eventFilterCity;
  String? _eventFilterCategory;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchStats();
    _fetchFinishedEvents();
    _fetchAllMyEvents();
  }

  Future<void> _fetchStats() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        setState(() {
          _loading = false;
        });
        return;
      }
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final pseudo = userDoc['pseudo'] ?? '';
      final role = userDoc['role'] ?? '';

      final eventsQuery = await FirebaseFirestore.instance
          .collection('events')
          .where('creatorId', isEqualTo: user.uid)
          .get();
      final myEventIds = eventsQuery.docs.map((doc) => doc.id).toList();

      int likesOnEvents = 0;
      int sharesOnEvents = 0;
      int uniqueViews = 0;
      int totalParticipations = 0;

      DateTime now = DateTime.now();
      DateTime minDate;
      if (_selectedPeriod == 0) {
        minDate = DateTime(now.year, now.month, now.day);
      } else if (_selectedPeriod == 1) {
        minDate = now.subtract(Duration(days: 6));
      } else {
        minDate = now.subtract(Duration(days: 29));
      }

      for (final doc in eventsQuery.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final List likes = data.containsKey('likes') && data['likes'] is List
            ? data['likes'] as List
            : <dynamic>[];
        likesOnEvents += likes.where((like) {
          if (like is Map && like.containsKey('createdAt')) {
            DateTime date = (like['createdAt'] as Timestamp).toDate();
            return !date.isBefore(minDate);
          }
          return _selectedPeriod == 0 ? false : true;
        }).length;
      }

      if (myEventIds.isNotEmpty) {
        for (var i = 0; i < myEventIds.length; i += 10) {
          final batchIds = myEventIds.sublist(
              i, (i + 10 > myEventIds.length) ? myEventIds.length : i + 10);
          final sharesQuery = await FirebaseFirestore.instance
              .collection('event_shares')
              .where('eventId', whereIn: batchIds)
              .get();
          sharesOnEvents += sharesQuery.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data.containsKey('timestamp')) {
              DateTime date = (data['timestamp'] as Timestamp).toDate();
              return !date.isBefore(minDate);
            }
            return _selectedPeriod == 0 ? false : true;
          }).length;
        }
      }

      if (myEventIds.isNotEmpty) {
        for (var i = 0; i < myEventIds.length; i += 10) {
          final batchIds = myEventIds.sublist(
              i, (i + 10 > myEventIds.length) ? myEventIds.length : i + 10);
          final viewsQuery = await FirebaseFirestore.instance
              .collection('event_views')
              .where('eventId', whereIn: batchIds)
              .get();
          final userIds = <String>{};
          for (final doc in viewsQuery.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data.containsKey('userId')) {
              if (data.containsKey('timestamp')) {
                DateTime date = (data['timestamp'] as Timestamp).toDate();
                if (!date.isBefore(minDate)) {
                  userIds.add(data['userId']);
                }
              } else if (_selectedPeriod != 0) {
                userIds.add(data['userId']);
              }
            }
          }
          uniqueViews += userIds.length;
        }
      }

      if (myEventIds.isNotEmpty) {
        for (var i = 0; i < myEventIds.length; i += 10) {
          final batchIds = myEventIds.sublist(
              i, (i + 10 > myEventIds.length) ? myEventIds.length : i + 10);
          final partQuery = await FirebaseFirestore.instance
              .collection('event_participations')
              .where('eventId', whereIn: batchIds)
              .get();
          totalParticipations += partQuery.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            if (data.containsKey('timestamp')) {
              DateTime date = (data['timestamp'] as Timestamp).toDate();
              return !date.isBefore(minDate);
            }
            return _selectedPeriod == 0 ? false : true;
          }).length;
        }
      }

      setState(() {
        _pseudo = pseudo;
        _role = role;
        _likesOnEvents = likesOnEvents;
        _sharesOnEvents = sharesOnEvents;
        _uniqueViews = uniqueViews;
        _totalParticipations = totalParticipations;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur lors du chargement des statistiques : $e")));
    }
  }

  Future<void> _fetchFinishedEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    DateTime now = DateTime.now();
    DateTime minDate = now.subtract(const Duration(days: 30));
    final eventsQuery = await FirebaseFirestore.instance
        .collection('events')
        .where('creatorId', isEqualTo: user.uid)
        .get();

    List<Map<String, dynamic>> finished = [];
    Set<String> cities = {};
    for (final doc in eventsQuery.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['date'] != null) {
        DateTime eventDate = (data['date'] as Timestamp).toDate();
        if (now.isAfter(eventDate.add(const Duration(hours: 4))) &&
            eventDate.isAfter(minDate)) {
          finished.add({...data, 'id': doc.id});
          if (data['city'] != null && data['city'].toString().isNotEmpty) {
            cities.add(data['city']);
          }
        }
      }
    }
    setState(() {
      _finishedEvents = finished;
      _cities = cities.toList()..sort();
      _selectedCity = null;
    });
    await _fetchRatingsAndFeedbacks();
  }

  Future<void> _fetchRatingsAndFeedbacks() async {
    Map<String, double> averages = {};
    Map<String, int> counts = {};
    Map<String, List<Map<String, dynamic>>> feedbacks = {};
    for (final event in _finishedEvents) {
      final eventId = event['id'];
      final ratingsQuery = await FirebaseFirestore.instance
          .collection('event_ratings')
          .where('eventId', isEqualTo: eventId)
          .get();
      if (ratingsQuery.docs.isNotEmpty) {
        double sum = 0;
        for (final doc in ratingsQuery.docs) {
          sum += (doc['rating'] ?? 0).toDouble();
        }
        averages[eventId] = sum / ratingsQuery.docs.length;
        counts[eventId] = ratingsQuery.docs.length;
      } else {
        averages[eventId] = 0;
        counts[eventId] = 0;
      }
      final feedbackQuery = await FirebaseFirestore.instance
          .collection('event_feedbacks')
          .where('eventId', isEqualTo: eventId)
          .get();
      feedbacks[eventId] = feedbackQuery.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
    }
    setState(() {
      _eventAverages = averages;
      _eventRatingsCount = counts;
      _eventFeedbacks = feedbacks;
    });
  }

  Future<void> _fetchAllMyEvents() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final eventsQuery = await FirebaseFirestore.instance
        .collection('events')
        .where('creatorId', isEqualTo: user.uid)
        .get();
    List<Map<String, dynamic>> allEvents = [];
    for (final doc in eventsQuery.docs) {
      final data = doc.data() as Map<String, dynamic>;
      allEvents.add({...data, 'id': doc.id});
    }
    setState(() {
      _allMyEvents = allEvents;
    });
  }

  Future<int> getLikesCount(String eventId) async {
    final likes = await FirebaseFirestore.instance
        .collection('event_likes')
        .where('eventId', isEqualTo: eventId)
        .get();
    return likes.docs.length;
  }

  Future<int> getSharesCount(String eventId) async {
    final shares = await FirebaseFirestore.instance
        .collection('event_shares')
        .where('eventId', isEqualTo: eventId)
        .get();
    return shares.docs.length;
  }

  Future<int> getViewsCount(String eventId) async {
    final views = await FirebaseFirestore.instance
        .collection('event_views')
        .where('eventId', isEqualTo: eventId)
        .get();
    return views.docs.length;
  }

  Future<int> getParticipationsCount(String eventId) async {
    final parts = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: eventId)
        .get();
    return parts.docs.length;
  }

  Color get _mainColor {
    switch (_role) {
      case 'admin':
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
    double? cardFontSize,
    double? valueFontSize,
    double? iconSize,
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
            vertical: cardFontSize ?? 18, horizontal: cardFontSize ?? 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.18),
              child: Icon(icon, color: color, size: iconSize ?? 28),
              radius: iconSize != null ? iconSize! * 0.93 : 26,
            ),
            SizedBox(width: cardFontSize ?? 18),
            Expanded(
              child: Center(
                child: AutoSizeText(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : color,
                    fontSize: cardFontSize ?? 16,
                  ),
                  maxLines: 3,
                  minFontSize: 13,
                  maxFontSize: 18,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
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
                  fontSize: valueFontSize ?? 26,
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

  Widget _periodSelector() {
    final labels = ["Aujourd'hui", "7 jours", "30 jours"];
    final screenWidth = MediaQuery.of(context).size.width;
    final double chipFontSize = screenWidth * 0.032;
    final double chipPadding = screenWidth * 0.012;
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

  Widget _buildRatingsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainColor = _mainColor;
    final filteredEvents = _selectedCity == null
        ? _finishedEvents
        : _finishedEvents.where((e) => e['city'] == _selectedCity).toList();

    final double dialogWidth = MediaQuery.of(context).size.width * 0.96;
    final double dialogMaxHeight = MediaQuery.of(context).size.height * 0.8;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_cities.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 260),
              child: DropdownButtonFormField<String>(
                isDense: true,
                style: TextStyle(fontSize: 13),
                value: _selectedCity,
                hint: Text(
                  "Toutes les villes",
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(
                      "Toutes les villes",
                      style: TextStyle(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  ..._cities.map((city) => DropdownMenuItem(
                        value: city,
                        child: Text(
                          city,
                          style: TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      )),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedCity = val;
                  });
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.grey[900] : Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ),
        if (filteredEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(
                "Aucun événement terminé sur les 30 derniers jours.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ...filteredEvents.map((event) {
          final avg = _eventAverages[event['id']] ?? 0.0;
          final count = _eventRatingsCount[event['id']] ?? 0;
          final feedbacks = _eventFeedbacks[event['id']] ?? [];
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            color: isDark ? const Color(0xFF23272F) : Colors.white,
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event, color: mainColor, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AutoSizeText(
                          event['title'] ?? 'Sans titre',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: isDark ? Colors.white : mainColor,
                          ),
                          maxLines: 2,
                          minFontSize: 12,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (event['city'] != null)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                isDark ? Colors.blueGrey[900] : Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark ? Colors.blue[200]! : Colors.blue,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.location_on,
                                  color:
                                      isDark ? Colors.blue[200] : Colors.blue,
                                  size: 15),
                              const SizedBox(width: 3),
                              AutoSizeText(
                                event['city'],
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.blue[100]
                                      : Colors.blue[900],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                minFontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, color: mainColor, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AutoSizeText(
                            _formatDateFr(
                                (event['date'] as Timestamp).toDate()),
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.grey[800],
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            minFontSize: 8,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber[700], size: 20),
                      const SizedBox(width: 4),
                      AutoSizeText(
                        avg > 0
                            ? "${avg.toStringAsFixed(2)} / 5"
                            : "Pas de note",
                        style: TextStyle(
                          color: Colors.amber[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        minFontSize: 10,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (count > 0)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: AutoSizeText(
                            "($count note${count > 1 ? 's' : ''})",
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey[700],
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            minFontSize: 10,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  if (feedbacks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          icon: Icon(Icons.comment, color: mainColor, size: 18),
                          label: Text(
                            "Avis (${feedbacks.length})",
                            style: TextStyle(
                              color: mainColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                double avisHeight = (feedbacks.length * 80.0)
                                    .clamp(80.0, dialogMaxHeight - 120);
                                return Dialog(
                                  insetPadding: EdgeInsets.symmetric(
                                    horizontal:
                                        MediaQuery.of(context).size.width *
                                            0.04,
                                    vertical: 24,
                                  ),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18)),
                                  backgroundColor: isDark
                                      ? const Color(0xFF23272F)
                                      : Colors.white,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: dialogWidth,
                                      maxHeight: dialogMaxHeight,
                                      minWidth: 0,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.comment,
                                                  color: mainColor, size: 24),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: AutoSizeText(
                                                  "Avis",
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 20,
                                                    color: isDark
                                                        ? Colors.white
                                                        : mainColor,
                                                  ),
                                                  maxLines: 1,
                                                  minFontSize: 14,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              TextButton.icon(
                                                icon: const Icon(Icons.close),
                                                label: const Text("Fermer"),
                                                style: TextButton.styleFrom(
                                                  foregroundColor:
                                                      Colors.grey[600],
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                                ),
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          ConstrainedBox(
                                            constraints: BoxConstraints(
                                              minHeight: 80,
                                              maxHeight: avisHeight,
                                            ),
                                            child: ListView.separated(
                                              shrinkWrap: true,
                                              itemCount: feedbacks.length,
                                              separatorBuilder: (_, __) =>
                                                  Divider(
                                                      color: isDark
                                                          ? Colors.white12
                                                          : Colors.grey[300]),
                                              itemBuilder: (context, i) {
                                                final fb = feedbacks[i];
                                                return ListTile(
                                                  leading: Icon(Icons.person,
                                                      color: mainColor),
                                                  title: AutoSizeText(
                                                    fb['feedback'] ?? '',
                                                    style: TextStyle(
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.black87,
                                                      fontSize: 16,
                                                    ),
                                                    maxLines: 5,
                                                    minFontSize: 11,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  subtitle: fb['createdAt'] !=
                                                          null
                                                      ? AutoSizeText(
                                                          _formatDateFr((fb[
                                                                      'createdAt']
                                                                  as Timestamp)
                                                              .toDate()),
                                                          style: TextStyle(
                                                            color: isDark
                                                                ? Colors.white54
                                                                : Colors
                                                                    .grey[600],
                                                            fontSize: 13,
                                                          ),
                                                          maxLines: 1,
                                                          minFontSize: 10,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        )
                                                      : null,
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
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildEventsFilterBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainColor = _mainColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        children: [
          ElevatedButton.icon(
            icon: Icon(Icons.filter_list, color: Colors.white),
            label: Text("Filtrer", style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: mainColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 2,
            ),
            onPressed: () async {
              await showModalBottomSheet(
                context: context,
                shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(18))),
                backgroundColor: isDark ? Color(0xFF23272F) : Colors.white,
                builder: (context) {
                  final List<Map<String, dynamic>> filterOptions = [
                    {
                      'key': 'alpha',
                      'label': 'A-Z',
                      'icon': Icons.sort_by_alpha,
                    },
                    {
                      'key': 'likes',
                      'label': 'Plus liké',
                      'icon': Icons.favorite,
                    },
                    {
                      'key': 'vues',
                      'label': 'Plus vu',
                      'icon': Icons.visibility,
                    },
                    {
                      'key': 'partages',
                      'label': 'Plus partagé',
                      'icon': Icons.share,
                    },
                    {
                      'key': 'participations',
                      'label': 'Plus participé',
                      'icon': Icons.event_available,
                    },
                  ];
                  final cities = _allMyEvents
                      .map((e) => e['city']?.toString() ?? '')
                      .where((c) => c.isNotEmpty)
                      .toSet()
                      .toList();
                  final categories = _allMyEvents
                      .map((e) => e['category']?.toString() ?? '')
                      .where((c) => c.isNotEmpty)
                      .toSet()
                      .toList();
                  return StatefulBuilder(
                    builder: (context, setModalState) {
                      return SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 40,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[400],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              SizedBox(height: 18),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: AutoSizeText(
                                  "Trier par",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                    color: mainColor,
                                  ),
                                  maxLines: 1,
                                  minFontSize: 8,
                                  overflow: TextOverflow.visible,
                                ),
                              ),
                              SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                children: filterOptions.map((opt) {
                                  final selected = _eventSort == opt['key'];
                                  return ChoiceChip(
                                    avatar: selected
                                        ? null
                                        : Icon(opt['icon'],
                                            color: mainColor, size: 20),
                                    label: Text(
                                      opt['label'],
                                      style: TextStyle(
                                        color:
                                            selected ? Colors.white : mainColor,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    selected: selected,
                                    selectedColor: mainColor,
                                    backgroundColor: isDark
                                        ? Colors.grey[900]
                                        : Colors.grey[200],
                                    onSelected: (_) {
                                      setModalState(() =>
                                          _eventSort = opt['key'] as String);
                                    },
                                    elevation: selected ? 4 : 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                  );
                                }).toList(),
                              ),
                              SizedBox(height: 18),
                              if (cities.isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: AutoSizeText(
                                        "Ville",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                          color: mainColor,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 8,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: 260),
                                      child: DropdownButtonFormField<String>(
                                        isDense: true,
                                        style: TextStyle(fontSize: 13),
                                        value: _eventFilterCity,
                                        hint: Text(
                                          "Toutes les villes",
                                          style: TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: null,
                                            child: Text(
                                              "Toutes les villes",
                                              style: TextStyle(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          ...cities
                                              .map((city) => DropdownMenuItem(
                                                    value: city,
                                                    child: Text(
                                                      city,
                                                      style: TextStyle(
                                                          fontSize: 13),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  )),
                                        ],
                                        onChanged: (val) {
                                          setModalState(
                                              () => _eventFilterCity = val);
                                        },
                                        decoration: InputDecoration(
                                          isDense: true,
                                          filled: true,
                                          fillColor: isDark
                                              ? Colors.grey[900]
                                              : Colors.grey[100],
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (categories.isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(height: 18),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: AutoSizeText(
                                        "Catégorie",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 17,
                                          color: mainColor,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 8,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                    SizedBox(height: 10),
                                    ConstrainedBox(
                                      constraints:
                                          BoxConstraints(maxWidth: 260),
                                      child: DropdownButtonFormField<String>(
                                        isDense: true,
                                        style: TextStyle(fontSize: 13),
                                        value: _eventFilterCategory,
                                        hint: Text(
                                          "Toutes les catégories",
                                          style: TextStyle(fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                        items: [
                                          DropdownMenuItem(
                                            value: null,
                                            child: Text(
                                              "Toutes les catégories",
                                              style: TextStyle(fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ),
                                          ...categories
                                              .map((cat) => DropdownMenuItem(
                                                    value: cat,
                                                    child: Text(
                                                      cat,
                                                      style: TextStyle(
                                                          fontSize: 13),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      maxLines: 1,
                                                    ),
                                                  )),
                                        ],
                                        onChanged: (val) {
                                          setModalState(
                                              () => _eventFilterCategory = val);
                                        },
                                        decoration: InputDecoration(
                                          isDense: true,
                                          filled: true,
                                          fillColor: isDark
                                              ? Colors.grey[900]
                                              : Colors.grey[100],
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              SizedBox(height: 24),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: TextButton(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: AutoSizeText("Réinitialiser",
                                            maxLines: 1,
                                            minFontSize: 8,
                                            overflow: TextOverflow.visible),
                                      ),
                                      onPressed: () {
                                        setModalState(() {
                                          _eventSort = 'alpha';
                                          _eventFilterCity = null;
                                          _eventFilterCategory = null;
                                        });
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: AutoSizeText("Appliquer",
                                            maxLines: 1,
                                            minFontSize: 8,
                                            overflow: TextOverflow.visible),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: mainColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                      onPressed: () {
                                        setState(() {});
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEventsTab() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainColor = _mainColor;
    List<Map<String, dynamic>> events = List.from(_allMyEvents);

    if (_eventFilterCity != null && _eventFilterCity!.isNotEmpty) {
      events = events.where((e) => e['city'] == _eventFilterCity).toList();
    }
    if (_eventFilterCategory != null && _eventFilterCategory!.isNotEmpty) {
      events =
          events.where((e) => e['category'] == _eventFilterCategory).toList();
    }

    for (var event in events) {
      event['likes'] =
          (event['likes'] is List) ? (event['likes'] as List).length : 0;
      event['shares'] = event['shares'] ?? 0;
      event['views'] = event['views'] ?? 0;
      event['participations'] = event['participations'] ?? 0;
    }

    switch (_eventSort) {
      case 'likes':
        events.sort((a, b) => (b['likes'] as int).compareTo(a['likes'] as int));
        break;
      case 'vues':
        events.sort((a, b) => (b['views'] as int).compareTo(a['views'] as int));
        break;
      case 'partages':
        events
            .sort((a, b) => (b['shares'] as int).compareTo(a['shares'] as int));
        break;
      case 'participations':
        events.sort((a, b) =>
            (b['participations'] as int).compareTo(a['participations'] as int));
        break;
      default:
        events.sort((a, b) => (a['title'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['title'] ?? '').toString().toLowerCase()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEventsFilterBar(),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(
                "Aucun événement trouvé.",
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ...events.map((event) => Card(
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              color: isDark ? const Color(0xFF23272F) : Colors.white,
              elevation: 2,
              child: ListTile(
                leading: Icon(Icons.event, color: mainColor),
                title: AutoSizeText(event['title'] ?? 'Sans titre',
                    style: TextStyle(
                        color: isDark ? Colors.white : mainColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 17),
                    maxLines: 2,
                    minFontSize: 12,
                    overflow: TextOverflow.ellipsis),
                subtitle: AutoSizeText(
                  event['city'] != null ? event['city'] : '',
                  style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey[700],
                      fontSize: 14),
                  maxLines: 1,
                  minFontSize: 10,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(Icons.bar_chart, color: mainColor),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      return Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18)),
                        backgroundColor:
                            isDark ? const Color(0xFF23272F) : Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.event, color: mainColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: AutoSizeText(
                                      event['title'] ?? 'Sans titre',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: isDark
                                              ? Colors.white
                                              : mainColor),
                                      maxLines: 2,
                                      minFontSize: 12,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (event['city'] != null)
                                Row(
                                  children: [
                                    Icon(Icons.location_on,
                                        color: mainColor, size: 18),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: AutoSizeText(
                                        event['city'],
                                        style: TextStyle(
                                            color: mainColor,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14),
                                        maxLines: 1,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 10),
                              if (event['date'] != null)
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        color: mainColor, size: 16),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: AutoSizeText(
                                        _formatDateFr(
                                            (event['date'] as Timestamp)
                                                .toDate()),
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.grey[800],
                                          fontSize: 15,
                                        ),
                                        maxLines: 1,
                                        minFontSize: 10,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              const SizedBox(height: 14),
                              FutureBuilder<int>(
                                future: getLikesCount(event['id']),
                                builder: (context, snapshot) {
                                  final likes = snapshot.data ?? 0;
                                  return Row(
                                    children: [
                                      Icon(Icons.favorite,
                                          color: Colors.pink[400], size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: AutoSizeText(
                                          "Likes : $likes",
                                          style: TextStyle(
                                              color: Colors.pink[400],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                          maxLines: 1,
                                          minFontSize: 10,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<int>(
                                future: getSharesCount(event['id']),
                                builder: (context, snapshot) {
                                  final shares = snapshot.data ?? 0;
                                  return Row(
                                    children: [
                                      Icon(Icons.share,
                                          color: Colors.blue[700], size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: AutoSizeText(
                                          "Partages : $shares",
                                          style: TextStyle(
                                              color: Colors.blue[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                          maxLines: 1,
                                          minFontSize: 10,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<int>(
                                future: getViewsCount(event['id']),
                                builder: (context, snapshot) {
                                  final views = snapshot.data ?? 0;
                                  return Row(
                                    children: [
                                      Icon(Icons.visibility,
                                          color: Colors.deepPurple, size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: AutoSizeText(
                                          "Vues : $views",
                                          style: TextStyle(
                                              color: Colors.deepPurple,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                          maxLines: 1,
                                          minFontSize: 10,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<int>(
                                future: getParticipationsCount(event['id']),
                                builder: (context, snapshot) {
                                  final parts = snapshot.data ?? 0;
                                  return Row(
                                    children: [
                                      Icon(Icons.event_available,
                                          color: Colors.green[700], size: 22),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: AutoSizeText(
                                          "Participations : $parts",
                                          style: TextStyle(
                                              color: Colors.green[700],
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15),
                                          maxLines: 1,
                                          minFontSize: 10,
                                          overflow: TextOverflow.ellipsis,
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
            )),
        const SizedBox(height: 24),
      ],
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mainColor = _mainColor;
    final bgColor = isDark ? const Color(0xFF181C20) : const Color(0xFFF7F8FA);

    final screenWidth = MediaQuery.of(context).size.width;
    final double cardPadding = screenWidth * 0.04;
    final double cardFontSize = screenWidth * 0.038;
    final double valueFontSize = screenWidth * 0.065;
    final double iconSize = screenWidth * 0.09;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
            "Mes statistiques",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: cardFontSize * 1.3,
              letterSpacing: 0.2,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: const [
              Tab(icon: Icon(Icons.bar_chart)),
              Tab(icon: Icon(Icons.star)),
              Tab(icon: Icon(Icons.event)),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: EdgeInsets.all(cardPadding * 1.5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: cardPadding * 0.5),
                        CircleAvatar(
                          radius: screenWidth * 0.11,
                          backgroundColor: mainColor.withOpacity(0.13),
                          child: Icon(
                            Icons.bar_chart_rounded,
                            size: screenWidth * 0.12,
                            color: mainColor,
                          ),
                        ),
                        SizedBox(height: cardPadding * 1.2),
                        AutoSizeText(
                          _pseudo != null && _pseudo!.isNotEmpty
                              ? _pseudo!
                              : "Utilisateur",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: cardFontSize * 1.5,
                            color: isDark ? Colors.white : mainColor,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 1,
                          minFontSize: 14,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 6),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: cardPadding * 0.7,
                              vertical: cardPadding * 0.3),
                          decoration: BoxDecoration(
                            color: mainColor.withOpacity(0.09),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _role == 'admin'
                                    ? Icons.verified
                                    : _role == 'premium'
                                        ? Icons.star
                                        : Icons.person,
                                color: mainColor,
                                size: cardFontSize * 1.1,
                              ),
                              SizedBox(width: 6),
                              AutoSizeText(
                                _role == 'admin'
                                    ? "Admin"
                                    : _role == 'premium'
                                        ? "Premium"
                                        : "Utilisateur",
                                style: TextStyle(
                                  color: mainColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: cardFontSize * 0.95,
                                ),
                                maxLines: 1,
                                minFontSize: 10,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: cardPadding * 2),
                        _periodSelector(),
                        SizedBox(height: cardPadding * 1.5),
                        GridView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: screenWidth < 400 ? 1 : 2,
                            mainAxisSpacing: cardPadding * 1.1,
                            crossAxisSpacing: cardPadding * 1.1,
                            childAspectRatio: 2.1,
                          ),
                          children: [
                            _statCard(
                              icon: Icons.favorite,
                              label: "Likes sur vos événements",
                              value: _likesOnEvents,
                              color: Colors.pink[400]!,
                              bgColor: isDark
                                  ? const Color(0xFF2A2227)
                                  : Colors.pink[50],
                              cardFontSize: cardFontSize,
                              valueFontSize: valueFontSize,
                              iconSize: iconSize,
                            ),
                            _statCard(
                              icon: Icons.share,
                              label: "Partages de vos événements",
                              value: _sharesOnEvents,
                              color: Colors.blue[700]!,
                              bgColor: isDark
                                  ? const Color(0xFF202A2F)
                                  : Colors.blue[50],
                              cardFontSize: cardFontSize,
                              valueFontSize: valueFontSize,
                              iconSize: iconSize,
                            ),
                            _statCard(
                              icon: Icons.visibility,
                              label: "Vues uniques de vos événements",
                              value: _uniqueViews,
                              color: Colors.deepPurple,
                              bgColor: isDark
                                  ? const Color(0xFF26222F)
                                  : Colors.deepPurple[50],
                              cardFontSize: cardFontSize,
                              valueFontSize: valueFontSize,
                              iconSize: iconSize,
                            ),
                            _statCard(
                              icon: Icons.event_available,
                              label: "Participations à vos événements",
                              value: _totalParticipations,
                              color: Colors.green[700]!,
                              bgColor: isDark
                                  ? const Color(0xFF222F26)
                                  : Colors.green[50],
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
                            color: isDark
                                ? const Color(0xFF23272F)
                                : Colors.blue[50],
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: mainColor, size: cardFontSize * 1.2),
                              SizedBox(width: cardPadding * 0.7),
                              Expanded(
                                child: AutoSizeText(
                                  "Ces statistiques sont calculées sur vos événements publics. Likes et vues sont uniques par utilisateur. Les participations comptent chaque inscription à vos événements. Les données sont conservées 31 jours maximum.",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey[700],
                                    fontSize: cardFontSize * 0.98,
                                  ),
                                  textAlign: TextAlign.left,
                                  maxLines: 4,
                                  minFontSize: 11,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: cardPadding * 1.5),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    padding: EdgeInsets.all(cardPadding * 1.5),
                    child: _buildRatingsTab(),
                  ),
                  SingleChildScrollView(
                    padding: EdgeInsets.all(cardPadding * 1.5),
                    child: _buildEventsTab(),
                  ),
                ],
              ),
      ),
    );
  }
}
