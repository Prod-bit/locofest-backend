import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class CityChatPage extends StatefulWidget {
  final String city;
  const CityChatPage({Key? key, required this.city}) : super(key: key);

  @override
  State<CityChatPage> createState() => _CityChatPageState();
}

class _CityChatPageState extends State<CityChatPage> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  late String _city;
  late User? _user;
  Map<String, dynamic>? _userData;
  bool _loadingUser = true;
  bool _isDark = false;

  Map<String, dynamic>? _replyTo;
  bool _sendAnonymously = false;

  Set<String> _animatingHearts = {};

  DateTime? _blockedUntil;
  int? _lastUserMsgCount;
  StreamSubscription<QuerySnapshot>? _deleteListener;
  StreamSubscription<DocumentSnapshot>? _blockListener;

  File? _selectedImage;

  // Pour favoris events
  Set<String> _favoriteEvents = {};

  @override
  void initState() {
    super.initState();
    _city = widget.city;
    _user = FirebaseAuth.instance.currentUser;
    _fetchUserData();
    _fetchFavorites();

    if (_user != null) {
      _blockListener = FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .collection('blockedChats')
          .doc(_city.toLowerCase())
          .snapshots()
          .listen((doc) {
        if (!mounted) return;
        if (doc.exists &&
            doc.data() != null &&
            doc.data()!['blockedUntil'] != null) {
          final until = (doc.data()!['blockedUntil'] as Timestamp).toDate();
          if (!mounted) return;
          setState(() {
            _blockedUntil = until;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _blockedUntil = null;
          });
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_user != null) {
        _deleteListener = FirebaseFirestore.instance
            .collection('city_chats')
            .doc(_city.toLowerCase())
            .collection('messages')
            .where('authorId', isEqualTo: _user!.uid)
            .snapshots()
            .listen((snapshot) async {
          if (!mounted) return;
          if (_lastUserMsgCount != null &&
              snapshot.docs.length < _lastUserMsgCount!) {
            if (_userData != null && _userData!['role'] != 'boss') {
              final blockedUntil = DateTime.now().add(Duration(minutes: 10));
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_user!.uid)
                  .collection('blockedChats')
                  .doc(_city.toLowerCase())
                  .set({'blockedUntil': Timestamp.fromDate(blockedUntil)});
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Un admin a supprimé votre message. Vous ne pouvez plus écrire dans ce chat pendant 10 minutes.",
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
              );
            }
          }
          _lastUserMsgCount = snapshot.docs.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _deleteListener?.cancel();
    _blockListener?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _fetchUserData() async {
    if (_user == null) {
      if (!mounted) return;
      setState(() {
        _loadingUser = false;
      });
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .get();
    if (!mounted) return;
    if (doc.exists) {
      setState(() {
        _userData = doc.data();
        _loadingUser = false;
      });
    } else {
      setState(() {
        _userData = null;
        _loadingUser = false;
      });
    }
  }

  Future<void> _fetchFavorites() async {
    if (_user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('favorites')
        .get();
    setState(() {
      _favoriteEvents = snap.docs.map((d) => d.id).toSet();
    });
  }

  Future<void> _toggleFavorite(String eventId) async {
    if (_user == null) return;
    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_user!.uid)
        .collection('favorites')
        .doc(eventId);
    if (_favoriteEvents.contains(eventId)) {
      await favRef.delete();
      setState(() {
        _favoriteEvents.remove(eventId);
      });
    } else {
      await favRef.set({'addedAt': FieldValue.serverTimestamp()});
      setState(() {
        _favoriteEvents.add(eventId);
      });
    }
  }

  Future<void> _sendMessage(
      {Map<String, dynamic>? event, String? imageUrl}) async {
    if ((_controller.text.trim().isEmpty &&
            event == null &&
            imageUrl == null &&
            _selectedImage == null) ||
        _user == null ||
        _userData == null) {
      return;
    }
    if (!mounted) return;
    setState(() {
      _sending = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection('city_chats')
          .doc(_city.toLowerCase())
          .collection('messages')
          .add({
        if (event == null && imageUrl == null) 'text': _controller.text.trim(),
        if (event != null) 'text': 'Événement partagé',
        if (event != null)
          'event': {
            ...event,
            'id': event['id'] ?? event['eventId'],
          },
        if (imageUrl != null) 'imageUrl': imageUrl,
        'authorId': _user!.uid,
        'authorPseudo': ((_userData?['role'] == 'boss') ||
                    (_userData?['role'] == 'premium' &&
                        _userData?['subscriptionStatus'] == 'active')) &&
                _sendAnonymously
            ? "Anonyme"
            : (_userData?['pseudo'] ?? 'Utilisateur'),
        'authorRole': _userData?['role'] ?? 'user',
        'authorCertif': _userData?['role'] == 'boss' ||
                (_userData?['role'] == 'premium' &&
                    _userData?['subscriptionStatus'] == 'active')
            ? true
            : false,
        'timestamp': FieldValue.serverTimestamp(),
        'likes': <String>[],
        if (_replyTo != null && _replyTo?['imageUrl'] == null)
          'replyTo': {
            'authorPseudo': _replyTo?['authorPseudo'] ?? '',
            'authorRole': _replyTo?['authorRole'] ?? 'user',
            'authorCertif': _replyTo?['authorCertif'] ?? false,
            'text': _replyTo?['text'] ?? '',
          }
      });
      _controller.clear();
      if (!mounted) return;
      setState(() {
        _replyTo = null;
        _selectedImage = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'envoi : $e")),
      );
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
    });
  }

  Future<void> _pickImage() async {
    if (_userData == null ||
        !(_userData?['role'] == 'boss' ||
            (_userData?['role'] == 'premium' &&
                _userData?['subscriptionStatus'] == 'active'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Seuls les membres premium ou boss peuvent envoyer des images."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<void> _sendSelectedImage() async {
    if (_selectedImage == null) return;
    setState(() {
      _sending = true;
    });
    try {
      final compressedBytes = await FlutterImageCompress.compressWithFile(
        _selectedImage!.path,
        minWidth: 1080,
        minHeight: 1080,
        quality: 70,
      );
      File fileToUpload = _selectedImage!;
      if (compressedBytes != null) {
        final tempPath = _selectedImage!.path + '_compressed.jpg';
        fileToUpload = await File(tempPath).writeAsBytes(compressedBytes);
      }
      final ref = FirebaseStorage.instance.ref().child(
          'city_chat_images/${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}');
      final uploadTask = ref.putFile(fileToUpload);
      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      await _sendMessage(imageUrl: url);
      setState(() {
        _selectedImage = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur lors de l'envoi de l'image : $e")),
      );
    }
    setState(() {
      _sending = false;
    });
  }

  void _toggleLike(
      DocumentReference msgRef, List<dynamic> likes, String msgId) async {
    if (_user == null) return;
    final uid = _user!.uid;
    final isLiked = likes.contains(uid);

    // Haptique à chaque like/delike
    HapticFeedback.lightImpact();

    setState(() {
      _animatingHearts.add(msgId);
    });

    await msgRef.update({
      'likes':
          isLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid])
    });

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() {
      _animatingHearts.remove(msgId);
    });
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'boss':
        return Colors.blue;
      case 'premium':
        return Colors.amber[700]!;
      case 'organizer':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Cœur SOUS la bulle, aligné à GAUCHE (sous le texte, pas centré)
  Widget buildLikeRow(int likeCount, bool isLiked) {
    if (likeCount == 0 && !isLiked) return SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 18, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite, color: Colors.red, size: 22),
          if (likeCount > 0)
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                likeCount.toString(),
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Pour la popup event : gestion inscription/désinscription + FAVORI (pas like)
  Future<bool> _isUserParticipating(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final docs = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: eventId)
        .where('userId', isEqualTo: user.uid)
        .get();
    return docs.docs.isNotEmpty;
  }

  Color _heartColor(String role) {
    switch (role) {
      case 'boss':
        return Colors.blue;
      case 'premium':
        return Colors.amber;
      case 'organizer':
        return Colors.green;
      default:
        return Colors.red;
    }
  }

  Icon? _certifIcon(String role, bool certif) {
    if (role == 'boss') {
      return const Icon(Icons.verified, color: Colors.blue, size: 16);
    }
    if (role == 'premium' && certif) {
      return Icon(Icons.verified, color: Colors.amber[700], size: 16);
    }
    return null;
  }

  Future<List<String>> _getLikeRoles(List<dynamic> likes) async {
    Set<String> roles = {};
    for (var uid in likes) {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        roles.add(doc['role'] ?? 'user');
      }
    }
    return roles.toList();
  }

  Future<void> _registerEventView(Map<String, dynamic> eventData) async {
    final user = FirebaseAuth.instance.currentUser;
    final eventId = eventData['id'] ?? eventData['eventId'];
    if (user != null && eventId != null) {
      final viewsRef = FirebaseFirestore.instance.collection('event_views');
      final existing = await viewsRef
          .where('eventId', isEqualTo: eventId)
          .where('userId', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (existing.docs.isEmpty) {
        await viewsRef.add({
          'eventId': eventId,
          'userId': user.uid,
          'timestamp': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  void _showEventPopup(Map<String, dynamic> eventData) async {
    await _registerEventView(eventData);
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final primaryColor =
            _isDark ? Color(0xFF34AADC) : Theme.of(context).primaryColor;
        final screenWidth = MediaQuery.of(context).size.width;
        final double dialogFontSize = screenWidth * 0.045;
        final double dialogTitleSize = screenWidth * 0.052;
        final double dialogRadius = screenWidth * 0.045;
        final eventId = eventData['id'] ?? eventData['eventId'];
        return StatefulBuilder(
          builder: (context, setStatePopup) => Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(dialogRadius * 1.2),
            ),
            backgroundColor: _isDark ? Colors.grey[900] : Color(0xFFEAF4FF),
            child: Padding(
              padding: EdgeInsets.all(screenWidth * 0.045),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    eventData['title'] ?? 'Sans titre',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: dialogTitleSize,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                              ),
                              if ((eventData['creatorRole'] ??
                                      eventData['role']) ==
                                  'boss')
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.verified_user,
                                      color: Colors.blue, size: dialogFontSize),
                                )
                              else if ((eventData['creatorRole'] ??
                                      eventData['role']) ==
                                  'premium')
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.verified,
                                      color: Colors.amber,
                                      size: dialogFontSize),
                                ),
                            ],
                          ),
                        ),
                        if (eventData['city'] != null &&
                            eventData['city'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: dialogFontSize * 0.9,
                                    color: Colors.blue),
                                SizedBox(width: 4),
                                SizedBox(
                                  width: screenWidth * 0.22,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      eventData['city'],
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: dialogFontSize * 0.95,
                                        color: _isDark
                                            ? Colors.blue[100]
                                            : Colors.blue[900],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        IconButton(
                          icon: Icon(Icons.close,
                              color:
                                  _isDark ? Colors.white54 : Colors.grey[700]),
                          onPressed: () => Navigator.pop(context),
                          tooltip: "Fermer",
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: dialogFontSize * 0.9, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Date : ${_formatDate((eventData['date'] as Timestamp).toDate())}",
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: dialogFontSize * 0.95,
                                  color: _isDark
                                      ? Colors.white70
                                      : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.place,
                            size: dialogFontSize * 0.9, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Lieu : ${eventData['location'] ?? 'Non spécifié'}",
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: dialogFontSize * 0.95,
                                  color: _isDark
                                      ? Colors.white70
                                      : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.category,
                            size: dialogFontSize * 0.9, color: primaryColor),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Catégorie : ${eventData['category'] ?? 'Non spécifiée'}",
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: dialogFontSize * 0.95,
                                  color: _isDark
                                      ? Colors.white70
                                      : Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Description :",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: dialogFontSize * 0.95,
                        color: _isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      eventData['description'] ?? 'Aucune description',
                      style: TextStyle(
                        fontSize: dialogFontSize * 0.95,
                        color: _isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (eventData['images'] != null &&
                        eventData['images'] is List &&
                        (eventData['images'] as List).isNotEmpty)
                      _EventImageCarousel(
                          images: List<String>.from(eventData['images'])),
                    SizedBox(height: 16),
                    FutureBuilder<bool>(
                      future: _isUserParticipating(eventId),
                      builder: (context, snap) {
                        final isParticipating = snap.data == true;
                        return Column(
                          children: [
                            SizedBox(
                              width: 160,
                              height: 38,
                              child: ElevatedButton.icon(
                                icon: Icon(
                                  isParticipating
                                      ? Icons.cancel
                                      : Icons.event_available,
                                  size: dialogFontSize * 1.1,
                                ),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isParticipating
                                        ? "Se désinscrire"
                                        : "Participer",
                                    style: TextStyle(
                                      fontSize: dialogFontSize * 0.95,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isParticipating
                                      ? Colors.red
                                      : Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        dialogRadius * 0.7),
                                  ),
                                ),
                                onPressed: () async {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  if (user == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              "Connectez-vous pour participer.")),
                                    );
                                    return;
                                  }
                                  final partRef = FirebaseFirestore.instance
                                      .collection('event_participations');
                                  if (isParticipating) {
                                    final docs = await partRef
                                        .where('eventId', isEqualTo: eventId)
                                        .where('userId', isEqualTo: user.uid)
                                        .get();
                                    for (var d in docs.docs) {
                                      await d.reference.delete();
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              "Désinscription enregistrée !")),
                                    );
                                  } else {
                                    await partRef.add({
                                      'eventId': eventId,
                                      'userId': user.uid,
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              "Participation enregistrée !")),
                                    );
                                  }
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(_user?.uid)
                                    .collection('favorites')
                                    .doc(eventId)
                                    .get(),
                                builder: (context, snapshot) {
                                  final isFav =
                                      snapshot.hasData && snapshot.data!.exists;
                                  return IconButton(
                                    icon: Icon(
                                      isFav
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: Colors.red,
                                      size: dialogFontSize * 1.3,
                                    ),
                                    tooltip: isFav
                                        ? "Retirer des favoris"
                                        : "Ajouter aux favoris",
                                    onPressed: () async {
                                      await _toggleFavorite(eventId);
                                      setStatePopup(() {});
                                    },
                                  );
                                },
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
          ),
        );
      },
    );
  }

  Future<void> _deleteMessage(DocumentReference msgRef,
      {bool isAdmin = false, String? authorId}) async {
    try {
      await msgRef.delete();
      if (isAdmin && authorId != null) {
        final authorDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(authorId)
            .get();
        final authorRole = authorDoc.data()?['role'] ?? 'user';
        if (authorRole != 'boss') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(authorId)
              .collection('blockedChats')
              .doc(_city.toLowerCase())
              .set({
            'blockedUntil':
                Timestamp.fromDate(DateTime.now().add(Duration(minutes: 10))),
          });
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "L'utilisateur est bloqué 10 minutes dans ce chat.",
                style:
                    TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Message supprimé."),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Message supprimé."),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Erreur lors de la suppression : $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final double bubbleMaxWidth = screenWidth * 0.75;
    final double bubbleFontSize = screenWidth * 0.040;
    final double bubbleSmallFont = screenWidth * 0.034;
    final double bubbleRadius = screenWidth * 0.045;
    final double imageHeight = screenWidth < 400 ? 140 : 180;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor:
            _isDark ? const Color(0xFF1A252F) : const Color(0xFFF5F5F5),
        appBar: AppBar(
          backgroundColor:
              _isDark ? const Color(0xFF1565C0) : const Color(0xFF2196F3),
          elevation: 2,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: "Messagerie générale",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.045,
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: " – ",
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w400,
                    fontSize: screenWidth * 0.045,
                  ),
                ),
                TextSpan(
                  text: _city[0].toUpperCase() + _city.substring(1),
                  style: TextStyle(
                    color: Colors.amber[200],
                    fontWeight: FontWeight.bold,
                    fontSize: screenWidth * 0.045,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false,
          actions: [
            if (_userData != null && _userData!['role'] == 'boss')
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('city_chats')
                    .doc(_city.toLowerCase())
                    .collection('online')
                    .snapshots(),
                builder: (context, snapshot) {
                  final count =
                      snapshot.hasData ? snapshot.data!.docs.length : 0;
                  return Row(
                    children: [
                      Icon(Icons.circle, color: Colors.green, size: 13),
                      const SizedBox(width: 6),
                      Text(
                        "membres en ligne",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: screenWidth * 0.034,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "$count",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: screenWidth * 0.036,
                        ),
                      ),
                      const SizedBox(width: 16),
                    ],
                  );
                },
              ),
          ],
        ),
        body: Column(
          children: [
            if (_userData != null &&
                (_userData!['role'] == 'boss' ||
                    (_userData!['role'] == 'premium' &&
                        _userData!['subscriptionStatus'] == 'active')))
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_off, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _sendAnonymously
                            ? "Vous envoyez des messages en anonyme"
                            : "Envoyer en anonyme",
                        style: TextStyle(
                          color: _isDark ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                          fontSize: bubbleFontSize,
                        ),
                      ),
                    ),
                    Switch(
                      value: _sendAnonymously,
                      activeColor: Colors.amber,
                      onChanged: (val) {
                        setState(() {
                          _sendAnonymously = val;
                        });
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('city_chats')
                    .doc(_city.toLowerCase())
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .limit(100)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Erreur de chargement : ${snapshot.error}'),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;
                  if (docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 54, color: Colors.grey[400]),
                          const SizedBox(height: 24),
                          Text(
                            "Aucun message pour l’instant",
                            style: TextStyle(
                              fontSize: screenWidth * 0.05,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Commencez la conversation.",
                            style: TextStyle(
                              fontSize: screenWidth * 0.04,
                              color: Colors.grey[500],
                              fontWeight: FontWeight.w400,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(
                        vertical: 8, horizontal: screenWidth * 0.01),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final pseudo = data['authorPseudo'] ?? 'Utilisateur';
                      final role = data['authorRole'] ?? 'user';
                      final certif = data['authorCertif'] ?? false;
                      final text = data['text'] ?? '';
                      final ts = data['timestamp'] as Timestamp?;
                      final date = ts != null ? ts.toDate() : DateTime.now();
                      final isMe =
                          _user != null && data['authorId'] == _user!.uid;
                      final replyTo = data['replyTo'] as Map<String, dynamic>?;
                      final msgRef = docs[i].reference;
                      final likes = data['likes'] ?? [];
                      final likeCount = likes.length;
                      final isLiked =
                          _user != null && likes.contains(_user!.uid);
                      final msgId = docs[i].id;
                      final eventData = data['event'] as Map<String, dynamic>?;

                      Widget bubble = eventData != null
                          ? ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: bubbleMaxWidth,
                              ),
                              child: Container(
                                margin: EdgeInsets.only(
                                  left: isMe ? screenWidth * 0.11 : 8,
                                  right: isMe ? 8 : screenWidth * 0.11,
                                  top: 10,
                                  bottom: 10,
                                ),
                                padding: EdgeInsets.symmetric(
                                    vertical: screenWidth * 0.025,
                                    horizontal: screenWidth * 0.035),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? (_isDark
                                          ? Colors.blue[700]
                                          : Colors.blue[100])
                                      : (_isDark
                                          ? Colors.blueGrey[800]
                                          : Colors.blue[50]),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(bubbleRadius),
                                    topRight: Radius.circular(bubbleRadius),
                                    bottomLeft: Radius.circular(
                                        isMe ? bubbleRadius : 6),
                                    bottomRight: Radius.circular(
                                        isMe ? 6 : bubbleRadius),
                                  ),
                                ),
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(bubbleRadius),
                                  onTap: () async {
                                    await _registerEventView(eventData);
                                    _showEventPopup(eventData);
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                data['authorPseudo'] ??
                                                    'Utilisateur',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.blue[900],
                                                  fontSize: bubbleSmallFont,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          if (data['authorRole'] == 'boss')
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 2),
                                              child: Icon(Icons.verified,
                                                  color: Colors.blue,
                                                  size: bubbleSmallFont),
                                            )
                                          else if (data['authorRole'] ==
                                                  'premium' &&
                                              (data['authorCertif'] ?? false))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 2),
                                              child: Icon(Icons.verified,
                                                  color: Colors.amber,
                                                  size: bubbleSmallFont),
                                            ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                "a partagé un événement",
                                                style: TextStyle(
                                                  color: _isDark
                                                      ? Colors.white70
                                                      : Colors.blueGrey,
                                                  fontSize:
                                                      bubbleSmallFont * 0.95,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          eventData['title'] ?? '',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue[900],
                                            fontSize: bubbleFontSize,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.category,
                                            size: bubbleSmallFont,
                                            color: _isDark
                                                ? Colors.white70
                                                : Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                eventData['category'] ?? '',
                                                style: TextStyle(
                                                  fontSize: bubbleSmallFont,
                                                  color: _isDark
                                                      ? Colors.white70
                                                      : Colors.blueGrey,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            Icons.calendar_today,
                                            size: bubbleSmallFont,
                                            color: _isDark
                                                ? Colors.white70
                                                : Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                _formatDate((eventData['date']
                                                        as Timestamp)
                                                    .toDate()),
                                                style: TextStyle(
                                                  fontSize: bubbleSmallFont,
                                                  color: _isDark
                                                      ? Colors.white70
                                                      : Colors.blueGrey,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Icon(
                                            Icons.location_on,
                                            size: bubbleSmallFont,
                                            color: _isDark
                                                ? Colors.white70
                                                : Colors.blueGrey,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              alignment: Alignment.centerLeft,
                                              child: Text(
                                                eventData['city'] ?? '',
                                                style: TextStyle(
                                                  fontSize: bubbleSmallFont,
                                                  color: _isDark
                                                      ? Colors.white70
                                                      : Colors.blueGrey,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          : ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: bubbleMaxWidth,
                              ),
                              child: GestureDetector(
                                onHorizontalDragEnd: (details) {
                                  if (details.primaryVelocity != null &&
                                      details.primaryVelocity! > 0 &&
                                      data['imageUrl'] == null) {
                                    setState(() {
                                      _replyTo = data;
                                    });
                                  }
                                },
                                child: Container(
                                  margin: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 12,
                                    bottom: 12,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                      vertical: screenWidth * 0.028,
                                      horizontal: screenWidth * 0.038),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? (_isDark
                                            ? Colors.blue[700]
                                            : Colors.blue[100])
                                        : (_isDark
                                            ? Colors.blueGrey[800]
                                            : const Color(0xFFF5F6FA)),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(bubbleRadius),
                                      topRight: Radius.circular(bubbleRadius),
                                      bottomLeft: Radius.circular(
                                          isMe ? bubbleRadius : 6),
                                      bottomRight: Radius.circular(
                                          isMe ? 6 : bubbleRadius),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (replyTo != null &&
                                          replyTo['text'] != null &&
                                          replyTo['text'].toString().isNotEmpty)
                                        Container(
                                          margin:
                                              const EdgeInsets.only(bottom: 6),
                                          padding: EdgeInsets.symmetric(
                                              horizontal: screenWidth * 0.025,
                                              vertical: screenWidth * 0.015),
                                          decoration: BoxDecoration(
                                            color: isMe
                                                ? (_isDark
                                                    ? Colors.blue[900]
                                                    : Colors.blue[200])
                                                : (_isDark
                                                    ? Colors.blueGrey[900]
                                                    : Colors.grey[200]),
                                            borderRadius: BorderRadius.circular(
                                                bubbleRadius * 0.7),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.reply,
                                                  size: bubbleSmallFont,
                                                  color: _isDark
                                                      ? Colors.white70
                                                      : Colors.grey[600]),
                                              const SizedBox(width: 4),
                                              FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  replyTo['authorPseudo'] ?? '',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: _isDark
                                                        ? Colors.white
                                                        : Colors.grey[700],
                                                    fontSize: bubbleSmallFont,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (_certifIcon(
                                                      replyTo['authorRole'] ??
                                                          '',
                                                      replyTo['authorCertif'] ??
                                                          false) !=
                                                  null) ...[
                                                const SizedBox(width: 2),
                                                _certifIcon(
                                                    replyTo['authorRole'] ?? '',
                                                    replyTo['authorCertif'] ??
                                                        false)!,
                                              ],
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: FittedBox(
                                                  fit: BoxFit.scaleDown,
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Text(
                                                    replyTo['text'],
                                                    style: TextStyle(
                                                      color: _isDark
                                                          ? Colors.white
                                                          : Colors.grey[700],
                                                      fontSize: bubbleSmallFont,
                                                      fontStyle:
                                                          FontStyle.italic,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ),
                                              if (replyTo['imageUrl'] != null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          left: 8),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: Image.network(
                                                      replyTo['imageUrl'],
                                                      width: 32,
                                                      height: 32,
                                                      fit: BoxFit.cover,
                                                      errorBuilder: (c, e, s) =>
                                                          Container(
                                                        width: 32,
                                                        height: 32,
                                                        color: Colors.grey[300],
                                                        child: Icon(
                                                            Icons.broken_image,
                                                            color: Colors.grey,
                                                            size: 16),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!isMe) ...[
                                            Flexible(
                                              child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                alignment: Alignment.centerLeft,
                                                child: Text(
                                                  pseudo,
                                                  style: TextStyle(
                                                    color: _roleColor(role),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: bubbleSmallFont,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            if (_certifIcon(role, certif) !=
                                                null) ...[
                                              const SizedBox(width: 4),
                                              _certifIcon(role, certif)!,
                                            ],
                                            const SizedBox(width: 6),
                                          ],
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              _formatDate(date),
                                              style: TextStyle(
                                                color: _isDark
                                                    ? Colors.white54
                                                    : Colors.grey[600],
                                                fontSize: bubbleSmallFont * 0.9,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      if (data['imageUrl'] != null)
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              vertical: screenWidth * 0.015),
                                          child: GestureDetector(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => Dialog(
                                                  backgroundColor:
                                                      Colors.transparent,
                                                  child: InteractiveViewer(
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                      child: Image.network(
                                                        data['imageUrl'],
                                                        fit: BoxFit.contain,
                                                        errorBuilder:
                                                            (c, e, s) =>
                                                                Container(
                                                          color:
                                                              Colors.grey[300],
                                                          width: imageHeight,
                                                          height: imageHeight,
                                                          child: Icon(
                                                              Icons
                                                                  .broken_image,
                                                              color:
                                                                  Colors.grey,
                                                              size: 60),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: Image.network(
                                                data['imageUrl'],
                                                height: imageHeight,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                                errorBuilder: (c, e, s) =>
                                                    Container(
                                                  height: imageHeight,
                                                  color: Colors.grey[300],
                                                  child: Icon(
                                                      Icons.broken_image,
                                                      color: Colors.grey),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (data['imageUrl'] == null)
                                        GestureDetector(
                                          onDoubleTap: () {
                                            _toggleLike(msgRef, likes, msgId);
                                          },
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              text,
                                              style: TextStyle(
                                                color: isMe
                                                    ? (_isDark
                                                        ? Colors.white
                                                        : Colors.blue[900])
                                                    : (_isDark
                                                        ? Colors.white
                                                        : Colors.black87),
                                                fontSize: bubbleFontSize,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        )
                                      else
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            text,
                                            style: TextStyle(
                                              color: isMe
                                                  ? (_isDark
                                                      ? Colors.white
                                                      : Colors.blue[900])
                                                  : (_isDark
                                                      ? Colors.white
                                                      : Colors.black87),
                                              fontSize: bubbleFontSize,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );

                      // Likes SOUS la bulle, aligné à GAUCHE (sous le texte)
                      return Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                bubble,
                                buildLikeRow(likeCount, isLiked),
                              ],
                            ),
                          ),
                          if (_userData != null && _userData!['role'] == 'boss')
                            IconButton(
                              icon: Icon(Icons.delete,
                                  color: Colors.red[400],
                                  size: bubbleSmallFont * 1.2),
                              tooltip: "Supprimer ce message",
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text("Supprimer ce message ?"),
                                    content:
                                        Text("Cette action est irréversible."),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text("Annuler"),
                                      ),
                                      ElevatedButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text("Supprimer"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await _deleteMessage(
                                    msgRef,
                                    isAdmin: true,
                                    authorId: data['authorId'],
                                  );
                                }
                              },
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_replyTo != null)
              Container(
                width: double.infinity,
                color: _isDark ? Colors.blueGrey[800] : Colors.blue[50],
                padding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.reply,
                        color: _isDark ? Colors.white70 : Colors.grey[700],
                        size: bubbleSmallFont * 1.1),
                    const SizedBox(width: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _replyTo?['authorPseudo'] ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _isDark ? Colors.white : Colors.grey[800],
                          fontSize: bubbleSmallFont,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_certifIcon(_replyTo?['authorRole'] ?? '',
                            _replyTo?['authorCertif'] ?? false) !=
                        null) ...[
                      const SizedBox(width: 2),
                      _certifIcon(_replyTo?['authorRole'] ?? '',
                          _replyTo?['authorCertif'] ?? false)!,
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _replyTo?['text'] ?? '',
                          style: TextStyle(
                            color: _isDark ? Colors.white : Colors.grey[700],
                            fontSize: bubbleSmallFont,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_replyTo?['imageUrl'] != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            _replyTo!['imageUrl'],
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => Container(
                              width: 32,
                              height: 32,
                              color: Colors.grey[300],
                              child: Icon(Icons.broken_image,
                                  color: Colors.grey, size: 16),
                            ),
                          ),
                        ),
                      ),
                    IconButton(
                      icon: Icon(Icons.close, size: bubbleSmallFont * 1.1),
                      onPressed: () {
                        setState(() {
                          _replyTo = null;
                        });
                      },
                    )
                  ],
                ),
              ),
            Container(
              color: _isDark ? Colors.blueGrey[900] : Colors.white,
              padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.03, vertical: 8),
              child: Row(
                children: [
                  if (_userData != null &&
                      (_userData!['role'] == 'boss' ||
                          (_userData!['role'] == 'premium' &&
                              _userData!['subscriptionStatus'] == 'active')))
                    IconButton(
                      icon: Icon(Icons.photo,
                          color: Theme.of(context).primaryColor),
                      onPressed: _sending ? null : _pickImage,
                      tooltip: "Choisir une photo",
                    ),
                  if (_selectedImage != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              _selectedImage!,
                              width: 60,
                              height: 60,
                              fit: BoxFit.cover,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedImage = null;
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
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: _user != null &&
                              !_sending &&
                              !_loadingUser &&
                              (_userData != null &&
                                  _userData!['role'] == 'boss') ||
                          (_blockedUntil == null ||
                              DateTime.now().isAfter(_blockedUntil!)),
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(
                        color: _isDark ? Colors.white : Colors.black87,
                        fontSize: bubbleFontSize,
                      ),
                      decoration: InputDecoration(
                        hintText: _blockedUntil != null &&
                                DateTime.now().isBefore(_blockedUntil!) &&
                                !(_userData != null &&
                                    _userData!['role'] == 'boss')
                            ? "Vous êtes temporairement bloqué suite à une suppression par un admin."
                            : _user == null
                                ? "Connectez-vous pour écrire…"
                                : "Écrire un message…",
                        hintStyle: TextStyle(
                          color: _isDark ? Colors.white54 : Colors.grey[500],
                          fontSize: bubbleFontSize * 0.95,
                        ),
                        filled: true,
                        fillColor:
                            _isDark ? Colors.blueGrey[800] : Colors.grey[100],
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: screenWidth * 0.035,
                            vertical: screenWidth * 0.025),
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(bubbleRadius * 1.1),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setState(() {});
                        if (_blockedUntil != null &&
                            DateTime.now().isBefore(_blockedUntil!) &&
                            !(_userData != null &&
                                _userData!['role'] == 'boss')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Vous êtes temporairement bloqué dans ce chat.",
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                      },
                      onSubmitted: (_) {
                        if (_selectedImage != null) {
                          _sendSelectedImage();
                        } else if (_user != null &&
                                !_sending &&
                                !_loadingUser &&
                                (_userData != null &&
                                    _userData!['role'] == 'boss') ||
                            (_blockedUntil == null ||
                                DateTime.now().isAfter(_blockedUntil!))) {
                          _sendMessage();
                        } else if (_blockedUntil != null &&
                            DateTime.now().isBefore(_blockedUntil!) &&
                            !(_userData != null &&
                                _userData!['role'] == 'boss')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                "Vous êtes temporairement bloqué dans ce chat.",
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                              backgroundColor: Colors.redAccent,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? SizedBox(
                            width: bubbleFontSize * 1.2,
                            height: bubbleFontSize * 1.2,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send_rounded,
                            color: Theme.of(context).primaryColor,
                            size: bubbleFontSize * 1.2),
                    onPressed: (_selectedImage != null)
                        ? _sendSelectedImage
                        : (_user != null &&
                                        !_sending &&
                                        !_loadingUser &&
                                        (_userData != null &&
                                            _userData!['role'] == 'boss') ||
                                    (_blockedUntil == null ||
                                        DateTime.now()
                                            .isAfter(_blockedUntil!))) &&
                                _controller.text.trim().isNotEmpty
                            ? () {
                                _sendMessage();
                              }
                            : () {
                                if (_blockedUntil != null &&
                                    DateTime.now().isBefore(_blockedUntil!) &&
                                    !(_userData != null &&
                                        _userData!['role'] == 'boss')) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        "Vous êtes temporairement bloqué dans ce chat.",
                                        style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white),
                                      ),
                                      backgroundColor: Colors.redAccent,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(16)),
                                    ),
                                  );
                                }
                              },
                    tooltip: _user == null
                        ? "Connectez-vous"
                        : _blockedUntil != null &&
                                DateTime.now().isBefore(_blockedUntil!) &&
                                !(_userData != null &&
                                    _userData!['role'] == 'boss')
                            ? "Vous êtes temporairement bloqué"
                            : "Envoyer",
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'boss':
        return "Boss";
      case 'premium':
        return "Premium";
      case 'organizer':
        return "Organisateur";
      default:
        return "Utilisateur";
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } else {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}";
    }
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
    final double carouselHeight = screenWidth < 400 ? 140 : 180;
    final double dotSize = screenWidth * 0.02 + 6;
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
                              width: carouselHeight,
                              height: carouselHeight,
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
              width: dotSize,
              height: dotSize,
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
