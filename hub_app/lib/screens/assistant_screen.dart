import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/providers.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = false;

  static const _suggestions = [
    'Quelle est la règle sur la prière en voyage ?',
    'Comment faire la prière du Fajr ?',
    'Qu\'est-ce que la Zakat al-Fitr ?',
    'Quels sont les piliers de l\'Islam ?',
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final prefs = ref.watch(prefsProvider);

    return Scaffold(
      body: Column(children: [
        // AppBar
        SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(children: [
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Assistant islamique', style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              Text('Madhab : ${prefs.madhab}', style: GoogleFonts.inter(
                fontSize: 11, color: AppColors.textMuted)),
            ]),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
              onPressed: () => ref.read(chatProvider.notifier).clear(),
            ),
          ]),
        )),
        const Divider(color: AppColors.bgCardLight, height: 1),

        // Messages
        Expanded(
          child: messages.isEmpty
            ? _EmptyState(suggestions: _suggestions, onSuggest: _send)
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length + (_loading ? 1 : 0),
                itemBuilder: (_, i) {
                  if (_loading && i == messages.length) return const _TypingBubble();
                  return _MessageBubble(message: messages[i], index: i);
                },
              ),
        ),

        // Input
        _ChatInput(
          ctrl: _ctrl,
          loading: _loading,
          onSend: () => _send(_ctrl.text.trim()),
        ),
      ]),
    );
  }

  Future<void> _send(String text) async {
    if (text.isEmpty || _loading) return;
    _ctrl.clear();

    final prefs = ref.read(prefsProvider);
    final history = ref.read(chatProvider);

    ref.read(chatProvider.notifier).addMessage(
      ChatMessage(role: 'user', content: text));
    setState(() => _loading = true);
    _scrollToBottom();

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.sendMessage(
        message: text,
        madhab: prefs.madhab,
        language: prefs.language,
        history: history,
      );
      ref.read(chatProvider.notifier).addMessage(
        ChatMessage(role: 'assistant', content: response.answer));
    } catch (e) {
      ref.read(chatProvider.notifier).addMessage(ChatMessage(
        role: 'assistant',
        content: '❌ Hub non connecté. Vérifiez l\'adresse IP dans les paramètres.'));
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: 300.ms, curve: Curves.easeOut);
      }
    });
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final int index;
  const _MessageBubble({required this.message, required this.index});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
            ? AppColors.emerald.withValues(alpha: 0.2)
            : AppColors.bgCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isUser
            ? Border.all(color: AppColors.emerald.withValues(alpha: 0.3))
            : null,
        ),
        child: Text(message.content, style: GoogleFonts.inter(
          fontSize: 14, color: Colors.white, height: 1.5)),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05);
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < 3; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: AppColors.emerald, shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat())
            .fadeOut(duration: 600.ms, delay: (i * 200).ms)
            .then().fadeIn(duration: 600.ms),
      ]),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onSuggest;
  const _EmptyState({required this.suggestions, required this.onSuggest});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const SizedBox(height: 40),
      Center(child: Text('🕌', style: GoogleFonts.inter(fontSize: 48))),
      const SizedBox(height: 12),
      Center(child: Text('Posez une question islamique',
        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white))),
      Center(child: Text('Fiqh, Quran, Hadith, Deen',
        style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted))),
      const SizedBox(height: 32),
      ...suggestions.map((s) => GestureDetector(
        onTap: () => onSuggest(s),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.bgCardLight)),
          child: Row(children: [
            const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textMuted, size: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(s, style: GoogleFonts.inter(fontSize: 13, color: Colors.white))),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 12),
          ]),
        ),
      )),
    ],
  );
}

class _ChatInput extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onSend;
  const _ChatInput({required this.ctrl, required this.loading, required this.onSend});

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
    decoration: const BoxDecoration(
      color: AppColors.bgCard,
      border: Border(top: BorderSide(color: AppColors.bgCardLight))),
    child: Row(children: [
      Expanded(
        child: TextField(
          controller: ctrl,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          maxLines: null,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSend(),
          decoration: InputDecoration(
            hintText: 'Votre question...',
            hintStyle: GoogleFonts.inter(color: AppColors.textMuted),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: onSend,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: loading ? AppColors.bgCardLight : AppColors.emerald,
            borderRadius: BorderRadius.circular(12)),
          child: loading
            ? const SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    ]),
  );
}
