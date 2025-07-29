import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class OrganizerRequestPage extends StatefulWidget {
  const OrganizerRequestPage({Key? key}) : super(key: key);

  @override
  State<OrganizerRequestPage> createState() => _OrganizerRequestPageState();
}

class _OrganizerRequestPageState extends State<OrganizerRequestPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _responsableController = TextEditingController();
  final TextEditingController _companyNameController = TextEditingController();
  final TextEditingController _contactEmailController = TextEditingController();
  final TextEditingController _companyTypeController = TextEditingController();
  final TextEditingController _motivationController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _siretController = TextEditingController();
  final TextEditingController _activityDescController = TextEditingController();
  final TextEditingController _socialController = TextEditingController();
  final TextEditingController _portfolioController = TextEditingController();

  bool _isSubmitting = false;
  bool _canCancel = true;
  bool _showSuccess = false;
  bool _showWaitOverlay = false;
  DateTime? _lastRequestDate;
  bool _hasPendingRequest = false;
  String? _lastRequestStatus;
  DateTime? _activeUntil;

  bool _isRevoked = false;
  DateTime? _revokedAt;
  String? _revokedReason;

  bool _isStillOrganizer = false;

  String? _city;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _contactEmailController.text = user.email ?? '';
      _responsableController.text = user.displayName ?? '';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Map<String, dynamic>) {
        if (!mounted) return;
        setState(() {
          _city = args['city'] as String?;
        });
      }
    });
    _fetchLastRequestStatus();
  }

  Future<void> _fetchLastRequestStatus() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data();
      if (userData != null && userData['role'] == 'organizer') {
        if (!mounted) return;
        setState(() {
          _isStillOrganizer = true;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isStillOrganizer = false;
        });
      }

      final query = await FirebaseFirestore.instance
          .collection('organizer_requests')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        if (!mounted) return;
        setState(() {
          _lastRequestDate = (doc['createdAt'] as Timestamp).toDate();
          _lastRequestStatus = doc['status'];
          _hasPendingRequest = (doc['status'] == 'pending');
          _isRevoked = (doc['status'] == 'revoked');
          _revokedAt =
              doc.data().containsKey('revokedAt') && doc['revokedAt'] != null
                  ? (doc['revokedAt'] as Timestamp).toDate()
                  : null;
          _revokedReason = doc.data().containsKey('revokedReason')
              ? doc['revokedReason']
              : null;
          if (doc.data().containsKey('activeUntil') &&
              doc['activeUntil'] != null) {
            _activeUntil = (doc['activeUntil'] as Timestamp).toDate();
          } else {
            _activeUntil = null;
          }
        });
      } else {
        if (!mounted) return;
        setState(() {
          _hasPendingRequest = false;
          _lastRequestStatus = null;
          _activeUntil = null;
          _isRevoked = false;
          _revokedAt = null;
          _revokedReason = null;
        });
      }
    }
  }

  bool get canSendRequest {
    if (_isStillOrganizer &&
        _lastRequestStatus == 'accepted' &&
        _activeUntil != null &&
        _activeUntil!.isAfter(DateTime.now())) {
      return false;
    }
    if (_hasPendingRequest) return false;
    if (_isRevoked && _revokedAt != null) {
      final now = DateTime.now();
      if (now.difference(_revokedAt!).inDays < 5) return false;
    }
    if (_lastRequestStatus == 'refused' && _lastRequestDate != null) {
      final now = DateTime.now();
      if (now.difference(_lastRequestDate!).inHours < 24) return false;
    }
    return true;
  }

  Future<void> _showDialogAndRedirect(String title, String message) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(color: Color(0xFF2196F3))),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _submitRequest() async {
    await _fetchLastRequestStatus();
    if (_isStillOrganizer &&
        _lastRequestStatus == 'accepted' &&
        _activeUntil != null &&
        _activeUntil!.isAfter(DateTime.now())) {
      await _showDialogAndRedirect(
        "Déjà organisateur",
        "Vous êtes déjà organisateur actif. Vous ne pouvez pas soumettre une nouvelle demande.",
      );
      return;
    }
    if (_hasPendingRequest) {
      await _showDialogAndRedirect(
        "Demande déjà envoyée",
        "Impossible : une demande est déjà en attente de réponse. Vous pourrez renvoyer une demande 1 jour après la dernière soumission.",
      );
      return;
    }
    if (_isRevoked && _revokedAt != null) {
      final now = DateTime.now();
      if (now.difference(_revokedAt!).inDays < 5) {
        await _showDialogAndRedirect(
          "Délai requis",
          "Vous devez attendre 5 jours après une révocation avant de pouvoir refaire une demande.",
        );
        return;
      }
    }
    if (_lastRequestStatus == 'refused' && _lastRequestDate != null) {
      final now = DateTime.now();
      if (now.difference(_lastRequestDate!).inHours < 24) {
        await _showDialogAndRedirect(
          "Délai requis",
          "Vous devez attendre 1 jour après un refus avant de pouvoir refaire une demande.",
        );
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _canCancel = true;
      _showWaitOverlay = true;
    });

    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('organizer_requests').add({
          'userId': user.uid,
          'status': 'pending',
          'createdAt': Timestamp.now(),
          'responsable': _responsableController.text.trim(),
          'companyName': _companyNameController.text.trim(),
          'contactEmail': _contactEmailController.text.trim(),
          'companyType': _companyTypeController.text.trim(),
          'motivation': _motivationController.text.trim(),
          'phone': _phoneController.text.trim(),
          'website': _websiteController.text.trim(),
          'address': _addressController.text.trim(),
          'siret': _siretController.text.trim(),
          'activityDesc': _activityDescController.text.trim(),
          'social': _socialController.text.trim(),
          'portfolio': _portfolioController.text.trim(),
          'city': _city ?? '',
        });
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _showWaitOverlay = false;
          _showSuccess = true;
          _hasPendingRequest = true;
        });
        await _showDialogAndRedirect(
          "Demande envoyée",
          "Votre demande a bien été envoyée ! Vous recevrez une réponse prochainement.",
        );
      } else {
        if (!mounted) return;
        setState(() {
          _isSubmitting = false;
          _showWaitOverlay = false;
        });
        await _showDialogAndRedirect(
          "Erreur",
          "Vous devez être connecté pour envoyer une demande.",
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _showWaitOverlay = false;
      });
      await _showDialogAndRedirect(
        "Erreur",
        "Une erreur est survenue lors de l'envoi de la demande : $e",
      );
    }
  }

  void _cancelSubmission() {
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _canCancel = false;
      _showWaitOverlay = false;
    });
  }

  void _showWaitSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Vous devez attendre 1 jour après un refus ou la réponse avant de pouvoir refaire une demande.",
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showConfirmationDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Confirmation"),
        content: const Text(
          "Après avoir envoyé votre demande, vous devrez attendre une réponse avant de pouvoir en envoyer une nouvelle. Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Non"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _submitRequest();
            },
            child: const Text("Confirmer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? const Color(0xFF181C20) : Colors.white;
    final cardColor = isDark ? const Color(0xFF23272F) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final inputFillColor =
        isDark ? const Color(0xFF23272F) : const Color(0xFFF0F0F0);

    // Affichage si la personne est organisateur actif
    if (_isStillOrganizer &&
        _lastRequestStatus == 'accepted' &&
        _activeUntil != null &&
        _activeUntil!.isAfter(DateTime.now())) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _city != null && _city!.isNotEmpty
                ? "Demande organisateur ($_city)"
                : "Demande organisateur",
            style: TextStyle(
                color: isDark ? Colors.amber : const Color(0xFF2196F3)),
          ),
          backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
          elevation: 1,
          foregroundColor: isDark ? Colors.white : Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.verified, color: Colors.green, size: 64),
                const SizedBox(height: 24),
                Text(
                  "Vous êtes organisateur actif !",
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Votre statut d'organisateur est actif jusqu'au :\n${_activeUntil != null ? "${_activeUntil!.day.toString().padLeft(2, '0')}/${_activeUntil!.month.toString().padLeft(2, '0')}/${_activeUntil!.year}" : ""}",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.event),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  label: const Text("Continuer vers les événements"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.amber : const Color(0xFF2196F3),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Affichage si révocation et délai non écoulé
    if (_isRevoked && _revokedAt != null && !canSendRequest) {
      final nextDate = _revokedAt!.add(const Duration(days: 5));
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _city != null && _city!.isNotEmpty
                ? "Demande organisateur ($_city)"
                : "Demande organisateur",
            style: TextStyle(
                color: isDark ? Colors.amber : const Color(0xFF2196F3)),
          ),
          backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
          elevation: 1,
          foregroundColor: isDark ? Colors.white : Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, color: Colors.red, size: 64),
                const SizedBox(height: 24),
                Text(
                  "Votre statut d'organisateur a été retiré${_revokedReason != null ? " :\n$_revokedReason" : ""}\n\nVous devez attendre 5 jours avant de pouvoir refaire une demande.",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Vous pourrez refaire une demande à partir du :\n${nextDate.day.toString().padLeft(2, '0')}/${nextDate.month.toString().padLeft(2, '0')}/${nextDate.year}",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.event),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  label: const Text("Continuer vers les événements"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.amber : const Color(0xFF2196F3),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Affichage si une demande est en attente
    if (_hasPendingRequest) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _city != null && _city!.isNotEmpty
                ? "Demande organisateur ($_city)"
                : "Demande organisateur",
            style: TextStyle(
                color: isDark ? Colors.amber : const Color(0xFF2196F3)),
          ),
          backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
          elevation: 1,
          foregroundColor: isDark ? Colors.white : Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top, color: Colors.orange, size: 64),
                const SizedBox(height: 24),
                Text(
                  "Votre demande d'organisateur est en cours de traitement.",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  "Impossible d'envoyer une nouvelle demande tant qu'une réponse n'a pas été donnée.\n\nVous pourrez renvoyer une demande 1 jour après la dernière soumission.",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.event),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  label: const Text("Continuer vers les événements"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.amber : const Color(0xFF2196F3),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Affichage si refusé ou délai non respecté
    if (!canSendRequest) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _city != null && _city!.isNotEmpty
                ? "Demande organisateur ($_city)"
                : "Demande organisateur",
            style: TextStyle(
                color: isDark ? Colors.amber : const Color(0xFF2196F3)),
          ),
          backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
          elevation: 1,
          foregroundColor: isDark ? Colors.white : Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.block, color: Colors.red, size: 64),
                const SizedBox(height: 24),
                Text(
                  _lastRequestStatus == 'refused'
                      ? "Votre précédente demande a été refusée.\nVous devez attendre 1 jour avant de pouvoir en soumettre une nouvelle."
                      : "Vous devez attendre 1 jour depuis votre dernière demande avant de pouvoir en soumettre une nouvelle.",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Text(
                  "Vous pouvez continuer à consulter les événements en attendant.",
                  style: TextStyle(
                    color: textColor,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: const Icon(Icons.event),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  label: const Text("Continuer vers les événements"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isDark ? Colors.amber : const Color(0xFF2196F3),
                    foregroundColor: isDark ? Colors.black : Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Affichage du formulaire si tout est OK
    return Stack(
      children: [
        Scaffold(
          backgroundColor: backgroundColor,
          appBar: AppBar(
            automaticallyImplyLeading: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              _city != null && _city!.isNotEmpty
                  ? "Demande organisateur ($_city)"
                  : "Demande organisateur",
              style: TextStyle(
                  color: isDark ? Colors.amber : const Color(0xFF2196F3)),
            ),
            backgroundColor: isDark ? const Color(0xFF23272F) : Colors.white,
            elevation: 1,
            foregroundColor: isDark ? Colors.white : Colors.black,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Container(
                alignment: Alignment.topCenter,
                width: MediaQuery.of(context).size.width * 0.95,
                margin: const EdgeInsets.symmetric(vertical: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? Colors.black26 : Colors.black12,
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: _showSuccess
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.green, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            "Demande envoyée avec succès !",
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Vous ne pouvez pas renvoyer de demande tant qu'une réponse n'a pas été donnée.",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 15,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.event),
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            label: const Text("Continuer vers les événements"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.amber
                                  : const Color(0xFF2196F3),
                              foregroundColor:
                                  isDark ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                          ),
                        ],
                      )
                    : Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_lastRequestStatus == 'refused')
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  canSendRequest
                                      ? "Votre précédente demande a été refusée. Vous pouvez en soumettre une nouvelle."
                                      : "Votre précédente demande a été refusée. Vous devez attendre 1 jour avant de pouvoir en soumettre une nouvelle.",
                                  style: TextStyle(
                                    color: canSendRequest
                                        ? Colors.red[700]
                                        : Colors.orange[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (_lastRequestStatus == 'accepted' &&
                                _activeUntil != null &&
                                _activeUntil!.isBefore(DateTime.now()))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  "Votre statut d'organisateur a expiré. Vous pouvez refaire une demande.",
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (_isRevoked &&
                                _revokedAt != null &&
                                canSendRequest)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16.0),
                                child: Text(
                                  "Votre statut d'organisateur a été retiré${_revokedReason != null ? " :\n$_revokedReason" : ""}\nVous pouvez refaire une demande.",
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            Text(
                              "Plus vous renseignez d’informations, plus vous augmentez vos chances d’être validé rapidement comme organisateur.",
                              style:
                                  TextStyle(color: Colors.orange, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _responsableController,
                              decoration: InputDecoration(
                                labelText: "Nom du responsable *",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? "Ce champ est requis"
                                      : null,
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _companyNameController,
                              decoration: InputDecoration(
                                labelText: "Nom de l'entreprise *",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? "Ce champ est requis"
                                      : null,
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _contactEmailController,
                              decoration: InputDecoration(
                                labelText: "Adresse e-mail de contact *",
                                border: const OutlineInputBorder(),
                                fillColor: inputFillColor,
                                filled: true,
                              ),
                              readOnly: true,
                              enabled: true,
                              style: TextStyle(color: textColor),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _companyTypeController,
                              decoration: InputDecoration(
                                labelText: "Type d'entreprise (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              decoration: InputDecoration(
                                labelText: "Numéro de téléphone (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              keyboardType: TextInputType.phone,
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _websiteController,
                              decoration: InputDecoration(
                                labelText: "Site web (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _addressController,
                              decoration: InputDecoration(
                                labelText: "Adresse postale (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _siretController,
                              decoration: InputDecoration(
                                labelText: "Numéro SIRET (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _activityDescController,
                              decoration: InputDecoration(
                                labelText:
                                    "Description de l'activité (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              maxLines: 2,
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _socialController,
                              decoration: InputDecoration(
                                labelText: "Réseaux sociaux (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _portfolioController,
                              decoration: InputDecoration(
                                labelText:
                                    "Portfolio/événements passés (facultatif)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _motivationController,
                              decoration: InputDecoration(
                                labelText:
                                    "Motivation (pourquoi devenir organisateur ?)",
                                border: const OutlineInputBorder(),
                                filled: true,
                                fillColor: inputFillColor,
                              ),
                              maxLines: 3,
                              enabled: canSendRequest,
                              style: TextStyle(color: textColor),
                              onTap: () {
                                if (!canSendRequest) {
                                  _showWaitSnackBar(context);
                                }
                              },
                            ),
                            const SizedBox(height: 24),
                            if (_isSubmitting)
                              Column(
                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    "Envoi de la demande en cours...",
                                    style: TextStyle(
                                      color:
                                          isDark ? Colors.white54 : Colors.grey,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  if (_canCancel)
                                    ElevatedButton(
                                      onPressed: _cancelSubmission,
                                      child: const Text("Annuler l'envoi"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                ],
                              )
                            else
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton(
                                      onPressed: !canSendRequest
                                          ? () {
                                              _showWaitSnackBar(context);
                                            }
                                          : () {
                                              if (_formKey.currentState!
                                                  .validate()) {
                                                _showConfirmationDialog();
                                              }
                                            },
                                      child: const Text("Soumettre la demande"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isDark
                                            ? Colors.amber
                                            : const Color(0xFF2196F3),
                                        foregroundColor: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        elevation: 4,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Annuler"),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.red,
                                        side:
                                            const BorderSide(color: Colors.red),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (!canSendRequest)
                              Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: Text(
                                  _isRevoked && _revokedAt != null
                                      ? "Vous devez attendre 5 jours après une révocation avant de pouvoir refaire une demande."
                                      : _lastRequestStatus == 'refused'
                                          ? "Vous devez attendre 1 jour depuis votre dernière demande refusée avant de pouvoir en soumettre une nouvelle."
                                          : "Vous devez attendre 1 jour depuis votre dernière demande avant de pouvoir en soumettre une nouvelle.",
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ),
        if (_showWaitOverlay)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
