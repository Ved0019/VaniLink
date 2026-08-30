import 'dart:convert';

class MessagePayload {
  final String text;
  final bool isEmergency;
  final int timestamp;

  MessagePayload({
    required this.text,
    this.isEmergency = false,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'isEmergency': isEmergency,
      'timestamp': timestamp,
    };
  }

  String toJson() => json.encode(toMap());
}
