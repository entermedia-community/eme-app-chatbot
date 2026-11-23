import 'dart:convert';

import 'package:eme_app_sdk/eme_app_sdk.dart';
import 'package:flutter/foundation.dart';

import 'lead_chat_state.dart';

/// Keeps the visitor's chat (transcript, progress, lead session) on their
/// device. On web, SharedPreferences is backed by `localStorage`, scoped to
/// the origin the chatbot is served from.
class LeadStore {
  static String _key(String vendorId) => 'eme_chatbot.lead.$vendorId';

  Future<LeadChatState?> load(String vendorId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(vendorId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return LeadChatState.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (e) {
      debugPrint('[LeadStore] discarding unreadable saved chat: $e');
    }
    return null;
  }

  Future<void> save(String vendorId, LeadChatState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(vendorId), jsonEncode(state.toJson()));
  }

  Future<void> clear(String vendorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(vendorId));
  }
}
