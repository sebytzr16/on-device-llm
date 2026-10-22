import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ChatProject {
  final String id, name, instructions, collection;
  const ChatProject(
    this.id,
    this.name, {
    this.instructions = '',
    this.collection = '',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'instructions': instructions,
    'collection': collection,
  };
}

class ConversationWorkspace {
  final List<ChatProject> projects;
  final Map<String, String> memberships, states;
  const ConversationWorkspace({
    this.projects = const [],
    this.memberships = const {},
    this.states = const {},
  });
  ChatProject? projectFor(String? chatId) =>
      projects.where((p) => p.id == memberships[chatId]).firstOrNull;
  String stateOf(String id) => states[id] ?? 'active';
}

final conversationWorkspaceProvider =
    NotifierProvider<ConversationWorkspaceNotifier, ConversationWorkspace>(
      ConversationWorkspaceNotifier.new,
    );

/// A separate versioned metadata contract leaves existing chat rows and branch
/// ancestry untouched. Backups include this key alongside the chat database.
class ConversationWorkspaceNotifier extends Notifier<ConversationWorkspace> {
  static const key = 'conversation_workspace_v1';
  late Future<void> ready;
  Future<void> _pending = Future.value();
  bool _alive = true;
  @override
  ConversationWorkspace build() {
    ref.onDispose(() => _alive = false);
    ready = _load();
    return const ConversationWorkspace();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final j = jsonDecode(prefs.getString(key) ?? '{}') as Map;
      final next = ConversationWorkspace(
        projects: [
          for (final p in (j['projects'] as List? ?? []))
            if (p is Map && p['id'] is String && p['name'] is String)
              ChatProject(
                p['id'],
                p['name'],
                instructions: p['instructions'] as String? ?? '',
                collection: p['collection'] as String? ?? '',
              ),
        ],
        memberships: Map<String, String>.from(j['memberships'] as Map? ?? {}),
        states: Map<String, String>.from(j['states'] as Map? ?? {}),
      );
      if (_alive) state = next;
    } catch (_) {
      /* An unreadable optional workspace must not prevent chat. */
    }
  }

  Future<void> _change(
    ConversationWorkspace Function(ConversationWorkspace) edit,
  ) {
    final next = _pending.then((_) async {
      await ready;
      if (!_alive) return;
      final updated = edit(state);
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        key,
        jsonEncode({
          'projects': updated.projects.map((p) => p.toJson()).toList(),
          'memberships': updated.memberships,
          'states': updated.states,
        }),
      );
      if (!saved) throw StateError('Could not save conversation organization.');
      if (_alive) state = updated;
    });
    _pending = next.catchError((Object _) {});
    return next;
  }

  Future<void> saveProject({
    String? id,
    required String name,
    String instructions = '',
    String collection = '',
  }) => _change((s) {
    if (name.trim().isEmpty ||
        name.length > 100 ||
        instructions.length > 4000 ||
        collection.length > 200) {
      throw const FormatException('Invalid project name or instructions.');
    }
    if (id == null && s.projects.length >= 32) {
      throw StateError('Project limit reached.');
    }
    final project = ChatProject(
      id ?? const Uuid().v4(),
      name.trim(),
      instructions: instructions.trim(),
      collection: collection.trim(),
    );
    return ConversationWorkspace(
      projects: [...s.projects.where((p) => p.id != id), project],
      memberships: s.memberships,
      states: s.states,
    );
  });
  Future<void> assign(Iterable<String> ids, String? projectId) => _change((s) {
    if (projectId != null && !s.projects.any((p) => p.id == projectId)) {
      throw StateError('Project no longer exists.');
    }
    final memberships = {...s.memberships};
    for (final id in ids) {
      if (projectId == null) {
        memberships.remove(id);
      } else {
        memberships[id] = projectId;
      }
    }
    return ConversationWorkspace(
      projects: s.projects,
      memberships: memberships,
      states: s.states,
    );
  });
  Future<void> setState(Iterable<String> ids, String destination) =>
      _change((s) {
        if (!const {'active', 'archived', 'trash'}.contains(destination)) {
          throw ArgumentError(destination);
        }
        final states = {...s.states};
        for (final id in ids) {
          if (destination == 'active') {
            states.remove(id);
          } else {
            states[id] = destination;
          }
        }
        return ConversationWorkspace(
          projects: s.projects,
          memberships: s.memberships,
          states: states,
        );
      });
  Future<void> removeProject(String id) => _change(
    (s) => ConversationWorkspace(
      projects: s.projects.where((p) => p.id != id).toList(),
      memberships: {...s.memberships}..removeWhere((_, v) => v == id),
      states: s.states,
    ),
  );
  Future<void> forget(String id) => _change(
    (s) => ConversationWorkspace(
      projects: s.projects,
      memberships: {...s.memberships}..remove(id),
      states: {...s.states}..remove(id),
    ),
  );
}
