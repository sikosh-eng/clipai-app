import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String serverUrl = 'https://clipai-app.onrender.com';

void main() {
  runApp(const ClipAIApp());
}

class ClipAIApp extends StatelessWidget {
  const ClipAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ClipAI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C3AED),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ClipMakerPage(),
    );
  }
}

class ClipMakerPage extends StatefulWidget {
  const ClipMakerPage({super.key});

  @override
  State<ClipMakerPage> createState() => _ClipMakerPageState();
}

class _ClipMakerPageState extends State<ClipMakerPage> {
  PlatformFile? selectedVideo;

  String numberOfClips = '5 clips';
  String format = '9:16 Shorts';
  String captions = 'Animated';

  bool isAnalyzing = false;
  double progress = 0;

  List<dynamic> clips = [];

  Future<void> pickVideo() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['mp4', 'mov', 'webm', 'mkv'],
    );

    if (file == null) return;

    setState(() {
      selectedVideo = file;
      clips = [];
    });
  }

  Future<void> analyzeVideo() async {
    if (selectedVideo == null) {
      _showMessage('First select a video.');
      return;
    }

    if (selectedVideo!.path == null) {
      _showMessage('Could not access the selected video.');
      return;
    }

    setState(() {
      isAnalyzing = true;
      progress = 0.05;
      clips = [];
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/analyze'),
      );

      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          selectedVideo!.path!,
          filename: selectedVideo!.name,
        ),
      );

      request.fields['numberOfClips'] =
          numberOfClips.split(' ').first;

      request.fields['format'] = format;
      request.fields['captions'] = captions;

      setState(() {
        progress = 0.15;
      });

      final streamedResponse = await request.send();

      setState(() {
        progress = 0.75;
      });

      final response = await http.Response.fromStream(
        streamedResponse,
      );

      setState(() {
        progress = 1.0;
      });

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data = jsonDecode(response.body);

        setState(() {
          clips = data['clips'] ?? [];
          isAnalyzing = false;
        });

        _showMessage(
          'Done! Found ${clips.length} clips.',
        );
      } else {
        String errorMessage = 'Server error';

        try {
          final data = jsonDecode(response.body);

          if (data['error'] != null) {
            errorMessage = data['error'].toString();
          }
        } catch (_) {}

        setState(() {
          isAnalyzing = false;
        });

        _showMessage(errorMessage);
      }
    } catch (e) {
      setState(() {
        isAnalyzing = false;
      });

      _showMessage(
        'Connection error. Check your internet connection.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            24,
            20,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ClipAI',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                'Turn long videos into Shorts',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade400,
                ),
              ),

              const SizedBox(height: 28),

              _sectionTitle('Upload video'),

              const SizedBox(height: 10),

              GestureDetector(
                onTap: isAnalyzing ? null : pickVideo,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141419),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: const Color(0xFF2A2A32),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.cloud_upload_outlined,
                        size: 42,
                        color: Color(0xFFA78BFA),
                      ),

                      const SizedBox(height: 12),

                      Text(
                        selectedVideo == null
                            ? 'Upload your video'
                            : selectedVideo!.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      const SizedBox(height: 6),

                      Text(
                        'MP4, MOV, WebM',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                        ),
                      ),

                      const SizedBox(height: 14),

                      OutlinedButton(
                        onPressed:
                            isAnalyzing ? null : pickVideo,
                        child: Text(
                          selectedVideo == null
                              ? 'Choose Video'
                              : 'Change Video',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _sectionTitle('Number of clips'),

              const SizedBox(height: 10),

              _dropdown(
                value: numberOfClips,
                items: const [
                  '1 clip',
                  '3 clips',
                  '5 clips',
                  '10 clips',
                  '15 clips',
                ],
                onChanged: isAnalyzing
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            numberOfClips = value;
                          });
                        }
                      },
              ),

              const SizedBox(height: 20),

              _sectionTitle('Format'),

              const SizedBox(height: 10),

              _dropdown(
                value: format,
                items: const [
                  '9:16 Shorts',
                  '1:1 Square',
                  '16:9 Landscape',
                ],
                onChanged: isAnalyzing
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            format = value;
                          });
                        }
                      },
              ),

              const SizedBox(height: 20),

              _sectionTitle('Captions'),

              const SizedBox(height: 10),

              _dropdown(
                value: captions,
                items: const [
                  'Animated',
                  'Clean',
                  'Bold',
                  'Minimal',
                  'None',
                ],
                onChanged: isAnalyzing
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() {
                            captions = value;
                          });
                        }
                      },
              ),

              const SizedBox(height: 28),

              if (isAnalyzing) ...[
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141419),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'AI is finding the best moments...',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      LinearProgressIndicator(
                        value: progress,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'This can take a few minutes for long videos.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed:
                      isAnalyzing ? null : analyzeVideo,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF7C3AED),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isAnalyzing
                        ? 'Analyzing...'
                        : 'Find Best Clips',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),

              if (clips.isNotEmpty) ...[
                const SizedBox(height: 32),

                _sectionTitle(
                  'Best clips (${clips.length})',
                ),

                const SizedBox(height: 12),

                ...clips.map(
                  (clip) => _clipCard(clip),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF292930),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF18181D),
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _clipCard(dynamic clip) {
    final title =
        clip['title']?.toString() ?? 'Best moment';

    final reason =
        clip['reason']?.toString() ?? '';

    final score =
        clip['score']?.toString() ?? '';

    final start =
        double.tryParse(
              clip['start']?.toString() ?? '',
            ) ??
            0;

    final end =
        double.tryParse(
              clip['end']?.toString() ?? '',
            ) ??
            0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF141419),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF292930),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                color: Color(0xFFA78BFA),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (score.isNotEmpty)
                Text(
                  '$score/100',
                  style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            reason,
            style: TextStyle(
              color: Colors.grey.shade400,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            '${_formatTime(start)} → ${_formatTime(end)}',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(double seconds) {
    final totalSeconds = seconds.round();

    final minutes = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;

    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }
}
