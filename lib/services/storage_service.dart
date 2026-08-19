import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class StorageService {
  static const _keyName = 'user_name';
  static const _keyUserId = 'user_id';
  static const _keyMessages = 'messages';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? getSavedName() => _prefs.getString(_keyName);

  Future<void> saveName(String name) async {
    await _prefs.setString(_keyName, name);
  }

  String? getSavedUserId() => _prefs.getString(_keyUserId);

  Future<void> saveUserId(String id) async {
    await _prefs.setString(_keyUserId, id);
  }

  List<Message> getMessages(String roomId) {
    final raw = _prefs.getString('${_keyMessages}_$roomId');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List;
    return list.map((e) => Message.fromJson(e)).toList();
  }

  Future<void> saveMessages(String roomId, List<Message> messages) async {
    final json = jsonEncode(messages.map((m) => m.toJson()).toList());
    await _prefs.setString('${_keyMessages}_$roomId', json);
  }

  Future<void> appendMessage(String roomId, Message message) async {
    final messages = getMessages(roomId);
    messages.add(message);
    await saveMessages(roomId, messages);
  }
}
