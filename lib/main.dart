import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      debugShowCheckedModeBanner: false,
      title: 'ClipAI',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String serverUrl =
      'https://clipai-app.onrender.com';

  final TextEditingController urlController =
      TextEditingController();

  File? selectedVideo;

  String numberOfClips = '5 clips';
  String format = '9:16 Shorts';
  String captions = 'Animated';

  bool loading = false;
  bool testingConnection = false;

  List<dynamic> clips = [];

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  Future<void> pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'mp4',
          'mov',
          'webm',
          'mkv',
        ],
      );

      if (result == null ||
          result.files.single.path == null) {
        return;
      }

      setState(() {
        selectedVideo =
            File(result.files.single.path!);
        urlController.clear();
      });
    } catch (e) {
      showError('Could not select video:\n\n$e');
    }
  }

  int getClipCount() {
    switch (numberOfClips) {
      case '1 clip':
        return 1;
      case '3 clips':
        return 3;
      case '5 clips':
        return 5;
      case '10 clips':
        return 10;
      case '15 clips':
        return 15;
      default:
        return 5;
    }
  }

  Future<void> testConnection() async {
    if (testingConnection || loading) return;

    setState(() {
      testingConnection = true;
    });

    final results = <String>[];

    // TEST 1 — Internet
    try {
      final response = await http
          .get(
            Uri.parse('https://example.com'),
          )
          .timeout(
            const Duration(seconds: 10),
          );

      results.add(
        '🌐 Internet: OK\n'
        'HTTP ${response.statusCode}',
      );
    } on SocketException catch (e) {
      results.add(
        '❌ Internet: FAILED\n'
        '$e',
      );
    } on TimeoutException {
      results.add(
        '❌ Internet: TIMEOUT',
      );
    } catch (e) {
      results.add(
        '❌ Internet: FAILED\n'
        '$e',
      );
    }

    // TEST 2 — DNS
    try {
      final addresses =
          await InternetAddress.lookup(
        'clipai-app.onrender.com',
      ).timeout(
        const Duration(seconds: 10),
      );

      if (addresses.isNotEmpty) {
        results.add(
          '🔎 DNS: OK\n'
          '${addresses.map((e) => e.address).join(', ')}',
        );
      } else {
        results.add(
          '❌ DNS: NO ADDRESS FOUND',
        );
      }
    } on SocketException catch (e) {
      results.add(
        '❌ DNS: FAILED\n'
        '$e',
      );
    } on TimeoutException {
      results.add(
        '❌ DNS: TIMEOUT',
      );
    } catch (e) {
      results.add(
        '❌ DNS: FAILED\n'
        '$e',
      );
    }

    // TEST 3 — Render
    try {
      final response = await http
          .get(
            Uri.parse('$serverUrl/'),
          )
          .timeout(
            const Duration(seconds: 15),
          );

      results.add(
        '🟢 Render: OK\n'
        'HTTP ${response.statusCode}\n\n'
        '${response.body}',
      );
    } on SocketException catch (e) {
      results.add(
        '❌ Render: FAILED\n'
        '$e',
      );
    } on TimeoutException {
      results.add(
        '❌ Render: TIMEOUT',
      );
    } catch (e) {
      results.add(
        '❌ Render: FAILED\n'
        '$e',
      );
    }

    if (!mounted) return;

    setState(() {
      testingConnection = false;
    });

    showError(
      results.join('\n\n--------------------\n\n'),
    );
  }

  Future<void> analyzeVideo() async {
    if (loading || testingConnection) return;

    final youtubeUrl =
        urlController.text.trim();

    if (selectedVideo == null &&
        youtubeUrl.isEmpty) {
      showError(
        'Upload a video or paste a YouTube URL first.',
      );
      return;
    }

    setState(() {
      loading = true;
      clips = [];
    });

    try {
      final uri =
          Uri.parse('$serverUrl/api/analyze');

      final request =
          http.MultipartRequest(
        'POST',
        uri,
      );

      request.fields['numberOfClips'] =
          getClipCount().toString();

      request.fields['format'] = format;
      request.fields['captions'] = captions;

      if (youtubeUrl.isNotEmpty) {
        request.fields['url'] = youtubeUrl;
      }

      if (selectedVideo != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'video',
            selectedVideo!.path,
          ),
        );
      }

      final streamedResponse =
          await request.send().timeout(
        const Duration(minutes: 10),
      );

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      if (!mounted) return;

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data =
            jsonDecode(response.body);

        setState(() {
          loading = false;
          clips = data['clips'] ?? [];
        });

        if (clips.isEmpty) {
          showError(
            'The server finished, but no clips were returned.',
          );
        }
      } else {
        setState(() {
          loading = false;
        });

        String message = response.body;

        try {
          final data =
              jsonDecode(response.body);

          message =
              data['error']?.toString() ??
                  response.body;
        } catch (_) {}

        showError(
          'Server error ${response.statusCode}:\n\n$message',
        );
      }
    } on SocketException catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showError(
        'Socket / DNS error.\n\n'
        'The app cannot connect to:\n'
        '$serverUrl\n\n'
        '$e',
      );
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showError(
        'Request timed out.\n\n'
        'The server took too long to respond.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      showError(
        'Unexpected error:\n\n$e',
      );
    }
  }

  void showError(String message) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ClipAI Diagnostics'),
          content: SingleChildScrollView(
            child: SelectableText(message),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget buildDropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF18181B),
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor:
              const Color(0xFF18181B),
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget buildSectionTitle(String title) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget buildUploadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'Upload a video',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            selectedVideo == null
                ? 'MP4, MOV, WebM or MKV'
                : selectedVideo!.path
                    .split('/')
                    .last,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  Colors.white.withOpacity(0.55),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed:
                loading ? null : pickVideo,
            icon: const Icon(
              Icons.upload_file,
            ),
            label:
                const Text('Choose video'),
          ),
        ],
      ),
    );
  }

  Widget buildUrlCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Video URL',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: urlController,
            enabled: !loading,
            onChanged: (value) {
              if (value.trim().isNotEmpty &&
                  selectedVideo != null) {
                setState(() {
                  selectedVideo = null;
                });
              }
            },
            decoration: InputDecoration(
              hintText:
                  'Paste YouTube URL',
              prefixIcon:
                  const Icon(Icons.link),
              filled: true,
              fillColor:
                  const Color(0xFF1B1B1F),
              border:
                  OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(14),
                borderSide:
                    BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildResultCard(
    dynamic clip,
    int index,
  ) {
    final title =
        clip['title']?.toString() ??
            'Clip ${index + 1}';

    final score =
        clip['score']?.toString() ?? '-';

    final url =
        clip['url']?.toString() ?? '';

    return Container(
      width: double.infinity,
      margin:
          const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF121214),
        borderRadius:
            BorderRadius.circular(18),
        border: Border.all(
          color:
              Colors.white.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text('AI Score: $score'),
          if (url.isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(
              url,
              style: TextStyle(
                color:
                    Colors.deepPurple.shade200,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            Colors.transparent,
        title: const Text(
          'ClipAI',
          style: TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Test connection',
            onPressed:
                testingConnection || loading
                    ? null
                    : testConnection,
            icon: const Icon(
              Icons.network_check,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            30,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Turn long videos into Shorts',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI finds the best moments automatically.',
                style: TextStyle(
                  color:
                      Colors.white.withOpacity(0.55),
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed:
                      testingConnection ||
                              loading
                          ? null
                          : testConnection,
                  icon: const Icon(
                    Icons.network_check,
                  ),
                  label: Text(
                    testingConnection
                        ? 'Testing connection...'
                        : 'Test Connection',
                  ),
                ),
              ),

              const SizedBox(height: 18),

              buildUrlCard(),

              const SizedBox(height: 14),

              const Center(
                child: Text(
                  'OR',
                  style: TextStyle(
                    color: Colors.white54,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              buildUploadCard(),

              const SizedBox(height: 24),

              buildSectionTitle(
                'Number of clips',
              ),

              buildDropdown(
                value: numberOfClips,
                items: const [
                  '1 clip',
                  '3 clips',
                  '5 clips',
                  '10 clips',
                  '15 clips',
                ],
                onChanged: (value) {
                  if (value != null &&
                      !loading) {
                    setState(() {
                      numberOfClips = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 18),

              buildSectionTitle('Format'),

              buildDropdown(
                value: format,
                items: const [
                  '9:16 Shorts',
                  '1:1 Square',
                  '16:9 Landscape',
                ],
                onChanged: (value) {
                  if (value != null &&
                      !loading) {
                    setState(() {
                      format = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 18),

              buildSectionTitle('Captions'),

              buildDropdown(
                value: captions,
                items: const [
                  'Animated',
                  'Bold',
                  'Minimal',
                  'None',
                ],
                onChanged: (value) {
                  if (value != null &&
                      !loading) {
                    setState(() {
                      captions = value;
                    });
                  }
                },
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed:
                      loading ||
                              testingConnection
                          ? null
                          : analyzeVideo,
                  child: loading
                      ? const Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,
                          children: [
                            SizedBox(
                              width: 21,
                              height: 21,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Finding best clips...',
                            ),
                          ],
                        )
                      : const Text(
                          'Find Best Clips',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                ),
              ),

              if (clips.isNotEmpty) ...[
                const SizedBox(height: 30),
                const Text(
                  'Best Clips',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                ...List.generate(
                  clips.length,
                  (index) {
                    return buildResultCard(
                      clips[index],
                      index,
                    );
                  },
                ),
              ]
