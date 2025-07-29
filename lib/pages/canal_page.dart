import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class CanalPage extends StatefulWidget {
  final String calendarId;
  final String ownerId;
  final bool isOwner;

  const CanalPage({
    Key? key,
    required this.calendarId,
    required this.ownerId,
    required this.isOwner,
  }) : super(key: key);

  @override
  State<CanalPage> createState() => _CanalPageState();
}

class _CanalPageState extends State<CanalPage> {
  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  late User? _user;
  Map<String, dynamic>? _userData;
  bool _loadingUser = true;
  bool _isDark = false;

  Map<String, dynamic>? _replyTo;
  bool _sendAnonymously = false;
  File? _selectedImage;

  String? _calendarName;
  bool _allowWriting = true;
  bool _loadingCalendar = true;

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    _fetchUserData();
    _fetchCalendarInfo();
  }

  @override
  void dispose() {
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

  Future<void> _fetchCalendarInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .get();
    if (doc.exists) {
      setState(() {
        _calendarName = doc.data()?['name'] ?? widget.calendarId;
        _allowWriting = doc.data()?['allowWriting'] ?? true;
        _loadingCalendar = false;
      });
    } else {
      setState(() {
        _calendarName = widget.calendarId;
        _allowWriting = true;
        _loadingCalendar = false;
      });
    }
  }

  Future<void> _updateAllowWriting(bool value) async {
    setState(() {
      _allowWriting = value;
    });
    await FirebaseFirestore.instance
        .collection('private_calendars')
        .doc(widget.calendarId)
        .update({'allowWriting': value});
  }

  Future<void> _sendMessage({String? imageUrl}) async {
    if ((_controller.text.trim().isEmpty &&
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
          .collection('private_calendars')
          .doc(widget.calendarId)
          .collection('canal')
          .add({
        if (imageUrl == null) 'text': _controller.text.trim(),
        if (imageUrl != null) 'imageUrl': imageUrl,
        'userId': _user!.uid,
        'pseudo': ((_userData?['role'] == 'boss') ||
                    (_userData?['role'] == 'premium' &&
                        _userData?['subscriptionStatus'] == 'active')) &&
                _sendAnonymously
            ? "Anonyme"
            : (_userData?['pseudo'] ?? 'Utilisateur'),
        'role': _userData?['role'] ?? 'user',
        'certif': _userData?['role'] == 'boss' ||
                (_userData?['role'] == 'premium' &&
                    _userData?['subscriptionStatus'] == 'active')
            ? true
            : false,
        'createdAt': FieldValue.serverTimestamp(),
        'likes': <String>[],
        if (_replyTo != null && _replyTo?['imageUrl'] == null)
          'replyTo': {
            'pseudo': _replyTo?['pseudo'] ?? '',
            'role': _replyTo?['role'] ?? 'user',
            'certif': _replyTo?['certif'] ?? false,
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
          'canal_images/${_user!.uid}_${DateTime.now().millisecondsSinceEpoch}');
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

  Future<void> _toggleLike(
      DocumentReference msgRef, List<dynamic> likes, String msgId) async {
    if (_user == null) return;
    final uid = _user!.uid;
    final isLiked = likes.contains(uid);

    await msgRef.update({
      'likes':
          isLiked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid])
    });
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'boss':
        return Colors.blue;
      case 'premium':
        return Colors.amber[700]!;
      default:
        return Colors.grey;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    _isDark = theme.brightness == Brightness.dark;
    final isSmallScreen = MediaQuery.of(context).size.width < 400;

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
          title: Text(
            _calendarName ?? widget.calendarId,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 0.5,
            ),
          ),
          centerTitle: false,
          actions: [
            if (widget.isOwner && !_loadingCalendar)
              Tooltip(
                message: "Autoriser les membres à écrire",
                child: IconButton(
                  icon: Icon(
                    _allowWriting ? Icons.lock_open : Icons.lock_outline,
                    color: Colors.white,
                  ),
                  onPressed: () => _updateAllowWriting(!_allowWriting),
                ),
              ),
            if (_userData != null &&
                (_userData!['role'] == 'boss' ||
                    (_userData!['role'] == 'premium' &&
                        _userData!['subscriptionStatus'] == 'active')))
              Tooltip(
                message: "Envoyer en anonyme (premium/boss)",
                child: IconButton(
                  icon: Icon(
                    _sendAnonymously ? Icons.visibility_off : Icons.visibility,
                    color: Colors.amber,
                  ),
                  onPressed: () {
                    setState(() {
                      _sendAnonymously = !_sendAnonymously;
                    });
                  },
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('private_calendars')
                    .doc(widget.calendarId)
                    .collection('canal')
                    .orderBy('createdAt', descending: true)
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
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Commencez la conversation.",
                            style: TextStyle(
                              fontSize: 16,
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
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final data = docs[i].data() as Map<String, dynamic>;
                      final pseudo = data['pseudo'] ?? 'Utilisateur';
                      final role = data['role'] ?? 'user';
                      final certif = data['certif'] ?? false;
                      final text = data['text'] ?? '';
                      final ts = data['createdAt'] as Timestamp?;
                      final date = ts != null ? ts.toDate() : DateTime.now();
                      final isMe =
                          _user != null && data['userId'] == _user!.uid;
                      final replyTo = data['replyTo'] as Map<String, dynamic>?;
                      final msgRef = docs[i].reference;
                      final likes = data['likes'] ?? [];
                      final likeCount = likes.length;
                      final isLiked =
                          _user != null && likes.contains(_user!.uid);
                      final msgId = docs[i].id;

                      Widget bubble = ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
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
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                margin: EdgeInsets.only(
                                  left: isMe ? 40 : 8,
                                  right: isMe ? 8 : 40,
                                  top: 10,
                                  bottom: 10,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 14),
                                decoration: BoxDecoration(
                                  color: isMe
                                      ? (_isDark
                                          ? Colors.blue[700]
                                          : Colors.blue[100])
                                      : (_isDark
                                          ? Colors.blueGrey[800]
                                          : Colors.blue[50]),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(18),
                                    topRight: const Radius.circular(18),
                                    bottomLeft: Radius.circular(isMe ? 18 : 6),
                                    bottomRight: Radius.circular(isMe ? 6 : 18),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (replyTo != null &&
                                        replyTo['text'] != null &&
                                        replyTo['text'].toString().isNotEmpty)
                                      Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isMe
                                              ? (_isDark
                                                  ? Colors.blue[900]
                                                  : Colors.blue[200])
                                              : (_isDark
                                                  ? Colors.blueGrey[900]
                                                  : Colors.grey[200]),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.reply,
                                                size: 16,
                                                color: _isDark
                                                    ? Colors.white70
                                                    : Colors.grey[600]),
                                            const SizedBox(width: 4),
                                            Text(
                                              replyTo['pseudo'] ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: _isDark
                                                    ? Colors.white
                                                    : Colors.grey[700],
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (_certifIcon(
                                                    replyTo['role'] ?? '',
                                                    replyTo['certif'] ??
                                                        false) !=
                                                null) ...[
                                              const SizedBox(width: 2),
                                              _certifIcon(replyTo['role'] ?? '',
                                                  replyTo['certif'] ?? false)!,
                                            ],
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                replyTo['text'],
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: _isDark
                                                      ? Colors.white
                                                      : Colors.grey[700],
                                                  fontSize: 12,
                                                  fontStyle: FontStyle.italic,
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
                                          Text(
                                            pseudo,
                                            style: TextStyle(
                                              color: _roleColor(role),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          if (_certifIcon(role, certif) !=
                                              null) ...[
                                            const SizedBox(width: 4),
                                            _certifIcon(role, certif)!,
                                          ],
                                          const SizedBox(width: 6),
                                        ],
                                        Text(
                                          _formatDate(date),
                                          style: TextStyle(
                                            color: _isDark
                                                ? Colors.white54
                                                : Colors.grey[600],
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    if (data['imageUrl'] != null)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 6),
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
                                                      errorBuilder: (c, e, s) =>
                                                          Container(
                                                        color: Colors.grey[300],
                                                        width: 300,
                                                        height: 300,
                                                        child: Icon(
                                                            Icons.broken_image,
                                                            color: Colors.grey,
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
                                              height: 180,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              errorBuilder: (c, e, s) =>
                                                  Container(
                                                height: 180,
                                                color: Colors.grey[300],
                                                child: Icon(Icons.broken_image,
                                                    color: Colors.grey),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    GestureDetector(
                                      onDoubleTap: () {
                                        _toggleLike(msgRef, likes, msgId);
                                      },
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
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (likeCount > 0)
                                Positioned(
                                  top: 8,
                                  right: isMe ? null : 8,
                                  left: isMe ? 8 : null,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black12,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.favorite,
                                            color: Colors.red, size: 16),
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(left: 2),
                                          child: Text(
                                            likeCount.toString(),
                                            style: TextStyle(
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );

                      return Row(
                        mainAxisAlignment: isMe
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          bubble,
                          if (_userData != null && _userData!['role'] == 'boss')
                            IconButton(
                              icon: Icon(Icons.delete,
                                  color: Colors.red[400], size: 20),
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
                                  await msgRef.delete();
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
                    horizontal: isSmallScreen ? 8 : 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.reply,
                        color: _isDark ? Colors.white70 : Colors.grey[700],
                        size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _replyTo?['pseudo'] ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _isDark ? Colors.white : Colors.grey[800],
                        fontSize: 13,
                      ),
                    ),
                    if (_certifIcon(_replyTo?['role'] ?? '',
                            _replyTo?['certif'] ?? false) !=
                        null) ...[
                      const SizedBox(width: 2),
                      _certifIcon(_replyTo?['role'] ?? '',
                          _replyTo?['certif'] ?? false)!,
                    ],
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _replyTo?['text'] ?? '',
                        style: TextStyle(
                          color: _isDark ? Colors.white : Colors.grey[700],
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
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
                  horizontal: isSmallScreen ? 4 : 12,
                  vertical: isSmallScreen ? 4 : 8),
              child: Row(
                children: [
                  if (_userData != null &&
                      (_userData!['role'] == 'boss' ||
                          (_userData!['role'] == 'premium' &&
                              _userData!['subscriptionStatus'] == 'active')))
                    IconButton(
                      icon: Icon(Icons.photo,
                          color: Theme.of(context).primaryColor),
                      onPressed: _sending || _controller.text.trim().isNotEmpty
                          ? null
                          : _pickImage,
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
                              width: 48,
                              height: 48,
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
                                  color: Colors.white, size: 16),
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
                          (_allowWriting || widget.isOwner) &&
                          _selectedImage == null,
                      minLines: 1,
                      maxLines: 4,
                      style: TextStyle(
                        color: _isDark ? Colors.white : Colors.black87,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                      decoration: InputDecoration(
                        hintText: _user == null
                            ? "Connectez-vous pour écrire…"
                            : (!_allowWriting && !widget.isOwner)
                                ? "L'écriture est désactivée"
                                : "Écrire un message…",
                        hintStyle: TextStyle(
                          color: _isDark ? Colors.white54 : Colors.grey[500],
                          fontSize: isSmallScreen ? 13 : 15,
                        ),
                        filled: true,
                        fillColor:
                            _isDark ? Colors.blueGrey[800] : Colors.grey[100],
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 8 : 14,
                            vertical: isSmallScreen ? 8 : 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      onSubmitted: (_) {
                        if (_selectedImage != null &&
                            _controller.text.trim().isEmpty) {
                          _sendSelectedImage();
                        } else if (_selectedImage == null &&
                            _controller.text.trim().isNotEmpty) {
                          _sendMessage();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send_rounded,
                            color: Theme.of(context).primaryColor),
                    onPressed: (_user != null &&
                            !_sending &&
                            !_loadingUser &&
                            (_allowWriting || widget.isOwner) &&
                            ((_selectedImage != null &&
                                    _controller.text.trim().isEmpty) ||
                                (_selectedImage == null &&
                                    _controller.text.trim().isNotEmpty)))
                        ? () {
                            if (_selectedImage != null) {
                              _sendSelectedImage();
                            } else {
                              _sendMessage();
                            }
                          }
                        : null,
                    tooltip: _user == null
                        ? "Connectez-vous"
                        : (!_allowWriting && !widget.isOwner)
                            ? "L'écriture est désactivée"
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (now.difference(date).inDays == 0) {
      return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } else {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}";
    }
  }
}
