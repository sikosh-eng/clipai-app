import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ClipAIApp());
}

class ClipAIApp extends StatelessWidget {
  const ClipAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Clipper',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090D),
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const ClipperHome(),
    );
  }
}

class ClipperHome extends StatefulWidget {
  const ClipperHome({super.key});

  @override
  State<ClipperHome> createState() => _ClipperHomeState();
}

class _ClipperHomeState extends State<ClipperHome> {
  final TextEditingController urlController =
      TextEditingController();

  String numberOfClips = '5 clips';
  String format = '9:16 Shorts';
  String captions = 'Animated';

  String? selectedVideo;

  Future<void> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result == null) return;

    final path = result.files.single.path;

    if (path == null) return;

    final file = File(path);

    if (!file.existsSync()) return;

    setState(() {
      selectedVideo = result.files.single.name;
    });
  }

  void analyzeVideo() {
    if (selectedVideo == null &&
        urlController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Upload a video or paste a video URL first.',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17171D),
          title: const Text('AI Clipper'),
          content: const Text(
            'Your video is ready for AI analysis.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Color(0xFFFF3B7A),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            32,
            28,
            32,
            40,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LOGO
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFFF2875),
                          Color(0xFFFF534D),
                        ],
                      ),
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),

                  const SizedBox(width: 13),

                  const Text(
                    'ClipAI',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 45),

              // TITLE
              const Text(
                'Turn long videos into\nviral short clips.',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),

              const SizedBox(height: 18),

              Text(
                'Upload your video and let ClipAI find the most '
                'interesting moments.',
                style: TextStyle(
                  fontSize: 16,
                  height: 1.5,
                  color: Colors.white.withOpacity(.55),
                ),
              ),

              const SizedBox(height: 30),

              // MAIN CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  28,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF15151B),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // VIDEO URL
                    Text(
                      'Video URL',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(.65),
                      ),
                    ),

                    const SizedBox(height: 10),

                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E0E13),
                        borderRadius:
                            BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withOpacity(.10),
                        ),
                      ),
                      child: TextField(
                        controller: urlController,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Paste YouTube video URL...',
                          hintStyle: TextStyle(
                            color:
                                Colors.white.withOpacity(.35),
                          ),
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 18,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // OR
                    Center(
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 17,
                          color: Colors.white
                              .withOpacity(.45),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // UPLOAD AREA
                    GestureDetector(
                      onTap: pickVideo,
                      child: Container(
                        width: double.infinity,
                        height: 260,
                        decoration: BoxDecoration(
                          color: const Color(0xFF101015),
                          borderRadius:
                              BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFF3A3A45),
                            width: 1.2,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFFF2875,
                                ).withOpacity(.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.movie_creation_outlined,
                                size: 40,
                                color: Color(0xFFFF2875),
                              ),
                            ),

                            const SizedBox(height: 20),

                            Text(
                              selectedVideo ??
                                  'Upload your video',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 8),

                            Text(
                              'MP4, MOV, WebM',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white
                                    .withOpacity(.40),
                              ),
                            ),

                            const SizedBox(height: 20),

                            Container(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                gradient:
                                    const LinearGradient(
                                  colors: [
                                    Color(0xFFFF2875),
                                    Color(0xFFFF4D62),
                                  ],
                                ),
                                borderRadius:
                                    BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Choose Video',
                                style: TextStyle(
                                  fontWeight:
                                      FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // SETTINGS CARD
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  24,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF15151B),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withOpacity(.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // NUMBER OF CLIPS
                    _label('Number of clips'),

                    const SizedBox(height: 10),

                    _dropdown(
                      value: numberOfClips,
                      items: const [
                        '3 clips',
                        '5 clips',
                        '10 clips',
                        '15 clips',
                        '20 clips',
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          numberOfClips = value;
                        });
                      },
                    ),

                    const SizedBox(height: 22),

                    // FORMAT
                    _label('Format'),

                    const SizedBox(height: 10),

                    _dropdown(
                      value: format,
                      items: const [
                        '9:16 Shorts',
                        '16:9 Landscape',
                        '1:1 Square',
                        '4:5 Portrait',
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          format = value;
                        });
                      },
                    ),

                    const SizedBox(height: 22),

                    // CAPTIONS
                    _label('Captions'),

                    const SizedBox(height: 10),

                    _dropdown(
                      value: captions,
                      items: const [
                        'Animated',
                        'Classic',
                        'Bold',
                        'Minimal',
                        'None',
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          captions = value;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ANALYZE BUTTON
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: analyzeVideo,
                  icon: const Icon(
                    Icons.auto_awesome,
                  ),
                  label: const Text(
                    'Find Best Clips',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFFF2875),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(15),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        color: Colors.white.withOpacity(.65),
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E13),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withOpacity(.10),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF18181F),
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: Colors.white70,
          ),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
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
}
