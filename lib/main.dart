import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ClipAIApp());
}

class ClipAIApp extends StatelessWidget {
  const ClipAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClipAI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08080A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF7C5CFF),
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
  static const String serverUrl = 'https://clipai-app.onrender.com';

  final TextEditingController urlController = TextEditingController();

  PlatformFile? selectedVideo;

  String numberOfClips = '5 clips';
  String videoFormat = '9:16 Shorts';
  String captionsStyle = 'Animated';

  bool isAnalyzing = false;

  List<dynamic> clips = [];
  String? errorMessage;

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  Future<void> pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      setState(() {
        selectedVideo = result.files.first;
        urlController.clear();
        errorMessage = null;
        clips = [];
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Could not select video: $e';
      });
    }
  }

  Future<void> analyzeVideo() async {
    final url = urlController.text.trim();

    if (selectedVideo == null && url.isEmpty) {
      showMessage('Upload a video or paste a YouTube URL.');
      return;
    }

    if (url.isNotEmpty && !isYouTubeUrl(url)) {
      showMessage('Please enter a valid YouTube URL.');
      return;
    }

    setState(() {
      isAnalyzing = true;
      errorMessage = null;
      clips = [];
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/analyze'),
      );

      request.fields['numberOfClips'] =
          numberOfClips.split(' ').first;

      request.fields['format'] = videoFormat;
      request.fields['captions'] = captionsStyle;

      if (url.isNotEmpty) {
        request.fields['url'] = url;
      }

      if (selectedVideo != null && selectedVideo!.path != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'video',
            selectedVideo!.path!,
            filename: selectedVideo!.name,
          ),
        );
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(
        streamedResponse,
      );

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        String message =
            'Server error: ${response.statusCode}';

        try {
          final data = jsonDecode(response.body);

          if (data is Map && data['error'] != null) {
            message = data['error'].toString();
          }
        } catch (_) {}

        throw Exception(message);
      }

      final data = jsonDecode(response.body);

      if (data is! Map) {
        throw Exception('Invalid server response.');
      }

      final returnedClips = data['clips'];

      if (returnedClips is List) {
        setState(() {
          clips = returnedClips;
        });
      }

      if (clips.isEmpty) {
        throw Exception(
          'AI could not find suitable clips.',
        );
      }

      showMessage(
        'AI found ${clips.length} clips.',
      );
    } catch (e) {
      setState(() {
        errorMessage = e
            .toString()
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          isAnalyzing = false;
        });
      }
    }
  }

  bool isYouTubeUrl(String value) {
    try {
      final uri = Uri.parse(value);

      final host = uri.host
          .toLowerCase()
          .replaceFirst('www.', '');

      return host == 'youtube.com' ||
          host == 'youtu.be' ||
          host == 'm.youtube.com';
    } catch (_) {
      return false;
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF15151A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          dropdownColor: const Color(0xFF19191F),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget buildUploadCard() {
    return InkWell(
      onTap: pickVideo,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 28,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF121217),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white12,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF201B35),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.video_library_rounded,
                color: Color(0xFF9B7CFF),
                size: 28,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              selectedVideo == null
                  ? 'Upload a video'
                  : selectedVideo!.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              selectedVideo == null
                  ? 'MP4, MOV or WebM'
                  : 'Video selected',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: pickVideo,
              child: const Text('Choose video'),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildUrlCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121217),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.link_rounded,
                color: Color(0xFF9B7CFF),
              ),
              SizedBox(width: 10),
              Text(
                'Video URL',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: urlController,
            onChanged: (_) {
              if (selectedVideo != null) {
                setState(() {
                  selectedVideo = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText: 'Paste YouTube URL',
              filled: true,
              fillColor: const Color(0xFF09090C),
              prefixIcon: const Icon(
                Icons.smart_display_outlined,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildClipCard(dynamic clip, int index) {
    final title =
        clip is Map ? clip['title']?.toString() : null;

    final score =
        clip is Map ? clip['score']?.toString() : null;

    final reason =
        clip is Map ? clip['reason']?.toString() : null;

    final start =
        clip is Map ? clip['start']?.toString() : null;

    final end =
        clip is Map ? clip['end']?.toString() : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121217),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white10,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF211A39),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title ?? 'Best Moment ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (score != null)
                Text(
                  '$score/100',
                  style: const TextStyle(
                    color: Color(0xFF9B7CFF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (reason != null && reason.isNotEmpty)
            Text(
              reason,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.4,
              ),
            ),
          const SizedBox(height: 12),
          if (start != null && end != null)
            Text(
              '$start s → $end s',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
              ),
            ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0B0B0E),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              clip is Map && clip['url'] != null
                  ? '$serverUrl${clip['url']}'
                  : 'Clip generated',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'ClipAI',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            18,
            10,
            18,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn long videos\ninto Shorts',
                style: TextStyle(
                  fontSize: 32,
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'AI finds the strongest moments automatically.',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),

              buildUrlCard(),

              const SizedBox(height: 12),

              Row(
                children: [
                  const Expanded(
                    child: Divider(
                      color: Colors.white12,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                    ),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Expanded(
                    child: Divider(
                      color: Colors.white12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              buildUploadCard(),

              const SizedBox(height: 24),

              buildDropdown(
                label: 'Number of clips',
                value: numberOfClips,
                items: const [
                  '1 clip',
                  '3 clips',
                  '5 clips',
                  '10 clips',
                  '15 clips',
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      numberOfClips = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 16),

              buildDropdown(
                label: 'Format',
                value: videoFormat,
                items: const [
                  '9:16 Shorts',
                  '1:1 Square',
                  '16:9 Landscape',
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      videoFormat = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 16),

              buildDropdown(
                label: 'Captions',
                value: captionsStyle,
                items: const [
                  'Animated',
                  'Bold',
                  'Minimal',
                  'None',
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      captionsStyle = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed:
                      isAnalyzing ? null : analyzeVideo,
                  icon: isAnalyzing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.auto_awesome,
                        ),
                  label: Text(
                    isAnalyzing
                        ? 'AI is finding the best clips...'
                        : 'Find Best Clips',
                  ),
                ),
              ),

              if (isAnalyzing) ...[
                const SizedBox(height: 18),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Transcribing video and analyzing moments...',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],

              if (errorMessage != null) ...[
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF32171A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              ],

              if (clips.isNotEmpty) ...[
                const SizedBox(height: 30),
                const Text(
                  'Best Clips',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(
                  clips.length,
                  (index) => buildClipCard(
                    clips[index],
                    index,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
