import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'theme.dart';

/// Voice search: listens once and returns what was said (English), or null. Tests replace this.
Future<String?> Function(BuildContext context) listenOnce = (context) => showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: StallColors.cream,
      builder: (_) => const _VoiceSheet(),
    );

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _stt = SpeechToText();
  String _words = '', _msg = 'Listening… say what you\'re looking for';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ok = await _stt.initialize(
      onError: (e) => mounted ? setState(() => _msg = 'Couldn\'t hear that. Tap the mic to try again.') : null,
    );
    if (!mounted) return;
    if (!ok) return setState(() => _msg = 'Voice search isn\'t available on this phone, or the microphone wasn\'t allowed.');
    // Nigerian English when the phone has it, otherwise the phone's English.
    final locales = await _stt.locales();
    final ng = locales.where((l) => l.localeId.replaceAll('-', '_') == 'en_NG').firstOrNull;
    await _stt.listen(
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.search, localeId: ng?.localeId),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _words = r.recognizedWords);
        if (r.finalResult && _words.trim().isNotEmpty) Navigator.pop(context, _words.trim());
      },
    );
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            IconButton.filled(
              iconSize: 36,
              onPressed: () {
                _stt.cancel();
                setState(() {
                  _words = '';
                  _msg = 'Listening… say what you\'re looking for';
                });
                _start();
              },
              icon: const Icon(Icons.mic_rounded),
            ),
            const SizedBox(height: 14),
            Text(_words.isEmpty ? _msg : _words, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
      );
}
