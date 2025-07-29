import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class FeedbackPage extends StatefulWidget {
  final String? city;
  final bool isOrganizer;
  const FeedbackPage({Key? key, this.city, required this.isOrganizer})
      : super(key: key);

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  String? _error;
  bool _isTyping = false;

  Future<void> _sendFeedback() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      if (!mounted) return;
      setState(() {
        _error = "Merci de saisir un message.";
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSending = true;
      _error = null;
    });
    final user = FirebaseAuth.instance.currentUser;
    await FirebaseFirestore.instance
        .collection('admin_organizer_requests')
        .add({
      'type': 'feedback',
      'userId': user?.uid,
      'email': user?.email,
      'city': widget.city ?? '',
      'isOrganizer': widget.isOrganizer,
      'message': text,
      'createdAt': Timestamp.now(),
    });
    if (!mounted) return;
    setState(() {
      _isSending = false;
    });
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Merci pour votre retour !"),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Responsive variables
    final double padding = screenWidth * 0.06;
    final double cardPadding = screenWidth * 0.045;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.11;
    final double buttonFontSize = screenWidth * 0.042;
    final double buttonHeight = screenHeight * 0.055;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF181C20) : const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // HEADER
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: padding * 0.7,
                left: 0,
                right: 0,
                bottom: padding * 0.4,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [const Color(0xFF0F2027), const Color(0xFF2C5364)]
                      : [const Color(0xFFBBDEFB), const Color(0xFF90CAF9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(cardRadius * 1.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color:
                              isDark ? Colors.white : const Color(0xFF1976D2),
                          size: iconSize * 0.7),
                      onPressed: () => Navigator.pop(context),
                      tooltip: "Retour",
                    ),
                  ),
                  Center(
                    child: Column(
                      children: [
                        Text(
                          "Donner un avis",
                          style: TextStyle(
                            color:
                                isDark ? Colors.white : const Color(0xFF1976D2),
                            fontSize: titleFontSize * 1.1,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Votre avis est très important pour nous.\nChaque message est lu avec attention et contribue directement à l’amélioration de l’application.\nMerci pour votre confiance",
                          style: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF424242),
                            fontSize: cardFontSize * 1.02,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(cardPadding * 1.2),
                child: Container(
                  padding: EdgeInsets.all(cardPadding * 1.2),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[850] : Colors.white,
                    borderRadius: BorderRadius.circular(cardRadius * 1.1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.feedback,
                          color: isDark
                              ? const Color(0xFF34AADC)
                              : const Color(0xFF1976D2),
                          size: iconSize * 1.1),
                      SizedBox(height: cardPadding * 1.1),
                      TextField(
                        controller: _controller,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        onChanged: (value) {
                          setState(() {
                            _isTyping = value.isNotEmpty;
                          });
                        },
                        style: TextStyle(
                          fontSize: cardFontSize * 1.08,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: "Votre message...",
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(cardRadius),
                          ),
                          prefixIcon: Icon(Icons.edit,
                              color: isDark
                                  ? const Color(0xFF34AADC)
                                  : const Color(0xFF1976D2),
                              size: iconSize * 0.7),
                          labelStyle: TextStyle(
                            color: isDark
                                ? Colors.white70
                                : const Color(0xFF424242),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? const Color(0xFF34AADC)
                                  : const Color(0xFF1976D2),
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(cardRadius),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[400]!,
                              width: 1,
                            ),
                            borderRadius: BorderRadius.circular(cardRadius),
                          ),
                          suffixIcon: _isTyping
                              ? const Icon(Icons.check, color: Colors.green)
                              : null,
                        ),
                      ),
                      SizedBox(height: cardPadding * 1.2),
                      SizedBox(
                        width: double.infinity,
                        height: buttonHeight,
                        child: ElevatedButton(
                          onPressed: _isSending ? null : _sendFeedback,
                          child: _isSending
                              ? SizedBox(
                                  width: buttonHeight * 0.7,
                                  height: buttonHeight * 0.7,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.send,
                                        color: Colors.white,
                                        size: buttonFontSize * 1.2),
                                    SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        "Envoyer",
                                        style: TextStyle(
                                          fontSize: buttonFontSize * 1.05,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? const Color(0xFF2196F3)
                                : const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: cardPadding * 1.2,
                                vertical: cardPadding * 0.7),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(cardRadius * 0.8),
                            ),
                            elevation: 3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
