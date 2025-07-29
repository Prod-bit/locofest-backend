import 'package:flutter/material.dart';

class EventCard extends StatelessWidget {
  final dynamic event;
  final bool isFavorite;
  final bool canDelete;
  final VoidCallback? onFavorite;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final double screenWidth;
  final double screenHeight;
  final bool isDarkMode;
  final Color primaryColor;
  final Color accentColor;
  final Color errorColor;

  const EventCard({
    required this.event,
    required this.isFavorite,
    required this.canDelete,
    required this.onFavorite,
    required this.onDelete,
    required this.onTap,
    required this.screenWidth,
    required this.screenHeight,
    required this.isDarkMode,
    required this.primaryColor,
    required this.accentColor,
    required this.errorColor,
    Key? key,
  }) : super(key: key);

  Widget _buildCertificationBadge(String? role) {
    if (role == 'premium') {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.verified, color: Colors.amber, size: 22),
      );
    } else if (role == 'boss') {
      return Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Icon(Icons.verified_user, color: Colors.blue, size: 22),
      );
    }
    return SizedBox.shrink();
  }

  String _formatDateFr(DateTime date) {
    final heure = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    if (date.hour != 0 || date.minute != 0) {
      return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à $heure:$minute";
    }
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Widget _infoRow({
    required IconData icon,
    required String label,
    required String value,
    required double iconSize,
    required double fontSize,
    required Color color,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconSize, color: color),
          SizedBox(width: 6),
          Flexible(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: fontSize,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
                children: [
                  if (label.isNotEmpty)
                    TextSpan(
                      text: label + " ",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  TextSpan(text: value),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double cardPadding = screenWidth * 0.04;
    final double cardRadius = screenWidth * 0.045;
    final double titleFontSize = screenWidth * 0.052;
    final double cardFontSize = screenWidth * 0.038;
    final double iconSize = screenWidth * 0.048;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: EdgeInsets.symmetric(
            horizontal: cardPadding, vertical: cardPadding / 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        elevation: 6,
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        shadowColor:
            isDarkMode ? Colors.black54 : Colors.blue.withOpacity(0.08),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              cardPadding, cardPadding * 0.9, cardPadding, cardPadding * 0.9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                event['title'] ?? 'Sans titre',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Color(0xFF34AADC)
                                      : primaryColor,
                                  fontSize: titleFontSize,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Roboto',
                                  letterSpacing: 0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            if ((event['creatorRole'] ?? event['role']) != null)
                              _buildCertificationBadge(
                                  event['creatorRole'] ?? event['role']),
                          ],
                        ),
                        if (event['city'] != null &&
                            event['city'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_on,
                                    color: isDarkMode
                                        ? Colors.blue[200]
                                        : Colors.blue,
                                    size: iconSize * 0.5),
                                SizedBox(width: 3),
                                Text(
                                  event['city'],
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.blue[100]
                                        : Colors.blue[900],
                                    fontWeight: FontWeight.w500,
                                    fontSize: cardFontSize * 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite
                          ? (isDarkMode ? Color(0xFFFF3B30) : accentColor)
                          : (isDarkMode ? Colors.grey : Colors.grey),
                      size: iconSize * 1.3,
                    ),
                    onPressed: onFavorite,
                  ),
                  if (canDelete)
                    IconButton(
                      icon: Icon(Icons.delete,
                          color: Colors.red, size: iconSize * 0.9),
                      tooltip: "Supprimer l'événement",
                      onPressed: onDelete,
                    ),
                ],
              ),
              SizedBox(height: screenHeight * 0.012),
              if (event['images'] != null &&
                  event['images'] is List &&
                  (event['images'] as List).isNotEmpty)
                Row(
                  children: [
                    Icon(Icons.photo_library,
                        color: primaryColor, size: iconSize * 0.7),
                    SizedBox(width: 4),
                    Text(
                      "${(event['images'] as List).length} image${(event['images'] as List).length > 1 ? 's' : ''} disponible${(event['images'] as List).length > 1 ? 's' : ''}",
                      style: TextStyle(
                        color: isDarkMode ? Colors.white70 : Color(0xFF333333),
                        fontSize: cardFontSize * 0.95,
                        fontFamily: 'Roboto',
                      ),
                    ),
                  ],
                ),
              _infoRow(
                icon: Icons.calendar_today,
                label: "",
                value: _formatDateFr((event['date'] as dynamic).toDate()),
                iconSize: iconSize,
                fontSize: cardFontSize,
                color: primaryColor,
                isDarkMode: isDarkMode,
              ),
              _infoRow(
                icon: Icons.place,
                label: "",
                value: event['location'] ?? 'Non spécifié',
                iconSize: iconSize,
                fontSize: cardFontSize,
                color: primaryColor,
                isDarkMode: isDarkMode,
              ),
              _infoRow(
                icon: Icons.category,
                label: "",
                value: event['category'] ?? 'Non spécifiée',
                iconSize: iconSize,
                fontSize: cardFontSize,
                color: primaryColor,
                isDarkMode: isDarkMode,
              ),
              SizedBox(height: screenHeight * 0.005),
              Text(
                "Description : ${event['description'] ?? 'Aucune description'}",
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Color(0xFF333333),
                  fontSize: cardFontSize,
                  fontFamily: 'Roboto',
                ),
                softWrap: true,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
