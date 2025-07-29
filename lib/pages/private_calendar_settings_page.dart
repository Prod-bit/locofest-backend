import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class PrivateCalendarSettingsPage extends StatefulWidget {
  final String calendarId;
  final String calendarName;
  final bool isOwner;
  final bool fromProfileManagement;

  const PrivateCalendarSettingsPage({
    Key? key,
    required this.calendarId,
    required this.calendarName,
    required this.isOwner,
    this.fromProfileManagement = false,
  }) : super(key: key);

  @override
  State<PrivateCalendarSettingsPage> createState() =>
      _PrivateCalendarSettingsPageState();
}

class _PrivateCalendarSettingsPageState
    extends State<PrivateCalendarSettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _pseudoController = TextEditingController();
  bool _canalAllowMembers = true;
  bool _initialized = false;
  String? _changeNameError;
  String? _pseudo;
  String? _role;
  String? _subscriptionStatus;

  // Champs pour l'ajout d'événement privé
  bool _showAddEventDialog = false;
  final TextEditingController _eventTitleController = TextEditingController();
  final TextEditingController _eventDateController = TextEditingController();
  final TextEditingController _eventTimeController = TextEditingController();
  final TextEditingController _eventLocationController =
      TextEditingController();
  final TextEditingController _eventDescController = TextEditingController();
  final TextEditingController _eventCategoryController =
      TextEditingController();
  DateTime? _selectedEventDate;
  TimeOfDay? _selectedEventTime;
  List<XFile> _selectedImages = [];

  static const Color mainBlue = Color(0xFF1976D2);
  static const Color mainBlueLight = Color(0xFF64B5F6);
  static const Color mainBlueBg = Color(0xFFE0F7FA);
  static const Color dangerRed = Color(0xFFE53935);

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.calendarName;
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      setState(() {
        _pseudo = doc.data()?['pseudo'] ?? '';
        _role = doc.data()?['role'] ?? '';
        _subscriptionStatus = doc.data()?['subscriptionStatus'] ?? '';
        _pseudoController.text = _pseudo ?? '';
      });
    }
  }

  Future<void> _savePseudo() async {
    final user = FirebaseAuth.instance.currentUser;
    final newPseudo = _pseudoController.text.trim();
    if (user != null && newPseudo.isNotEmpty) {
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('pseudo', isEqualTo: newPseudo)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty && existing.docs.first.id != user.uid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Ce pseudo est déjà utilisé. Merci d'en choisir un autre."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'pseudo': newPseudo});
      setState(() {
        _pseudo = newPseudo;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Pseudo modifié !"), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _saveSettings() async {
    final docRef = FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId);
    final docSnap = await docRef.get();
    final mapData = docSnap.data() ?? <String, dynamic>{};
    List<dynamic> timestamps = mapData['nameChangeTimestamps'] ?? [];

    final now = DateTime.now();
    timestamps = timestamps
        .where(
            (ts) => ts is Timestamp && now.difference(ts.toDate()).inDays < 7)
        .toList();

    if (timestamps.length >= 2 &&
        _nameController.text.trim() !=
            (mapData['name'] ?? widget.calendarName)) {
      setState(() {
        _changeNameError =
            "Vous ne pouvez changer le nom que 2 fois par semaine.";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Limite atteinte : vous ne pouvez changer le nom que 2 fois par semaine."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_nameController.text.trim() !=
        (mapData['name'] ?? widget.calendarName)) {
      timestamps.add(Timestamp.now());
    }

    await docRef.update({
      'name': _nameController.text.trim(),
      'canalAllowMembers': _canalAllowMembers,
      'nameChangeTimestamps': timestamps,
    });
    if (!mounted) return;
    setState(() {
      _changeNameError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Paramètres enregistrés !"),
          backgroundColor: Colors.green),
    );
  }

  Future<void> _handleLogout() async {
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
            child: const Text("Oui, se déconnecter"),
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
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  Future<void> _addPrivateEvent() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);

    int maxEvents = 4;
    if (_role == 'premium') maxEvents = 70;
    if (_role == 'boss') maxEvents = 999999;

    final eventsQuery = await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .where('creatorId', isEqualTo: userId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(firstDayOfMonth))
        .get();

    if (eventsQuery.docs.length >= maxEvents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Limite atteinte : vous ne pouvez créer que $maxEvents événements privés ce mois-ci."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!widget.isOwner && _role != 'premium' && _role != 'boss') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Seuls le propriétaire ou les membres premium/boss peuvent ajouter un événement."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final title = _eventTitleController.text.trim();
    final desc = _eventDescController.text.trim();
    final location = _eventLocationController.text.trim();
    final category = _eventCategoryController.text.trim();
    final date = _selectedEventDate;
    final time = _selectedEventTime;
    if (title.isEmpty || date == null || time == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Veuillez remplir tous les champs obligatoires."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final eventDate = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    List<String> imageUrls = [];
    for (final img in _selectedImages) {
      final ref = FirebaseStorage.instance.ref().child(
          'private_event_images/${FirebaseAuth.instance.currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}_${img.name}');
      UploadTask uploadTask = ref.putFile(File(img.path));
      TaskSnapshot snapshot = await uploadTask;
      String url = await snapshot.ref.getDownloadURL();
      imageUrls.add(url);
    }
    await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .collection('events')
        .add({
      'title': title,
      'description': desc,
      'location': location,
      'category': category,
      'date': Timestamp.fromDate(eventDate),
      'creatorId': FirebaseAuth.instance.currentUser!.uid,
      'createdAt': Timestamp.now(),
      'images': imageUrls,
      'participants': [],
      'likes': [],
      'views': {},
    });
    if (!mounted) return;
    setState(() {
      _showAddEventDialog = false;
      _eventTitleController.clear();
      _eventDateController.clear();
      _eventTimeController.clear();
      _eventLocationController.clear();
      _eventDescController.clear();
      _eventCategoryController.clear();
      _selectedEventDate = null;
      _selectedEventTime = null;
      _selectedImages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Événement privé ajouté !"),
        backgroundColor: Colors.green,
      ),
    );
  }

  Widget _buildAddEventDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth < 400 ? screenWidth * 0.97 : 370.0;
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: SingleChildScrollView(
          child: Container(
            width: dialogWidth,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
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
                Text("Ajouter un événement privé",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 16),
                TextField(
                  controller: _eventTitleController,
                  decoration: const InputDecoration(
                    labelText: "Titre de l'événement",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedEventDate ?? DateTime.now(),
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
                      decoration: const InputDecoration(
                        labelText: "Date (AAAA/MM/JJ)",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () async {
                    TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: _selectedEventTime ?? TimeOfDay.now(),
                      builder: (context, child) {
                        return Localizations.override(
                          context: context,
                          locale: const Locale('fr', 'FR'),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedEventTime = picked;
                        _eventTimeController.text = picked.format(context);
                      });
                    }
                  },
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _eventTimeController,
                      decoration: const InputDecoration(
                        labelText: "Heure (ex: 18:30)",
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.access_time),
                      ),
                      readOnly: true,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _eventLocationController,
                  decoration: const InputDecoration(
                    labelText: "Lieu",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _eventDescController,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _eventCategoryController,
                  decoration: const InputDecoration(
                    labelText: "Catégorie (concert, soirée, etc.)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Photos de l'événement (optionnel)",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ..._selectedImages.map((img) => Stack(
                          alignment: Alignment.topRight,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
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
                                  _selectedImages.remove(img);
                                });
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close,
                                    color: Colors.white, size: 18),
                              ),
                            ),
                          ],
                        )),
                    GestureDetector(
                      onTap: () async {
                        final picker = ImagePicker();
                        final picked =
                            await picker.pickImage(source: ImageSource.gallery);
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
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Icon(Icons.add_a_photo, color: Colors.grey[700]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAddEventDialog = false;
                          _eventTitleController.clear();
                          _eventDateController.clear();
                          _eventTimeController.clear();
                          _eventLocationController.clear();
                          _eventDescController.clear();
                          _eventCategoryController.clear();
                          _selectedEventDate = null;
                          _selectedEventTime = null;
                          _selectedImages.clear();
                        });
                      },
                      child: const Text("Annuler"),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addPrivateEvent,
                      child: const Text("Enregistrer"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final bool _isDarkMode = themeProvider.isDarkMode;
    final user = FirebaseAuth.instance.currentUser;
    final bool isPremium =
        _role == 'premium' && _subscriptionStatus == 'active';
    final bool isBoss = _role == 'boss';

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;

    return Stack(
      children: [
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('private_calendars')
              .doc(widget.calendarId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final mapData = (snapshot.data!.data() as Map<String, dynamic>?) ??
                <String, dynamic>{};

            if (!_initialized && mapData.isNotEmpty) {
              _nameController.text = mapData['name'] ?? widget.calendarName;
              _canalAllowMembers = mapData['canalAllowMembers'] ?? true;
              _initialized = true;
            }

            return Scaffold(
              backgroundColor:
                  _isDarkMode ? const Color(0xFF1A252F) : mainBlueBg,
              appBar: AppBar(
                backgroundColor:
                    _isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
                elevation: 0,
                leading: null,
                automaticallyImplyLeading: false,
                title: Text(
                  "Paramètres du calendrier",
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white : mainBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: titleFontSize,
                    letterSpacing: 1,
                  ),
                ),
                centerTitle: true,
              ),
              body: SingleChildScrollView(
                padding:
                    EdgeInsets.symmetric(horizontal: cardPadding, vertical: 0),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(cardPadding),
                  decoration: BoxDecoration(
                    color: _isDarkMode ? Colors.grey[800] : Colors.white,
                    borderRadius: BorderRadius.circular(0),
                    boxShadow: [
                      BoxShadow(
                        color: _isDarkMode
                            ? Colors.black38
                            : mainBlue.withOpacity(0.08),
                        blurRadius: 32,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: screenWidth * 0.3,
                        height: screenWidth * 0.3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              _isDarkMode
                                  ? mainBlue.withOpacity(0.5)
                                  : mainBlue.withOpacity(0.3),
                              _isDarkMode ? mainBlue : mainBlue,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isDarkMode
                                  ? Colors.black26
                                  : mainBlue.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.lock_person,
                            size: 80, color: Colors.white),
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.light_mode,
                              color: !_isDarkMode ? mainBlue : Colors.grey,
                              size: 22),
                          Switch(
                            value: _isDarkMode,
                            onChanged: (val) {
                              themeProvider.toggleTheme(val);
                            },
                            activeColor: mainBlue,
                            inactiveThumbColor: Colors.grey,
                          ),
                          Icon(Icons.dark_mode,
                              color: _isDarkMode ? mainBlue : Colors.grey,
                              size: 22),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.01),
                      Center(
                        child: Text(
                          _nameController.text,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: titleFontSize,
                            color: _isDarkMode ? Colors.white : mainBlue,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.03),
                      Text(
                        "Nom du calendrier privé",
                        style: TextStyle(
                          color:
                              _isDarkMode ? Colors.white70 : Colors.grey[800],
                          fontWeight: FontWeight.w600,
                          fontSize: cardFontSize * 1.1,
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.008),
                      TextField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: "Nom du calendrier",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          prefixIcon: Icon(Icons.edit,
                              color: _isDarkMode ? Colors.white70 : mainBlue),
                          errorText: _changeNameError,
                          filled: true,
                          fillColor:
                              _isDarkMode ? Colors.grey[900] : Colors.grey[100],
                        ),
                        style: TextStyle(
                            fontSize: cardFontSize * 1.1,
                            color: _isDarkMode ? Colors.white : Colors.black87),
                      ),
                      SizedBox(height: screenHeight * 0.03),
                      Padding(
                        padding: EdgeInsets.symmetric(
                            vertical: screenHeight * 0.015),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          color: _isDarkMode
                              ? Colors.blueGrey[900]
                              : Colors.blue[50],
                          child: Padding(
                            padding: EdgeInsets.all(cardPadding),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.forum, color: mainBlue),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        "Écriture dans le canal",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: cardFontSize * 0.92,
                                          color: mainBlue,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: screenHeight * 0.01),
                                Text(
                                  "Autoriser les membres à écrire dans le canal ?",
                                  style: TextStyle(
                                    color: _isDarkMode
                                        ? Colors.white70
                                        : Colors.grey[800],
                                    fontSize: cardFontSize * 0.92,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: screenHeight * 0.018),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 110,
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.check_circle,
                                            color: _canalAllowMembers
                                                ? Colors.white
                                                : mainBlue),
                                        label: Text("Autoriser"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _canalAllowMembers
                                              ? mainBlue
                                              : (_isDarkMode
                                                  ? Colors.grey[800]
                                                  : Colors.white),
                                          foregroundColor: _canalAllowMembers
                                              ? Colors.white
                                              : mainBlue,
                                          elevation: _canalAllowMembers ? 4 : 0,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        onPressed: () {
                                          setState(
                                              () => _canalAllowMembers = true);
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      width: 110,
                                      child: ElevatedButton.icon(
                                        icon: Icon(Icons.block,
                                            color: !_canalAllowMembers
                                                ? Colors.white
                                                : mainBlue),
                                        label: Text("Interdire"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: !_canalAllowMembers
                                              ? dangerRed
                                              : (_isDarkMode
                                                  ? Colors.grey[800]
                                                  : Colors.white),
                                          foregroundColor: !_canalAllowMembers
                                              ? Colors.white
                                              : dangerRed,
                                          elevation:
                                              !_canalAllowMembers ? 4 : 0,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12)),
                                        ),
                                        onPressed: () {
                                          setState(
                                              () => _canalAllowMembers = false);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(bottom: screenHeight * 0.015),
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _isDarkMode
                                  ? Colors.white.withOpacity(0.08)
                                  : Colors.blue.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: EdgeInsets.symmetric(
                                horizontal: cardPadding * 2, vertical: 8),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.blueAccent, size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "Appuyez sur « Enregistrer » pour valider vos modifications.",
                                    style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontSize: cardFontSize,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _saveSettings,
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text("Enregistrer"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isDarkMode ? mainBlue : mainBlue,
                            foregroundColor: Colors.white,
                            minimumSize: Size(0, screenHeight * 0.06),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.04),
                      Divider(
                          height: screenHeight * 0.04,
                          color: _isDarkMode
                              ? Colors.grey[700]
                              : Colors.grey[300]),
                      Center(
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: screenWidth * 0.085,
                              backgroundColor: _isDarkMode
                                  ? mainBlue.withOpacity(0.3)
                                  : mainBlue.withOpacity(0.13),
                              child: Icon(Icons.person,
                                  color: mainBlueLight,
                                  size: screenWidth * 0.09),
                            ),
                            SizedBox(height: screenHeight * 0.012),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isBoss)
                                  Icon(Icons.verified,
                                      color: Colors.blue, size: 22),
                                if (isPremium)
                                  Icon(Icons.verified,
                                      color: Colors.amber, size: 22),
                                const SizedBox(width: 6),
                                SizedBox(
                                  width: screenWidth * 0.4,
                                  child: TextField(
                                    controller: _pseudoController,
                                    decoration: InputDecoration(
                                      hintText: "Pseudo",
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                    ),
                                    style: TextStyle(
                                      color:
                                          _isDarkMode ? Colors.white : mainBlue,
                                      fontWeight: FontWeight.bold,
                                      fontSize: cardFontSize * 1.2,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.save,
                                      color: Colors.green),
                                  tooltip: "Enregistrer le pseudo",
                                  onPressed: _savePseudo,
                                ),
                              ],
                            ),
                            if (user?.email != null)
                              Text(
                                user!.email!,
                                style: TextStyle(
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : Colors.grey[600],
                                  fontSize: cardFontSize,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      SizedBox(height: screenHeight * 0.03),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: FloatingActionButton(
                              heroTag: "addPrivateEventBtn",
                              backgroundColor: mainBlue,
                              child: const Icon(Icons.add, color: Colors.white),
                              tooltip: "Ajouter un événement privé",
                              onPressed: () {
                                setState(() {
                                  _showAddEventDialog = true;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.02),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (isBoss || isPremium)
                            SizedBox(
                              width: 56,
                              height: 56,
                              child: FloatingActionButton(
                                heroTag: "analyse_fab",
                                backgroundColor: Colors.deepPurple,
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    '/private_analyse',
                                    arguments: {
                                      'calendarId': widget.calendarId,
                                      'calendarName': widget.calendarName,
                                    },
                                  );
                                },
                                child: const Icon(Icons.analytics,
                                    color: Colors.white, size: 30),
                                tooltip: "Analyser ce calendrier privé",
                              ),
                            )
                          else
                            const SizedBox(width: 56),
                          SizedBox(
                            width: 56,
                            height: 56,
                            child: FloatingActionButton(
                              heroTag: "premium_fab",
                              backgroundColor: Colors.amber[700],
                              onPressed: () {
                                Navigator.pushNamed(context, '/premium');
                              },
                              child: const Icon(Icons.workspace_premium,
                                  color: Colors.white, size: 30),
                              tooltip: "Passer Premium (certification)",
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: screenHeight * 0.03),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text("Se déconnecter"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isDarkMode ? Colors.white : Colors.white,
                            foregroundColor: _isDarkMode ? mainBlue : mainBlue,
                            side: const BorderSide(color: mainBlue, width: 2),
                            minimumSize: Size(0, screenHeight * 0.06),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _handleLogout,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: 3,
                onTap: (index) async {
                  if (index == 0) {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text("Retour à l'accueil"),
                        content: const Text(
                            "Voulez-vous vraiment quitter ce calendrier et revenir à l'accueil ?"),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text("Annuler",
                                style: TextStyle(
                                    color:
                                        _isDarkMode ? Colors.white : mainBlue)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text("Oui"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isDarkMode ? mainBlue : mainBlue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                        backgroundColor: _isDarkMode
                            ? const Color(0xFF23272F)
                            : Colors.white,
                      ),
                    );
                    if (confirm == true) {
                      Navigator.of(context)
                          .pushNamedAndRemoveUntil('/home', (route) => false);
                    }
                  } else if (index == 1) {
                    Navigator.pushReplacementNamed(
                      context,
                      '/private_calendar',
                      arguments: {
                        'calendarId': widget.calendarId,
                        'calendarName': widget.calendarName,
                        'ownerId': FirebaseAuth.instance.currentUser?.uid,
                      },
                    );
                  } else if (index == 2) {
                    Navigator.pushReplacementNamed(
                      context,
                      '/canal',
                      arguments: {
                        'calendarId': widget.calendarId,
                        'ownerId': FirebaseAuth.instance.currentUser?.uid,
                        'isOwner': widget.isOwner,
                      },
                    );
                  } else if (index == 3) {
                    // On reste sur la page paramètres
                  }
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.lock_clock),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.forum),
                    label: '',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings),
                    label: '',
                  ),
                ],
                showSelectedLabels: false,
                showUnselectedLabels: false,
                selectedItemColor: mainBlue,
                unselectedItemColor:
                    _isDarkMode ? Colors.grey : Colors.grey[600],
                type: BottomNavigationBarType.fixed,
                backgroundColor:
                    _isDarkMode ? const Color(0xFF2A2F32) : Colors.white,
              ),
            );
          },
        ),
        if (_showAddEventDialog) _buildAddEventDialog(),
      ],
    );
  }
}
