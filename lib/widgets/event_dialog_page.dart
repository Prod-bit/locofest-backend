import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EventDialogPage extends StatefulWidget {
  final dynamic event;
  final bool isDarkMode;
  final double screenWidth;
  final double screenHeight;
  final String? creatorId;
  final bool canRate;
  final Function()? onReport;
  final Function()? onShare;
  final Function()? onComments;
  final Function()? onQuestions;

  const EventDialogPage({
    required this.event,
    required this.isDarkMode,
    required this.screenWidth,
    required this.screenHeight,
    this.creatorId,
    this.canRate = false,
    this.onReport,
    this.onShare,
    this.onComments,
    this.onQuestions,
    Key? key,
  }) : super(key: key);

  @override
  State<EventDialogPage> createState() => _EventDialogPageState();
}

class _EventDialogPageState extends State<EventDialogPage> {
  bool _isParticipating = false;
  bool _loadingParticipation = true;

  @override
  void initState() {
    super.initState();
    _checkParticipation();
  }

  Future<void> _checkParticipation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _isParticipating = false;
        _loadingParticipation = false;
      });
      return;
    }
    final participations = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: widget.event.id)
        .where('userId', isEqualTo: user.uid)
        .get();
    setState(() {
      _isParticipating = participations.docs.isNotEmpty;
      _loadingParticipation = false;
    });
  }

  Future<void> _toggleParticipation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingParticipation = true);
    final participations = await FirebaseFirestore.instance
        .collection('event_participations')
        .where('eventId', isEqualTo: widget.event.id)
        .where('userId', isEqualTo: user.uid)
        .get();
    if (participations.docs.isNotEmpty) {
      for (var doc in participations.docs) {
        await doc.reference.delete();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Vous êtes désinscrit de l'événement."),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      await FirebaseFirestore.instance.collection('event_participations').add({
        'eventId': widget.event.id,
        'userId': user.uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Inscription confirmée à l'événement "),
          backgroundColor: Colors.green,
        ),
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
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

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final screenWidth = widget.screenWidth;
    final screenHeight = widget.screenHeight;
    final isDarkMode = widget.isDarkMode;
    final creatorId = widget.creatorId;
    final canRate = widget.canRate;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(screenWidth * 0.06),
      ),
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.05),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titre, badge certif, bouton signaler et croix
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            event['title'] ?? 'Sans titre',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: screenWidth * 0.052,
                              color: isDarkMode
                                  ? Color(0xFF34AADC)
                                  : Color(0xFF1976D2),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildCertificationBadge(
                            event['creatorRole'] ?? event['role']),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.report,
                        color: Colors.redAccent, size: screenWidth * 0.055),
                    tooltip: "Signaler",
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: widget.onReport,
                  ),
                  IconButton(
                    icon: Icon(Icons.close,
                        size: screenWidth * 0.055,
                        color: isDarkMode ? Colors.white38 : Colors.grey[600]),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: "Fermer",
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              // Badge ville
              if (event['city'] != null && event['city'].toString().isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(
                      top: screenWidth * 0.01,
                      bottom: screenWidth * 0.02,
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal: screenWidth * 0.03,
                      vertical: screenWidth * 0.013,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isDarkMode ? Colors.blueGrey[900] : Colors.blue[50],
                      borderRadius: BorderRadius.circular(screenWidth * 0.035),
                      border: Border.all(
                        color: isDarkMode ? Colors.blue[200]! : Colors.blue,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_on,
                            color: isDarkMode ? Colors.blue[200] : Colors.blue,
                            size: screenWidth * 0.04),
                        SizedBox(width: screenWidth * 0.01),
                        Text(
                          event['city'],
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.blue[100]
                                : Colors.blue[900],
                            fontWeight: FontWeight.w600,
                            fontSize: screenWidth * 0.035,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Carousel images
              if (event['images'] != null &&
                  event['images'] is List &&
                  (event['images'] as List).isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(bottom: screenWidth * 0.03),
                  child: _EventImageCarousel(
                    images: event['images'],
                    height: screenWidth * 0.55,
                  ),
                ),
              // Infos
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: screenWidth * 0.045, color: Color(0xFF2196F3)),
                  SizedBox(width: screenWidth * 0.02),
                  Flexible(
                    child: Text(
                      "Date : ${_formatDateFr((event['date'] as Timestamp).toDate())}",
                      style: TextStyle(fontSize: screenWidth * 0.038),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenWidth * 0.01),
              Row(
                children: [
                  Icon(Icons.place,
                      size: screenWidth * 0.045, color: Color(0xFF2196F3)),
                  SizedBox(width: screenWidth * 0.02),
                  Flexible(
                    child: Text(
                      "Lieu : ${event['location'] ?? 'Non spécifié'}",
                      style: TextStyle(fontSize: screenWidth * 0.038),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenWidth * 0.01),
              Row(
                children: [
                  Icon(Icons.category,
                      size: screenWidth * 0.045, color: Color(0xFF2196F3)),
                  SizedBox(width: screenWidth * 0.02),
                  Flexible(
                    child: Text(
                      "Catégorie : ${event['category'] ?? 'Non spécifiée'}",
                      style: TextStyle(fontSize: screenWidth * 0.038),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              SizedBox(height: screenWidth * 0.025),
              Text(
                "Description :",
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: screenWidth * 0.038,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              SizedBox(height: screenWidth * 0.01),
              Text(
                event['description'] ?? 'Aucune description',
                style: TextStyle(
                  fontSize: screenWidth * 0.038,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                ),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: screenWidth * 0.045),
              // Boutons actions harmonisés et responsive
              LayoutBuilder(
                builder: (context, constraints) {
                  double btnWidth = (constraints.maxWidth < 400)
                      ? (constraints.maxWidth - 32) / 2
                      : 140;
                  btnWidth = btnWidth < 90 ? 90 : btnWidth;
                  double btnHeight = 38;
                  double btnFont = screenWidth * 0.035;

                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      // Bouton Participer / Se désinscrire (design EventsListPage)
                      SizedBox(
                        width: btnWidth,
                        height: btnHeight,
                        child: _loadingParticipation
                            ? Center(child: CircularProgressIndicator())
                            : ElevatedButton.icon(
                                icon: Icon(
                                  _isParticipating
                                      ? Icons.close
                                      : Icons.event_available,
                                  size: btnFont,
                                ),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _isParticipating
                                        ? "Se désinscrire"
                                        : "Participer",
                                    style: TextStyle(
                                      fontSize: btnFont,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isParticipating
                                      ? Colors.red
                                      : (isDarkMode
                                          ? Color(0xFF34AADC)
                                          : Color(0xFF1976D2)),
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        screenWidth * 0.035),
                                  ),
                                  elevation: 4,
                                ),
                                onPressed: _toggleParticipation,
                              ),
                      ),
                      // Bouton Partager
                      SizedBox(
                        width: btnWidth,
                        height: btnHeight,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.share, size: btnFont),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Partager",
                              style: TextStyle(
                                fontSize: btnFont,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                isDarkMode ? Colors.blueGrey : Colors.blue[800],
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(screenWidth * 0.035),
                            ),
                            elevation: 4,
                          ),
                          onPressed: widget.onShare,
                        ),
                      ),
                      // Bouton Commentaires
                      SizedBox(
                        width: btnWidth,
                        height: btnHeight,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.comment, size: btnFont),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Commentaires",
                              style: TextStyle(
                                fontSize: btnFont,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(screenWidth * 0.035),
                            ),
                            elevation: 4,
                          ),
                          onPressed: widget.onComments,
                        ),
                      ),
                      // Bouton Questions
                      SizedBox(
                        width: btnWidth,
                        height: btnHeight,
                        child: ElevatedButton.icon(
                          icon: Icon(Icons.help_outline, size: btnFont),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              "Questions",
                              style: TextStyle(
                                fontSize: btnFont,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDarkMode
                                ? Color(0xFF34AADC)
                                : Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(screenWidth * 0.035),
                            ),
                            elevation: 4,
                          ),
                          onPressed: widget.onQuestions,
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
  }

  String _formatDateFr(DateTime date) {
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (date.hour != 0 || date.minute != 0) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à $heure:$minute";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }
}

// Carousel images pour le popup
class _EventImageCarousel extends StatefulWidget {
  final List images;
  final double height;

  const _EventImageCarousel({
    required this.images,
    required this.height,
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
