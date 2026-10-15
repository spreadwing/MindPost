import 'package:flutter/material.dart';
import '../../models/api_request.dart';

class HttpMethodBadge extends StatelessWidget {
  final HttpMethod method;
  final double fontSize;
  final bool isSolid;

  const HttpMethodBadge({
    super.key,
    required this.method,
    this.fontSize = 11,
    this.isSolid = false,
  });

  Color get _textColor {
    switch (method) {
      case HttpMethod.get:
        return const Color(0xFF059669); // Emerald 600
      case HttpMethod.post:
        return const Color(0xFF2563EB); // Blue 600
      case HttpMethod.put:
        return const Color(0xFFD97706); // Amber 600
      case HttpMethod.delete:
        return const Color(0xFFDC2626); // Red 600
      case HttpMethod.patch:
        return const Color(0xFF7C3AED); // Purple 600
      case HttpMethod.head:
      case HttpMethod.options:
        return const Color(0xFF475569); // Slate 600
    }
  }

  Color get _bgColor {
    switch (method) {
      case HttpMethod.get:
        return const Color(0xFFECFDF5);
      case HttpMethod.post:
        return const Color(0xFFEFF6FF);
      case HttpMethod.put:
        return const Color(0xFFFFFBEB);
      case HttpMethod.delete:
        return const Color(0xFFFEF2F2);
      case HttpMethod.patch:
        return const Color(0xFFF5F3FF);
      case HttpMethod.head:
      case HttpMethod.options:
        return const Color(0xFFF1F5F9);
    }
  }

  Color get _borderColor {
    switch (method) {
      case HttpMethod.get:
        return const Color(0xFFA7F3D0);
      case HttpMethod.post:
        return const Color(0xFFBFDBFE);
      case HttpMethod.put:
        return const Color(0xFFFDE68A);
      case HttpMethod.delete:
        return const Color(0xFFFECACA);
      case HttpMethod.patch:
        return const Color(0xFFDDD6FE);
      case HttpMethod.head:
      case HttpMethod.options:
        return const Color(0xFFE2E8F0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isSolid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          color: _textColor,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          method.nameString,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _borderColor, width: 0.8),
      ),
      child: Text(
        method.nameString,
        style: TextStyle(
          color: _textColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
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

  Color get _textColor {
    if (statusCode >= 200 && statusCode < 300) {
      return const Color(0xFF059669);
    } else if (statusCode >= 300 && statusCode < 400) {
      return const Color(0xFF2563EB);
    } else if (statusCode >= 400 && statusCode < 500) {
      return const Color(0xFFD97706);
    } else if (statusCode >= 500) {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFF475569);
  }

  Color get _bgColor {
    if (statusCode >= 200 && statusCode < 300) {
      return const Color(0xFFECFDF5);
    } else if (statusCode >= 300 && statusCode < 400) {
      return const Color(0xFFEFF6FF);
    } else if (statusCode >= 400 && statusCode < 500) {
      return const Color(0xFFFFFBEB);
    } else if (statusCode >= 500) {
      return const Color(0xFFFEF2F2);
    }
    return const Color(0xFFF1F5F9);
  }

  Color get _borderColor {
    if (statusCode >= 200 && statusCode < 300) {
      return const Color(0xFFA7F3D0);
    } else if (statusCode >= 300 && statusCode < 400) {
      return const Color(0xFFBFDBFE);
    } else if (statusCode >= 400 && statusCode < 500) {
      return const Color(0xFFFDE68A);
    } else if (statusCode >= 500) {
      return const Color(0xFFFECACA);
    }
    return const Color(0xFFE2E8F0);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _textColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusCode == 0 ? 'Network Error' : '$statusCode $statusMessage',
            style: TextStyle(
              color: _textColor,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
