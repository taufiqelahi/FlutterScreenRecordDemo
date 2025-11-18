// lib/main.dart
import 'package:ffmpeg_kit_flutter_new_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min_gpl/return_code.dart';

import 'package:flutter/material.dart';
import 'package:flutter_screen_recording/flutter_screen_recording.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gallery_saver_plus/gallery_saver.dart' as gallery_saver;


void main() {
  runApp(const ScreenRecordDemoApp());
}

class ScreenRecordDemoApp extends StatelessWidget {
  const ScreenRecordDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Screen Recording Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ScreenRecorderPage(),
    );
  }
}

class ScreenRecorderPage extends StatefulWidget {
  const ScreenRecorderPage({super.key});

  @override
  State<ScreenRecorderPage> createState() => _ScreenRecorderPageState();
}

class _ScreenRecorderPageState extends State<ScreenRecorderPage> {
  bool _isRecording = false;
  String? _lastVideoPath;
  String _status = 'Idle';

  Future<bool> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    final storageStatus = await Permission.storage.request(); // optional

    debugPrint('mic: $micStatus, storage: $storageStatus');

    if (!micStatus.isGranted) {
      setState(() {
        _status = 'Microphone permission not granted';
      });
      return false;
    }

    // ✅ Mic granted → allow recording even if storage is denied
    return true;
  }


  Future<void> _startRecording({bool withAudio = true}) async {
    if (!await _requestPermissions()) return;

    setState(() {
      _status = 'Starting recording...';
    });

    try {
      final fileName =
          'screen_${DateTime.now().millisecondsSinceEpoch.toString()}';

      bool started;
      if (withAudio) {
        started = await FlutterScreenRecording.startRecordScreenAndAudio(
          fileName,
          titleNotification: 'Screen Recording',
          messageNotification: 'Recording in progress…',
        );
      } else {
        started = await FlutterScreenRecording.startRecordScreen(
          fileName,
          titleNotification: 'Screen Recording',
          messageNotification: 'Recording in progress…',
        );
      }

      setState(() {
        _isRecording = started;
        _status = started ? 'Recording...' : 'Failed to start recording';
      });
    } catch (e) {
      setState(() {
        _status = 'Error starting recording: $e';
        _isRecording = false;
      });
    }
  }
  Future<String?> _denoiseVideo(String inputPath) async {
    // create new output file path
    final outputPath = inputPath.replaceFirst('.mp4', '_denoised.mp4');

    // Simple noise reduction filter with FFmpeg (tweak nf value as needed)
    final cmd = "-y -i '$inputPath' -af afftdn=nf=-25 '$outputPath'";

    final session = await FFmpegKit.execute(cmd);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) {
      debugPrint('Denoise success: $outputPath');
      return outputPath;
    } else {
      debugPrint('Denoise failed: $returnCode');
      return null;
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    setState(() {
      _status = 'Stopping recording...';
    });

    try {
      // 1) Stop recording, get local path from flutter_screen_recording
      final path = await FlutterScreenRecording.stopRecordScreen;
      final denoisedPath = await _denoiseVideo(path) ?? path;

      // 2) Save that file into system gallery / Photos using gallery_saver_plus
      bool? saved;
      if (path.isNotEmpty) {
        saved = await gallery_saver.GallerySaver.saveVideo(denoisedPath);
      }

      setState(() {
        _isRecording = false;
        _lastVideoPath = path;

        if (saved == true) {
          _status = 'Recording saved to gallery.\nPath: $path';
        } else {
          _status = 'Recording stopped, but gallery save failed.\nPath: $path';
        }
      });
    } catch (e) {
      setState(() {
        _status = 'Error stopping recording: $e';
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Screen Recording'),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Status: $_status',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _isRecording
                      ? null
                      : () => _startRecording(withAudio: true),
                  icon: const Icon(Icons.mic),
                  label: const Text('Start (with audio)'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isRecording
                      ? null
                      : () => _startRecording(withAudio: false),
                  icon: const Icon(Icons.volume_off),
                  label: const Text('Start (no audio)'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isRecording ? _stopRecording : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.stop),
              label: const Text('Stop & Save'),
            ),
            const SizedBox(height: 24),
            if (_lastVideoPath != null) ...[
              const Text(
                'Last recorded file:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SelectableText(
                _lastVideoPath!,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
