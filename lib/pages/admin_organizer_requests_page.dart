import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class AdminOrganizerRequestsPage extends StatefulWidget {
  const AdminOrganizerRequestsPage({Key? key}) : super(key: key);

  @override
  State<AdminOrganizerRequestsPage> createState() =>
      _AdminOrganizerRequestsPageState();
}

class _AdminOrganizerRequestsPageState extends State<AdminOrganizerRequestsPage>
    with SingleTickerProviderStateMixin {
  String _sortMode = 'priorite';
  String _citySortMode = 'desc';
  late TabController _tabController;

  int _totalActiveOrganizers = 0;
  int _totalEvents = 0;
  String _mostRepresentedCity = '';
  double _avgEventsPerOrganizer = 0;

  List<Map<String, dynamic>> _citiesStats = [];
  bool _loadingCities = false;

  List<Map<String, dynamic>> _privateCalendars = [];
  bool _loadingPrivateCalendars = false;

  String _sortByName = 'asc';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _fetchGlobalStats();
    _fetchCitiesStats();
    _fetchPrivateCalendars();
  }

  Future<bool> isBoss() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    return data != null && data['role'] == 'boss';
  }

  Future<void> _fetchGlobalStats() async {
    final now = DateTime.now();
    final reqSnap = await FirebaseFirestore.instance
        .collection('organizer_requests')
        .where('status', isEqualTo: 'accepted')
        .get();
    final activeDocs = reqSnap.docs.where((doc) {
      final data = Map<String, dynamic>.from(doc.data() as Map);
      return data['activeUntil'] != null &&
          (data['activeUntil'] as Timestamp).toDate().isAfter(now);
    }).toList();

    _totalActiveOrganizers = activeDocs.length;

    List<String> organizerIds = activeDocs
        .map((doc) => (doc.data() as Map)['userId'] as String)
        .where((id) => id.isNotEmpty)
        .toList();

    int totalEvents = 0;
    Map<String, int> cityCount = {};
    for (final orgId in organizerIds) {
      final eventsSnap = await FirebaseFirestore.instance
          .collection('events')
          .where('organizerId', isEqualTo: orgId)
          .get();
      totalEvents += eventsSnap.docs.length;
      for (final e in eventsSnap.docs) {
        final event = Map<String, dynamic>.from(e.data() as Map);
        final city = (event['city'] ?? '').toString();
        if (city.isNotEmpty) {
          cityCount[city] = (cityCount[city] ?? 0) + 1;
        }
      }
    }
    _totalEvents = totalEvents;
    _avgEventsPerOrganizer =
        _totalActiveOrganizers > 0 ? totalEvents / _totalActiveOrganizers : 0;
    _mostRepresentedCity = '';
    int maxCity = 0;
    cityCount.forEach((city, count) {
      if (count > maxCity) {
        maxCity = count;
        _mostRepresentedCity = city;
      }
    });

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _fetchCitiesStats() async {
    if (!mounted) return;
    setState(() {
      _loadingCities = true;
    });
    final eventsSnap =
        await FirebaseFirestore.instance.collection('events').get();
    Map<String, List<Map<String, dynamic>>> cityEvents = {};
    for (final doc in eventsSnap.docs) {
      final event = Map<String, dynamic>.from(doc.data() as Map);
      final city = (event['city'] ?? '').toString();
      if (city.isEmpty) continue;
      cityEvents[city] = cityEvents[city] ?? [];
      cityEvents[city]!.add(event);
    }

    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    List<Map<String, dynamic>> stats = [];
    for (final entry in cityEvents.entries) {
      final city = entry.key;
      final events = entry.value;

      int eventsThisMonth = events.where((e) {
        if (e['date'] is Timestamp) {
          final d = (e['date'] as Timestamp).toDate();
          return d.isAfter(firstDayOfMonth);
        }
        return false;
      }).length;

      int totalAnswers = 0;
      int eventsWithAnswers = 0;
      for (final e in events) {
        if (e['answersCount'] != null) {
          totalAnswers += (e['answersCount'] as int);
          eventsWithAnswers++;
        }
      }
      double avgAnswers =
          eventsWithAnswers > 0 ? totalAnswers / eventsWithAnswers : 0;

      Set<String> organizers = {};
      for (final e in events) {
        if (e['organizerId'] != null) {
          organizers.add(e['organizerId']);
        }
      }

      Set<String> participants = {};
      for (final e in events) {
        if (e['participants'] != null && e['participants'] is List) {
          for (var p in (e['participants'] as List)) {
            if (p is String) participants.add(p);
          }
        }
      }

      DateTime? nextEventDate;
      String? nextEventName;
      for (final e in events) {
        if (e['date'] is Timestamp) {
          final d = (e['date'] as Timestamp).toDate();
          if (d.isAfter(now)) {
            if (nextEventDate == null || d.isBefore(nextEventDate)) {
              nextEventDate = d;
              nextEventName = e['title'] ?? '';
            }
          }
        }
      }

      String? mostPopularEventName;
      int mostPopularCount = 0;
      for (final e in events) {
        int count = 0;
        if (e['participants'] != null && e['participants'] is List) {
          count = (e['participants'] as List).length;
        }
        if (count > mostPopularCount) {
          mostPopularCount = count;
          mostPopularEventName = e['title'] ?? '';
        }
      }

      stats.add({
        'city': city,
        'totalEvents': events.length,
        'eventsThisMonth': eventsThisMonth,
        'avgAnswers': avgAnswers,
        'organizersCount': organizers.length,
        'participantsCount': participants.length,
        'nextEventDate': nextEventDate,
        'nextEventName': nextEventName,
        'mostPopularEventName': mostPopularEventName,
        'mostPopularCount': mostPopularCount,
      });
    }

    stats.sort((a, b) => b['totalEvents'].compareTo(a['totalEvents']));

    if (!mounted) return;
    setState(() {
      _citiesStats = stats;
      _loadingCities = false;
    });
  }

  Future<void> _fetchPrivateCalendars() async {
    if (!mounted) return;
    setState(() => _loadingPrivateCalendars = true);
    final calendarsSnap =
        await FirebaseFirestore.instance.collection('private_calendars').get();

    List<Map<String, dynamic>> allCalendars = [];
    for (final calDoc in calendarsSnap.docs) {
      final calendarId = calDoc.id;
      final calendarData = calDoc.data();
      final ownerId = calendarData['ownerId'];
      final calendarName = calendarData['name'] ?? '';
      final inviteCode = calendarData['inviteCode'] ?? '';
      final ville = calendarData['ville'] ?? '';
      final createdAt = calendarData['createdAt'];
      allCalendars.add({
        'calendarId': calendarId,
        'calendarName': calendarName,
        'ownerId': ownerId,
        'inviteCode': inviteCode,
        'ville': ville,
        'createdAt': createdAt,
      });
    }
    if (_sortByName == 'asc') {
      allCalendars.sort((a, b) => (a['calendarName'] ?? '')
          .toString()
          .compareTo((b['calendarName'] ?? '').toString()));
    } else {
      allCalendars.sort((a, b) => (b['calendarName'] ?? '')
          .toString()
          .compareTo((a['calendarName'] ?? '').toString()));
    }
    if (!mounted) return;
    setState(() {
      _privateCalendars = allCalendars;
      _loadingPrivateCalendars = false;
    });
  }

  Future<void> _showConfirmationDialog(
    BuildContext context,
    String action,
    VoidCallback onConfirm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$action la demande ?'),
        content: Text('Es-tu sûr de vouloir $action cette demande ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }

  void _showSnackBar(BuildContext context, String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _acceptRequest(BuildContext context, Map<String, dynamic> data,
      DocumentReference docRef) async {
    Navigator.pop(context);
    DateTime now = DateTime.now();
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
      helpText: "Choisir la date de fin d'activation",
      locale: const Locale('fr', 'FR'),
    );
    if (picked != null) {
      await docRef.update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'activeUntil': Timestamp.fromDate(picked),
        'revokedAt': null,
        'revokedReason': null,
      });
      if (data['userId'] != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(data['userId'])
            .update({
          'role': 'organizer',
          'subscriptionStatus': 'active',
          'subscriptionEndDate': Timestamp.fromDate(picked),
        });
      }
      _showSnackBar(context, "Demande acceptée et utilisateur promu ");
      await _fetchGlobalStats();
    }
  }

  void _showDetailsDialog(BuildContext context, Map<String, dynamic> data,
      DocumentReference docRef) {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final iconSize = screenWidth * 0.07;

    final fields = [
      {
        'label': 'Nom de l\'entreprise',
        'value': data['companyName'],
        'icon': Icons.business
      },
      {
        'label': 'Responsable',
        'value': data['responsable'],
        'icon': Icons.person
      },
      {'label': 'Email', 'value': data['contactEmail'], 'icon': Icons.email},
      {
        'label': 'Téléphone',
        'value': data['contactPhone'] ?? data['phone'],
        'icon': Icons.phone
      },
      {'label': 'Ville', 'value': data['city'], 'icon': Icons.location_city},
      {
        'label': 'Motivation',
        'value': data['motivation'],
        'icon': Icons.messenger_outline
      },
      {
        'label': 'Date de demande',
        'value': (data.containsKey('createdAt') && data['createdAt'] != null)
            ? (data['createdAt'] as Timestamp).toDate().toString()
            : "(non renseigné)",
        'icon': Icons.calendar_today
      },
    ];
    final totalFields = fields.length;
    final filledFields = fields
        .where((f) =>
            f['value'] != null && f['value'].toString().trim().isNotEmpty)
        .length;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data['companyName'] ?? 'Sans nom',
            style: TextStyle(fontSize: fontNormal * 1.2)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Champs remplis : $filledFields / $totalFields',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: fontNormal)),
              SizedBox(height: fontNormal * 0.8),
              ...fields.map((f) => Column(
                    children: [
                      Row(
                        children: [
                          Icon(f['icon'] as IconData, size: fontNormal * 1.1),
                          SizedBox(width: fontNormal * 0.6),
                          Expanded(
                            child: Text(
                              '${f['label']} : ${f['value'] ?? "(non renseigné)"}',
                              style: TextStyle(fontSize: fontNormal),
                            ),
                          ),
                        ],
                      ),
                      Divider(height: fontNormal * 1.2),
                    ],
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _acceptRequest(context, data, docRef);
            },
            child: const Text('Accepter'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showConfirmationDialog(context, "Refuser", () async {
                await docRef.update({'status': 'refused'});
                _showSnackBar(context, "Demande refusée.");
              });
            },
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
  }

  Widget _pendingRequestsTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final cardPadding = screenWidth * 0.025;
    final iconSize = screenWidth * 0.07;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('organizer_requests')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;

        docs.sort((a, b) {
          final aMap = Map<String, dynamic>.from(a.data() as Map);
          final bMap = Map<String, dynamic>.from(b.data() as Map);
          final aTime = aMap['createdAt'] != null
              ? (aMap['createdAt'] as Timestamp).toDate()
              : DateTime(2100);
          final bTime = bMap['createdAt'] != null
              ? (bMap['createdAt'] as Timestamp).toDate()
              : DateTime(2100);
          if (_sortMode == 'priorite') {
            return aTime.compareTo(bTime);
          } else {
            return bTime.compareTo(aTime);
          }
        });

        if (docs.isEmpty) {
          return const Center(child: Text('Aucune demande en attente.'));
        }
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = Map<String, dynamic>.from(docs[index].data() as Map);
            final docRef = docs[index].reference;
            return Card(
              margin: EdgeInsets.all(cardPadding),
              child: ListTile(
                leading: CircleAvatar(
                  radius: iconSize * 0.5,
                  child: Icon(Icons.business, size: iconSize * 0.7),
                ),
                title: Text(data['companyName'] ?? 'Sans nom',
                    style: TextStyle(
                        fontFamily: 'Roboto', fontSize: fontNormal * 1.2)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Responsable: ${data['responsable'] ?? ''}',
                        style: TextStyle(
                            fontFamily: 'Roboto', fontSize: fontNormal)),
                    Text('Email: ${data['contactEmail'] ?? ''}',
                        style: TextStyle(
                            fontFamily: 'Roboto', fontSize: fontNormal)),
                  ],
                ),
                isThreeLine: true,
                onTap: () => _showDetailsDialog(context, data, docRef),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.check,
                          color: Colors.green, size: iconSize * 0.7),
                      tooltip: 'Accepter',
                      onPressed: () =>
                          _showDetailsDialog(context, data, docRef),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: Colors.red, size: iconSize * 0.7),
                      tooltip: 'Refuser',
                      onPressed: () {
                        _showConfirmationDialog(context, "Refuser", () async {
                          await docRef.update({'status': 'refused'});
                          _showSnackBar(context, "Demande refusée.");
                        });
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _activeOrganizersTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final cardPadding = screenWidth * 0.025;
    final iconSize = screenWidth * 0.07;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('organizer_requests')
          .where('status', isEqualTo: 'accepted')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        final now = DateTime.now();
        final activeDocs = docs.where((doc) {
          final data = Map<String, dynamic>.from(doc.data() as Map);
          return data['activeUntil'] != null &&
              (data['activeUntil'] as Timestamp).toDate().isAfter(now);
        }).toList();

        activeDocs.sort((a, b) {
          final aMap = Map<String, dynamic>.from(a.data() as Map);
          final bMap = Map<String, dynamic>.from(b.data() as Map);
          final aTime = aMap['acceptedAt'] != null
              ? (aMap['acceptedAt'] as Timestamp).toDate()
              : DateTime(2100);
          final bTime = bMap['acceptedAt'] != null
              ? (bMap['acceptedAt'] as Timestamp).toDate()
              : DateTime(2100);
          if (_sortMode == 'priorite') {
            return aTime.compareTo(bTime);
          } else {
            return bTime.compareTo(aTime);
          }
        });

        if (activeDocs.isEmpty) {
          return const Center(child: Text('Aucun organisateur actif.'));
        }
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.blueGrey[800],
              padding: EdgeInsets.symmetric(
                  vertical: fontNormal * 1.2, horizontal: fontNormal * 0.9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Stats organisateurs actifs",
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: fontNormal * 1.2,
                        fontFamily: 'Roboto'),
                  ),
                  SizedBox(height: fontNormal * 0.5),
                  Wrap(
                    spacing: fontNormal * 1.5,
                    runSpacing: fontNormal * 0.5,
                    children: [
                      Text(
                        "Total : $_totalActiveOrganizers",
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: fontNormal),
                      ),
                      Text(
                        "Événements : $_totalEvents",
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: fontNormal),
                      ),
                      Text(
                        "Ville la + représentée : ${_mostRepresentedCity.isNotEmpty ? _mostRepresentedCity : "Aucune"}",
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: fontNormal),
                      ),
                      Text(
                        "Moyenne événements/org. : ${_avgEventsPerOrganizer.toStringAsFixed(1)}",
                        style: TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: fontNormal),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: activeDocs.length,
                itemBuilder: (context, index) {
                  final data = Map<String, dynamic>.from(
                      activeDocs[index].data() as Map);
                  final docRef = activeDocs[index].reference;
                  return Card(
                    margin: EdgeInsets.all(cardPadding),
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green,
                        radius: iconSize * 0.5,
                        child: Icon(Icons.verified,
                            color: Colors.white, size: iconSize * 0.7),
                      ),
                      title: Text(data['companyName'] ?? 'Sans nom',
                          style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: fontNormal * 1.2,
                              fontWeight: FontWeight.w500)),
                      subtitle: Text(
                          'Responsable: ${data['responsable'] ?? ''}',
                          style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: fontNormal,
                              color: Colors.grey[600])),
                      onTap: () async {
                        final eventsSnap = await FirebaseFirestore.instance
                            .collection('events')
                            .where('organizerId', isEqualTo: data['userId'])
                            .get();
                        final events = eventsSnap.docs
                            .map((e) =>
                                Map<String, dynamic>.from(e.data() as Map))
                            .toList();

                        final totalEvents = events.length;
                        String mostCity = '';
                        int mostCityCount = 0;
                        DateTime? lastEventDate;
                        DateTime? firstEventDate;
                        int upcomingEvents = 0;
                        Set<String> cities = {};
                        for (var e in events) {
                          final city = (e['city'] ?? '').toString();
                          if (city.isNotEmpty) {
                            cities.add(city);
                            final count = events
                                .where((ev) => (ev['city'] ?? '') == city)
                                .length;
                            if (count > mostCityCount) {
                              mostCity = city;
                              mostCityCount = count;
                            }
                          }
                          if (e['date'] != null) {
                            final d = (e['date'] as Timestamp).toDate();
                            if (lastEventDate == null ||
                                d.isAfter(lastEventDate)) {
                              lastEventDate = d;
                            }
                            if (firstEventDate == null ||
                                d.isBefore(firstEventDate)) {
                              firstEventDate = d;
                            }
                            if (d.isAfter(DateTime.now())) {
                              upcomingEvents++;
                            }
                          }
                        }

                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(data['companyName'] ?? 'Sans nom',
                                style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: fontNormal * 1.3,
                                    fontWeight: FontWeight.bold)),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Responsable: ${data['responsable'] ?? ""}',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                  Text('Email: ${data['contactEmail'] ?? ""}',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                  SizedBox(height: fontNormal),
                                  Text('Nombre d\'événements : $totalEvents',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                  Text(
                                      'Ville la plus fréquente : ${mostCity.isNotEmpty ? mostCity : "Aucune"}',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                  Text(
                                      'Nombre de villes différentes : ${cities.length}',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                  if (firstEventDate != null)
                                    Text(
                                        'Premier événement : ${firstEventDate.toLocal().toString().split(' ')[0]}',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: fontNormal,
                                            color: Colors.grey[700])),
                                  if (lastEventDate != null)
                                    Text(
                                        'Dernier événement : ${lastEventDate.toLocal().toString().split(' ')[0]}',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: fontNormal,
                                            color: Colors.grey[700])),
                                  Text('Événements à venir : $upcomingEvents',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: fontNormal,
                                          color: Colors.grey[700])),
                                ],
                              ),
                            ),
                            actions: [
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFF1976D2),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Fermer',
                                    style: TextStyle(fontFamily: 'Roboto')),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text(
                                          'Retirer les permissions ?'),
                                      content: const Text(
                                          'Voulez-vous vraiment retirer les droits d\'organisateur à cette personne ?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Annuler'),
                                        ),
                                        ElevatedButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Confirmer'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true &&
                                      data['userId'] != null) {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(data['userId'])
                                        .update({
                                      'role': 'user',
                                      'subscriptionStatus': 'inactive',
                                      'subscriptionEndDate': null,
                                    });
                                    await docRef.update({
                                      'status': 'revoked',
                                      'revokedAt': FieldValue.serverTimestamp(),
                                      'revokedReason':
                                          "Profil jugé non sérieux après analyse"
                                    });
                                    if (!mounted) return;
                                    Navigator.pop(context);
                                    _showSnackBar(
                                        context, "Permissions retirées.");
                                    await _fetchGlobalStats();
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFF44336),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Retirer les droits',
                                    style: TextStyle(fontFamily: 'Roboto')),
                              ),
                            ],
                          ),
                        );
                      },
                      trailing: IconButton(
                        icon: Icon(Icons.remove_circle,
                            color: Colors.red, size: iconSize * 0.7),
                        tooltip: 'Retirer les permissions',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Retirer les permissions ?'),
                              content: const Text(
                                  'Voulez-vous vraiment retirer les droits d\'organisateur à cette personne ?'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Annuler'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Confirmer'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true && data['userId'] != null) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(data['userId'])
                                .update({
                              'role': 'user',
                              'subscriptionStatus': 'inactive',
                              'subscriptionEndDate': null,
                            });
                            await docRef.update({
                              'status': 'revoked',
                              'revokedAt': FieldValue.serverTimestamp(),
                              'revokedReason':
                                  "Profil jugé non sérieux après analyse"
                            });
                            if (!mounted) return;
                            _showSnackBar(context, "Permissions retirées.");
                            await _fetchGlobalStats();
                          }
                        },
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

  Widget _citiesTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final cardPadding = screenWidth * 0.025;
    final iconSize = screenWidth * 0.07;

    if (_loadingCities) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_citiesStats.isEmpty) {
      return const Center(child: Text("Aucune ville avec des événements."));
    }
    List<Map<String, dynamic>> sortedCities = List.from(_citiesStats);
    if (_citySortMode == 'desc') {
      sortedCities.sort((a, b) => b['totalEvents'].compareTo(a['totalEvents']));
    } else {
      sortedCities.sort((a, b) => a['totalEvents'].compareTo(b['totalEvents']));
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: fontNormal * 2, vertical: fontNormal * 0.5),
          child: LayoutBuilder(
            builder: (context, constraints) {
              double dynamicFont = fontNormal * 1.1;
              if (constraints.maxWidth < 350) {
                dynamicFont = fontNormal * 0.95;
              }
              if (constraints.maxWidth < 300) {
                dynamicFont = fontNormal * 0.8;
              }
              if (constraints.maxWidth < 260) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Trier par : ',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: dynamicFont,
                            color: Color(0xFF1976D2))),
                    DropdownButton<String>(
                      value: _citySortMode,
                      dropdownColor: Color(0xFFE0F7FA),
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: dynamicFont * 0.9,
                          color: Color(0xFF1976D2)),
                      underline: Container(
                        height: 2,
                        color: Color(0xFF1976D2),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'desc',
                          child: Text('Plus d\'événements'),
                        ),
                        DropdownMenuItem(
                          value: 'asc',
                          child: Text('Moins d\'événements'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null)
                          setState(() => _citySortMode = value);
                      },
                    ),
                  ],
                );
              } else {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text('Trier par : ',
                          style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: dynamicFont,
                              color: Color(0xFF1976D2)),
                          overflow: TextOverflow.ellipsis),
                    ),
                    DropdownButton<String>(
                      value: _citySortMode,
                      dropdownColor: Color(0xFFE0F7FA),
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: dynamicFont * 0.9,
                          color: Color(0xFF1976D2)),
                      underline: Container(
                        height: 2,
                        color: Color(0xFF1976D2),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'desc',
                          child: Text('Plus d\'événements'),
                        ),
                        DropdownMenuItem(
                          value: 'asc',
                          child: Text('Moins d\'événements'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null)
                          setState(() => _citySortMode = value);
                      },
                    ),
                  ],
                );
              }
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            itemCount: sortedCities.length,
            itemBuilder: (context, index) {
              final city = sortedCities[index];
              return Card(
                margin: EdgeInsets.symmetric(vertical: cardPadding),
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: Icon(Icons.location_city,
                      color: Color(0xFF1976D2), size: iconSize),
                  title: Text(city['city'],
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: fontNormal * 1.2,
                          fontWeight: FontWeight.w500)),
                  subtitle: Text(
                      "Événements : ${city['totalEvents']} | Ce mois : ${city['eventsThisMonth']} | Moy. réponses : ${city['avgAnswers'].toStringAsFixed(1)}",
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: fontNormal,
                          color: Colors.grey[600])),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Text("Statistiques pour ${city['city']}",
                            style: TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: fontNormal * 1.3,
                                fontWeight: FontWeight.bold)),
                        content: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  "Nombre total d'événements : ${city['totalEvents']}",
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal,
                                      color: Colors.grey[700])),
                              SizedBox(height: fontNormal * 0.5),
                              Text(
                                  "Événements ce mois : ${city['eventsThisMonth']}",
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal,
                                      color: Colors.grey[700])),
                              SizedBox(height: fontNormal * 0.5),
                              Text(
                                  "Organisateurs actifs : ${city['organizersCount']}",
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal,
                                      color: Colors.grey[700])),
                              SizedBox(height: fontNormal * 0.5),
                              Text(
                                  "Participants uniques : ${city['participantsCount']}",
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal,
                                      color: Colors.grey[700])),
                              SizedBox(height: fontNormal * 0.5),
                              Text(
                                  "Moyenne réponses : ${city['avgAnswers'].toStringAsFixed(1)}",
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: fontNormal,
                                      color: Colors.grey[700])),
                              if (city['nextEventDate'] != null)
                                Text(
                                    "Prochain événement : ${city['nextEventName'] ?? ''} (${city['nextEventDate'].toString().split(' ')[0]})",
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: fontNormal,
                                        color: Colors.grey[700])),
                              if (city['mostPopularEventName'] != null)
                                Text(
                                    "Événement populaire : ${city['mostPopularEventName']} (${city['mostPopularCount']} participants)",
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: fontNormal,
                                        color: Colors.grey[700])),
                            ],
                          ),
                        ),
                        actions: [
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Fermer',
                                style: TextStyle(fontFamily: 'Roboto')),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: city['city']));
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Nom copié dans le presse-papier')),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Copier le nom',
                                style: TextStyle(fontFamily: 'Roboto')),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _feedbackTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final cardPadding = screenWidth * 0.025;
    final iconSize = screenWidth * 0.07;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('admin_organizer_requests')
          .where('type', isEqualTo: 'feedback')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Aucun retour pour le moment.'));
        }
        docs.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aPinned =
              (aData.containsKey('pinned') && aData['pinned'] == true) ? 1 : 0;
          final bPinned =
              (bData.containsKey('pinned') && bData['pinned'] == true) ? 1 : 0;
          return bPinned.compareTo(aPinned);
        });
        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: cardPadding),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final docRef = docs[index].reference;
            final email = data['email'] ?? 'Inconnu';
            final isPinned =
                data.containsKey('pinned') && data['pinned'] == true;
            return Card(
              margin: EdgeInsets.symmetric(vertical: cardPadding),
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.mail,
                  color: isPinned ? Colors.amber : Colors.blueGrey,
                  size: iconSize,
                ),
                title: Text(email,
                    style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: fontNormal * 1.1,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(
                  (data['createdAt'] != null && data['createdAt'] is Timestamp)
                      ? (data['createdAt'] as Timestamp)
                          .toDate()
                          .toString()
                          .split('.')[0]
                      : '',
                  style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: fontNormal * 0.85,
                      color: Colors.grey[600]),
                ),
                trailing: isPinned
                    ? Icon(Icons.push_pin,
                        color: Colors.amber, size: iconSize * 0.7)
                    : null,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      title: Row(
                        children: [
                          Text(email,
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: fontNormal * 1.1,
                                  fontWeight: FontWeight.bold)),
                          if (isPinned)
                            Padding(
                              padding: EdgeInsets.only(left: fontNormal * 0.5),
                              child: Icon(Icons.push_pin,
                                  color: Colors.amber, size: iconSize * 0.7),
                            ),
                        ],
                      ),
                      content: Text(data['message'] ?? '',
                          style: TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: fontNormal,
                              color: Colors.grey[700])),
                      actions: [
                        IconButton(
                          tooltip: isPinned ? "Désépingler" : "Épingler",
                          icon: Icon(
                            Icons.push_pin,
                            color: isPinned ? Colors.amber : Colors.grey,
                            size: iconSize * 0.7,
                          ),
                          onPressed: () async {
                            await docRef.update({'pinned': !isPinned});
                            Navigator.pop(context);
                          },
                        ),
                        IconButton(
                          tooltip: "Marquer comme lu et supprimer",
                          icon: Icon(Icons.thumb_up,
                              color: Colors.green, size: iconSize * 0.7),
                          onPressed: () async {
                            await docRef.delete();
                            Navigator.pop(context);
                            if (!mounted) return;
                            _showSnackBar(context, "Retour supprimé.");
                          },
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Fermer',
                              style: TextStyle(fontFamily: 'Roboto')),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _privateCalendarsTab() {
    final screenWidth = MediaQuery.of(context).size.width;
    final fontNormal = screenWidth * 0.034;
    final cardPadding = screenWidth * 0.025;
    final iconSize = screenWidth * 0.07;

    if (_loadingPrivateCalendars) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_privateCalendars.isEmpty) {
      return const Center(child: Text("Aucun calendrier privé trouvé."));
    }

    return ListView.builder(
      itemCount: _privateCalendars.length,
      itemBuilder: (context, index) {
        final calendar = _privateCalendars[index];
        final calendarName = calendar['calendarName'] ?? '';
        final ville = calendar['ville'] ?? '';
        final inviteCode = calendar['inviteCode'] ?? '';
        final calendarId = calendar['calendarId'];

        return Card(
          margin: EdgeInsets.symmetric(vertical: cardPadding),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: Icon(Icons.lock, color: Colors.deepPurple, size: iconSize),
            title: Text(calendarName.isNotEmpty ? calendarName : 'Sans nom',
                style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: fontNormal * 1.2,
                    fontWeight: FontWeight.w500)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (ville.isNotEmpty)
                  Text("Ville : $ville",
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: fontNormal,
                          color: Colors.grey[600])),
                if (inviteCode.isNotEmpty)
                  Text("Code d'accès : $inviteCode",
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: fontNormal,
                          color: Colors.grey[600])),
              ],
            ),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  title: Text(
                      calendarName.isNotEmpty ? calendarName : 'Sans nom',
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: fontNormal * 1.3,
                          fontWeight: FontWeight.bold)),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ville.isNotEmpty)
                          Text("Ville : $ville",
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: fontNormal,
                                  color: Colors.grey[700])),
                        if (inviteCode.isNotEmpty)
                          Text("Code d'accès : $inviteCode",
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: fontNormal,
                                  color: Colors.grey[700])),
                      ],
                    ),
                  ),
                  actions: [
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1976D2),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Fermer',
                          style: TextStyle(fontFamily: 'Roboto')),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pushNamed(
                          context,
                          '/private_calendar',
                          arguments: {
                            'calendarId': calendarId,
                            'calendarName': calendarName,
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('S’y rendre',
                          style: TextStyle(fontFamily: 'Roboto')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFF44336),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: const Text('Supprimer ce calendrier ?',
                                style: TextStyle(fontFamily: 'Roboto')),
                            content: const Text(
                                'Voulez-vous vraiment supprimer ce calendrier privé ? Cette action est irréversible.',
                                style: TextStyle(fontFamily: 'Roboto')),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Annuler',
                                    style: TextStyle(fontFamily: 'Roboto')),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Color(0xFFF44336),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('Supprimer',
                                    style: TextStyle(fontFamily: 'Roboto')),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await FirebaseFirestore.instance
                              .collection('private_calendars')
                              .doc(calendarId)
                              .delete();
                          if (!mounted) return;
                          Navigator.pop(context);
                          _showSnackBar(context, "Calendrier supprimé.");
                          _fetchPrivateCalendars();
                        }
                      },
                      child: const Text('Supprimer',
                          style: TextStyle(fontFamily: 'Roboto')),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double fontTitle = screenWidth * 0.055;
    double fontSubtitle = screenWidth * 0.042;
    double fontNormal = screenWidth * 0.034;
    double iconSize = screenWidth * 0.07;
    double tabFontSize = screenWidth * 0.035;

    return FutureBuilder<bool>(
      future: isBoss(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (!snapshot.data!) {
          return Scaffold(
            backgroundColor: colorScheme.background,
            appBar: AppBar(
              title: Row(
                children: [
                  Icon(Icons.admin_panel_settings,
                      color: colorScheme.error, size: iconSize),
                  SizedBox(width: screenWidth * 0.02),
                  Text('Accès refusé',
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: fontTitle,
                      )),
                ],
              ),
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
            ),
            body: Center(
              child: Text(
                "Vous n'avez pas la permission d'accéder à cette page.",
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                  fontSize: fontSubtitle,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: colorScheme.background,
          appBar: AppBar(
              backgroundColor: colorScheme.primary,
              foregroundColor: colorScheme.onPrimary,
              elevation: 6,
              title: Row(
                children: [
                  Icon(Icons.admin_panel_settings,
                      color: colorScheme.onPrimary, size: iconSize),
                  SizedBox(width: screenWidth * 0.02),
                  // Correction responsive :
                  Expanded(
                    child: Text(
                      'Gestion organisateurs (Admin)',
                      style: textTheme.titleLarge?.copyWith(
                        color: colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: fontTitle,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: colorScheme.secondary,
                labelColor: colorScheme.onPrimary,
                unselectedLabelColor: colorScheme.onPrimary.withOpacity(0.7),
                labelStyle: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: screenWidth < 400
                      ? 11
                      : tabFontSize, // <-- taille réduite sur mobile
                ),
                unselectedLabelStyle: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w400,
                  fontSize: screenWidth < 400 ? 10 : tabFontSize * 0.95,
                ),
                tabs: [
                  Tab(
                      icon: Icon(Icons.pending_actions, size: iconSize),
                      text: "Demandes"),
                  Tab(
                      icon: Icon(Icons.verified_user, size: iconSize),
                      text: "Organisateurs actifs"),
                  Tab(
                      icon: Icon(Icons.location_city, size: iconSize),
                      text: "Villes"),
                  Tab(
                      icon: Icon(Icons.feedback, size: iconSize),
                      text: "Retours"),
                  Tab(
                      icon: Icon(Icons.lock, size: iconSize),
                      text: "Calendriers privés"),
                ],
              )),
          body: Container(
            color: colorScheme.background,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.04,
                      vertical: screenHeight * 0.015),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      double dynamicFont = fontSubtitle;
                      if (constraints.maxWidth < 350) {
                        dynamicFont = fontSubtitle * 0.85;
                      }
                      if (constraints.maxWidth < 300) {
                        dynamicFont = fontSubtitle * 0.7;
                      }
                      // Si vraiment trop petit, on passe en colonne
                      if (constraints.maxWidth < 260) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Trier par : ',
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w500,
                                fontSize: dynamicFont,
                              ),
                            ),
                            DropdownButton<String>(
                              value: _sortMode,
                              dropdownColor: colorScheme.surface,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.primary,
                                fontSize: dynamicFont * 0.9,
                              ),
                              underline: Container(
                                height: 2,
                                color: colorScheme.primary,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'priorite',
                                  child: Text('Priorité (plus ancien)'),
                                ),
                                DropdownMenuItem(
                                  value: 'recent',
                                  child: Text('Plus récent'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _sortMode = value);
                              },
                            ),
                          ],
                        );
                      } else {
                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: Text(
                                'Trier par : ',
                                style: textTheme.titleMedium?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                  fontSize: dynamicFont,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            DropdownButton<String>(
                              value: _sortMode,
                              dropdownColor: colorScheme.surface,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colorScheme.primary,
                                fontSize: dynamicFont * 0.9,
                              ),
                              underline: Container(
                                height: 2,
                                color: colorScheme.primary,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'priorite',
                                  child: Text('Priorité (plus ancien)'),
                                ),
                                DropdownMenuItem(
                                  value: 'recent',
                                  child: Text('Plus récent'),
                                ),
                              ],
                              onChanged: (value) {
                                if (value != null)
                                  setState(() => _sortMode = value);
                              },
                            ),
                          ],
                        );
                      }
                    },
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _pendingRequestsTab(),
                      _activeOrganizersTab(),
                      _citiesTab(),
                      _feedbackTab(),
                      _privateCalendarsTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
