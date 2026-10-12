import 'package:flutter/material.dart';
import '../../models/api_request.dart';

class HttpMethodBadge extends StatelessWidget {
  final HttpMethod method;
  final double fontSize;

  const HttpMethodBadge({
    super.key,
    required this.method,
    this.fontSize = 11,
  });

  Color get _color {
    switch (method) {
      case HttpMethod.get:
        return const Color(0xFF10B981); // Emerald Green
      case HttpMethod.post:
        return const Color(0xFF3B82F6); // Blue
      case HttpMethod.put:
        return const Color(0xFFF59E0B); // Amber
      case HttpMethod.delete:
        return const Color(0xFFEF4444); // Red
      case HttpMethod.patch:
        return const Color(0xFF8B5CF6); // Purple
      case HttpMethod.head:
      case HttpMethod.options:
        return const Color(0xFF6B7280); // Gray
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        method.nameString,
        style: TextStyle(
          color: _color,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class StatusCodeBadge extends StatelessWidget {
  final int statusCode;
  final String statusMessage;

  const StatusCodeBadge({
    super.key,
    required this.statusCode,
    required this.statusMessage,
  });

  Color get _color {
    if (statusCode >= 200 && statusCode < 300) {
      return const Color(0xFF10B981);
    } else if (statusCode >= 300 && statusCode < 400) {
      return const Color(0xFF3B82F6);
    } else if (statusCode >= 400 && statusCode < 500) {
      return const Color(0xFFF59E0B);
    } else if (statusCode >= 500) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFF6B7280);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            statusCode == 0 ? 'Error' : '$statusCode $statusMessage',
            style: TextStyle(
              color: _color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
