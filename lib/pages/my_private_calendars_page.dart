import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:auto_size_text/auto_size_text.dart';
import '../providers/theme_provider.dart';

class MyPrivateCalendarsPage extends StatefulWidget {
  const MyPrivateCalendarsPage({super.key});

  @override
  State<MyPrivateCalendarsPage> createState() => _MyPrivateCalendarsPageState();
}

class _MyPrivateCalendarsPageState extends State<MyPrivateCalendarsPage> {
  List<Map<String, dynamic>> _allCalendars = [];
  List<Map<String, dynamic>> _filteredCalendars = [];
  String _filter = 'all';
  bool _loading = true;
  String? _userId;
  List<String> _pinnedCalendars = [];
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _fetchCalendars();
    _loadThemePreference();
  }

  Future<void> _fetchCalendars() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      return;
    }
    _userId = user.uid;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(_userId).get();
    final userData = userDoc.data();
    List<String> visited =
        List<String>.from(userData?['visitedPrivateCalendars'] ?? []);
    _pinnedCalendars =
        List<String>.from(userData?['pinnedPrivateCalendars'] ?? []);

    final ownerSnap = await FirebaseFirestore.instance
        .collection('private_calendars')
        .where('ownerId', isEqualTo: _userId)
        .get();
    final ownerIds = ownerSnap.docs.map((doc) => doc.id).toList();

    final allIds = {...visited, ..._pinnedCalendars, ...ownerIds}.toList();
    if (allIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _allCalendars = [];
        _filteredCalendars = [];
        _loading = false;
      });
      return;
    }

    final snap = await FirebaseFirestore.instance
        .collection('private_calendars')
        .where(FieldPath.documentId, whereIn: allIds)
        .get();

    final all = snap.docs.map((doc) {
      final data = doc.data();
      data['calendarId'] = doc.id;
      return data;
    }).toList();

    all.sort((a, b) {
      final aPinned = _pinnedCalendars.contains(a['calendarId']) ? 0 : 1;
      final bPinned = _pinnedCalendars.contains(b['calendarId']) ? 0 : 1;
      if (aPinned != bPinned) return aPinned.compareTo(bPinned);
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    if (!mounted) return;
    setState(() {
      _allCalendars = all;
      _filteredCalendars = _applyFilterAndSort(all);
      _loading = false;
    });
  }

  Future<void> _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    });
  }

  Future<void> _saveThemePreference(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  List<Map<String, dynamic>> _applyFilterAndSort(
      List<Map<String, dynamic>> list) {
    List<Map<String, dynamic>> filtered = [];
    if (_filter == 'all') {
      filtered = List.from(list);
    } else if (_filter == 'mine') {
      filtered = list.where((data) => data['ownerId'] == _userId).toList();
    } else if (_filter == 'member') {
      filtered = list
          .where((data) =>
              data['ownerId'] != _userId &&
              (data['members'] as Map<String, dynamic>?)
                      ?.containsKey(_userId) ==
                  true)
          .toList();
    }
    filtered.sort((a, b) {
      final aPinned = _pinnedCalendars.contains(a['calendarId']) ? 0 : 1;
      final bPinned = _pinnedCalendars.contains(b['calendarId']) ? 0 : 1;
      if (aPinned != bPinned) return aPinned.compareTo(bPinned);
      final nameA = (a['name'] ?? '').toString().toLowerCase();
      final nameB = (b['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
    return filtered;
  }

  void _setFilter(String filter) {
    setState(() {
      _filter = filter;
      _filteredCalendars = _applyFilterAndSort(_allCalendars);
    });
  }

  Future<void> _togglePin(String calendarId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final userSnap = await userRef.get();
    final userData = userSnap.data();
    List<String> pinned =
        List<String>.from(userData?['pinnedPrivateCalendars'] ?? []);
    if (pinned.contains(calendarId)) {
      pinned.remove(calendarId);
    } else {
      pinned.insert(0, calendarId); // Place en haut
    }
    await userRef.update({'pinnedPrivateCalendars': pinned});
    if (!mounted) return;
    setState(() {
      _pinnedCalendars = pinned;
      _filteredCalendars = _applyFilterAndSort(_allCalendars);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final hasMine = _allCalendars.any((data) => data['ownerId'] == _userId);
    final hasMember = _allCalendars.any((data) =>
        data['ownerId'] != _userId &&
        (data['members'] as Map<String, dynamic>?)?.containsKey(_userId) ==
            true);

    return Scaffold(
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: screenWidth * 0.09,
              left: 0,
              right: 0,
              bottom: screenWidth * 0.045,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: themeProvider.isDarkMode
                    ? [const Color(0xFF0F2027), const Color(0xFF2C5364)]
                    : [const Color(0xFFF5F6FA), const Color(0xFFE3F2FD)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(screenWidth * 0.07),
              ),
              boxShadow: [
                BoxShadow(
                  color: themeProvider.isDarkMode
                      ? Colors.black38
                      : Colors.black26.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: themeProvider.isDarkMode
                            ? Colors.white
                            : const Color(0xFF1976D2),
                        size: screenWidth * 0.055),
                    onPressed: () => Navigator.pop(context),
                    tooltip: "Retour",
                  ),
                ),
                Center(
                  child: Column(
                    children: [
                      AutoSizeText(
                        "Mes accès privés",
                        style: TextStyle(
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : const Color(0xFF2C5364),
                          fontSize: screenWidth * 0.055,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'SansSerif',
                          letterSpacing: 1.2,
                        ),
                        maxLines: 1,
                        minFontSize: 16,
                        maxFontSize: 22,
                        stepGranularity: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: screenWidth * 0.015),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.04),
                        child: AutoSizeText(
                          "Retrouvez ici tous vos calendriers privés visités, épinglés ou créés.",
                          style: TextStyle(
                            color: themeProvider.isDarkMode
                                ? Colors.white.withOpacity(0.92)
                                : const Color(0xFF424242),
                            fontSize: screenWidth * 0.032,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          minFontSize: 10,
                          maxFontSize: 14,
                          stepGranularity: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: screenWidth * 0.03, vertical: screenWidth * 0.025),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilterChip(
                  label: Text(
                    "Tous",
                    style: TextStyle(fontSize: screenWidth * 0.042),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  selected: _filter == 'all',
                  onSelected: (_) => _setFilter('all'),
                  selectedColor: themeProvider.isDarkMode
                      ? Colors.blue.shade900
                      : Colors.blue.shade100,
                  backgroundColor: themeProvider.isDarkMode
                      ? Colors.grey.shade800
                      : Colors.grey.shade200,
                ),
                SizedBox(width: screenWidth * 0.02),
                if (hasMine)
                  FilterChip(
                    label: Text(
                      "Mes calendriers",
                      style: TextStyle(fontSize: screenWidth * 0.042),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: _filter == 'mine',
                    onSelected: (_) => _setFilter('mine'),
                    selectedColor: themeProvider.isDarkMode
                        ? Colors.green.shade900
                        : Colors.green.shade100,
                    backgroundColor: themeProvider.isDarkMode
                        ? Colors.grey.shade800
                        : Colors.grey.shade200,
                  ),
                if (hasMember) ...[
                  SizedBox(width: screenWidth * 0.02),
                  FilterChip(
                    label: Text(
                      "Où je suis invité",
                      style: TextStyle(fontSize: screenWidth * 0.042),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    selected: _filter == 'member',
                    onSelected: (_) => _setFilter('member'),
                    selectedColor: themeProvider.isDarkMode
                        ? Colors.purple.shade900
                        : Colors.purple.shade100,
                    backgroundColor: themeProvider.isDarkMode
                        ? Colors.grey.shade800
                        : Colors.grey.shade200,
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCalendars.isEmpty
                    ? Center(
                        child: Padding(
                          padding: EdgeInsets.only(top: screenWidth * 0.18),
                          child: AutoSizeText(
                            "Aucun calendrier privé",
                            style: TextStyle(
                              fontSize: screenWidth * 0.055,
                              fontWeight: FontWeight.bold,
                              color: themeProvider.isDarkMode
                                  ? Colors.white.withOpacity(0.8)
                                  : const Color(0xFF2C5364),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            minFontSize: 14,
                            maxFontSize: 22,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCalendars.length,
                        itemBuilder: (context, index) {
                          final data = _filteredCalendars[index];
                          final isMine = data['ownerId'] == _userId;
                          final name = data['name'] ?? 'Sans nom';
                          final description = data.containsKey('description')
                              ? data['description'] ?? ''
                              : '';
                          final inviteCode = data['inviteCode'] ?? '';
                          final calendarId = data['calendarId'];
                          final isPinned =
                              _pinnedCalendars.contains(calendarId);

                          return Dismissible(
                            key: Key(calendarId),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              color: isPinned ? Colors.red : Colors.amber,
                              padding: EdgeInsets.symmetric(horizontal: 20),
                              child: Icon(
                                isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (_) async {
                              setState(() {
                                _filteredCalendars.removeAt(index);
                              });
                              await _togglePin(calendarId);
                              await _fetchCalendars();
                            },
                            child: Card(
                              margin: EdgeInsets.symmetric(
                                  horizontal: screenWidth * 0.04,
                                  vertical: screenWidth * 0.025),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      screenWidth * 0.045)),
                              elevation: 4,
                              color: themeProvider.isDarkMode
                                  ? Colors.grey[800]
                                  : Colors.white,
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                    vertical: screenWidth * 0.02,
                                    horizontal: screenWidth * 0.03),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isMine
                                              ? Icons.lock_person
                                              : Icons.lock_open,
                                          color: isMine
                                              ? (themeProvider.isDarkMode
                                                  ? Colors.green[300]
                                                  : Colors.green[700])
                                              : (themeProvider.isDarkMode
                                                  ? Colors.deepPurple[300]
                                                  : Colors.deepPurple[700]),
                                          size: screenWidth * 0.07,
                                        ),
                                        SizedBox(width: screenWidth * 0.02),
                                        Flexible(
                                          child: AutoSizeText(
                                            name,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: screenWidth * 0.045,
                                              color: themeProvider.isDarkMode
                                                  ? Colors.white
                                                  : const Color(0xFF2C5364),
                                            ),
                                            maxLines: 1,
                                            minFontSize: 12,
                                            maxFontSize: 18,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isPinned)
                                          Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Icon(Icons.push_pin,
                                                color: Colors.amber, size: 20),
                                          ),
                                        Spacer(),
                                        ElevatedButton.icon(
                                          icon: Icon(Icons.arrow_forward,
                                              color: Colors.white, size: 18),
                                          label: Text(
                                            "S'y rendre",
                                            style: TextStyle(
                                              fontSize: screenWidth * 0.035,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                themeProvider.isDarkMode
                                                    ? const Color(0xFF2C5364)
                                                    : const Color(0xFF1976D2),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      screenWidth * 0.03),
                                            ),
                                            padding: EdgeInsets.symmetric(
                                              vertical: screenWidth * 0.012,
                                              horizontal: screenWidth * 0.018,
                                            ),
                                            minimumSize: Size(
                                                screenWidth * 0.01,
                                                screenWidth * 0.01),
                                          ),
                                          onPressed: () {
                                            Navigator.pushNamed(
                                              context,
                                              '/private_calendar',
                                              arguments: {
                                                'calendarId': calendarId,
                                                'calendarName': name,
                                                'ownerId': data['ownerId'],
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    if (description.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(
                                            top: screenWidth * 0.01),
                                        child: AutoSizeText(
                                          description,
                                          style: TextStyle(
                                            color: themeProvider.isDarkMode
                                                ? Colors.white70
                                                : Colors.black87,
                                            fontSize: screenWidth * 0.035,
                                          ),
                                          maxLines: 2,
                                          minFontSize: 10,
                                          maxFontSize: 14,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if (inviteCode.isNotEmpty)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: IconButton(
                                          icon: Icon(Icons.copy,
                                              color: themeProvider.isDarkMode
                                                  ? Colors.blue[300]
                                                  : const Color(0xFF1976D2)),
                                          tooltip: "Copier le code d'accès",
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(
                                                text: inviteCode));
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    "Code copié dans le presse-papier !"),
                                                backgroundColor: Colors.blue,
                                              ),
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
                      ),
          ),
        ],
      ),
    );
  }
}
