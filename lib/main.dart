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
        scaffoldBackgroundColor: const Color(0xFF08080B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE91E63),
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
  final TextEditingController urlController =
      TextEditingController();

  PlatformFile? selectedVideo;

  String numberOfClips = '5 clips';
  String format = '9:16 Shorts';
  String captions = 'Bold';

  bool isAnalyzing = false;
  double progress = 0;

  String statusText = '';

  List<dynamic> clips = [];

  @override
  void dispose() {
    urlController.dispose();
    super.dispose();
  }

  Future<void> pickVideo() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'mp4',
        'mov',
        'webm',
        'mkv',
      ],
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    setState(() {
      selectedVideo = result.files.first;
      urlController.clear();
      clips = [];
    });
  }

  void clearVideo() {
    setState(() {
      selectedVideo = null;
    });
  }

  Future<void> analyzeVideo() async {
    final url = urlController.text.trim();

    final hasUrl = url.isNotEmpty;
    final hasFile =
        selectedVideo != null &&
        selectedVideo!.path != null;

    if (!hasUrl && !hasFile) {
      showMessage(
        'Paste a video URL or choose a video file.',
      );
      return;
    }

    if (hasUrl && !isValidYouTubeUrl(url)) {
      showMessage(
        'Please enter a valid YouTube URL.',
      );
      return;
    }

    setState(() {
      isAnalyzing = true;
      progress = 0.05;
      clips = [];
      statusText = 'Preparing video...';
    });

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/api/analyze'),
      );

      /*
       * URL MODE
       */
      if (hasUrl) {
        request.fields['url'] = url;
      }

      /*
       * FILE MODE
       */
      if (hasFile) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'video',
            selectedVideo!.path!,
            filename: selectedVideo!.name,
          ),
        );
      }

      request.fields['numberOfClips'] =
          numberOfClips.split(' ').first;

      request.fields['format'] = format;
      request.fields['captions'] = captions;

      setState(() {
        progress = 0.12;
        statusText = hasUrl
            ? 'Getting your video...'
            : 'Uploading your video...';
      });

      final streamedResponse =
          await request.send();

      setState(() {
        progress = 0.70;
        statusText =
            'AI is finding the best moments...';
      });

      final response =
          await http.Response.fromStream(
        streamedResponse,
      );

      setState(() {
        progress = 0.90;
        statusText = 'Creating your clips...';
      });

      if (response.statusCode >= 200 &&
          response.statusCode < 300) {
        final data = jsonDecode(response.body);

        final receivedClips =
            data['clips'] ?? [];

        setState(() {
          clips = receivedClips;
          progress = 1.0;
          isAnalyzing = false;
          statusText = 'Finished!';
        });

        showMessage(
          'Done! Found ${clips.length} clips.',
        );
      } else {
        String errorMessage =
            'Server error: ${response.statusCode}';

        try {
          final data =
              jsonDecode(response.body);

          if (data['error'] != null) {
            errorMessage =
                data['error'].toString();
          }
        } catch (_) {}

        setState(() {
          isAnalyzing = false;
          statusText = '';
        });

        showMessage(errorMessage);
      }
    } catch (error) {
      setState(() {
        isAnalyzing = false;
        statusText = '';
      });

      showMessage(
        'Connection error. Please try again.',
      );
    }
  }

  bool isValidYouTubeUrl(String value) {
    try {
      final uri = Uri.parse(value);

      final host =
          uri.host.toLowerCase();

      return host == 'youtube.com' ||
          host == 'www.youtube.com' ||
          host == 'm.youtube.com' ||
          host == 'youtu.be' ||
          host == 'www.youtu.be';
    } catch (_) {
      return false;
    }
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
        behavior:
            SnackBarBehavior.floating,
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
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Clipper',
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

              /*
               * URL
               */

              const Text(
                'Video URL',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              Container(
                decoration: BoxDecoration(
                  color:
                      const Color(0xFF141419),
                  borderRadius:
                      BorderRadius.circular(16),
                  border: Border.all(
                    color:
                        const Color(0xFF292930),
                  ),
                ),
                child: TextField(
                  controller: urlController,
                  enabled: !isAnalyzing,
                  keyboardType:
                      TextInputType.url,
                  textInputAction:
                      TextInputAction.done,
                  onChanged: (_) {
                    if (selectedVideo != null) {
                      setState(() {
                        selectedVideo = null;
                      });
                    }
                  },
                  decoration:
                      InputDecoration(
                    hintText:
                        'Paste YouTube URL',
                    hintStyle: TextStyle(
                      color:
                          Colors.grey.shade600,
                    ),
                    prefixIcon:
                        const Icon(
                      Icons.link,
                    ),
                    suffixIcon:
                        urlController.text
                                .isNotEmpty
                            ? IconButton(
                                onPressed:
                                    isAnalyzing
                                        ? null
                                        : () {
                                            urlController
                                                .clear();
                                            setState(
                                              () {},
                                            );
                                          },
                                icon:
                                    const Icon(
                                  Icons.clear,
                                ),
                              )
                            : null,
                    border:
                        InputBorder.none,
                    contentPadding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 16,
                      vertical: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              const Row(
                children: [
                  Expanded(
                    child: Divider(),
                  ),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(
                      horizontal: 12,
                    ),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        color:
                            Colors.grey,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              /*
               * UPLOAD
               */

              GestureDetector(
                onTap:
                    isAnalyzing
                        ? null
                        : pickVideo,
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.all(
                    22,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF141419,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color:
                          const Color(
                        0xFF2A2A32,
                      ),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons
                            .cloud_upload_outlined,
                        size: 42,
                        color:
                            Color(
                          0xFFE91E63,
                        ),
                      ),

                      const SizedBox(
                        height: 12,
                      ),

                      Text(
                        selectedVideo ==
                                null
                            ? 'Upload your video'
                            : selectedVideo!
                                .name,
                        textAlign:
                            TextAlign.center,
                        style:
                            const TextStyle(
                          fontSize: 16,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),

                      const SizedBox(
                        height: 6,
                      ),

                      Text(
                        'MP4, MOV, WebM',
                        style:
                            TextStyle(
                          color: Colors
                              .grey
                              .shade500,
                        ),
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      OutlinedButton(
                        onPressed:
                            isAnalyzing
                                ? null
                                : pickVideo,
                        child: Text(
                          selectedVideo ==
                                  null
                              ? 'Choose Video'
                              : 'Change Video',
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              /*
               * NUMBER OF CLIPS
               */

              const Text(
                'Number of clips',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              buildDropdown(
                value: numberOfClips,
                items: const [
                  '1 clip',
                  '3 clips',
                  '5 clips',
                  '10 clips',
                  '15 clips',
                ],
                onChanged:
                    isAnalyzing
                        ? null
                        : (value) {
                            if (value !=
                                null) {
                              setState(() {
                                numberOfClips =
                                    value;
                              });
                            }
                          },
              ),

              const SizedBox(height: 20),

              /*
               * FORMAT
               */

              const Text(
                'Format',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              buildDropdown(
                value: format,
                items: const [
                  '9:16 Shorts',
                  '1:1 Square',
                  '16:9 Landscape',
                ],
                onChanged:
                    isAnalyzing
                        ? null
                        : (value) {
                            if (value !=
                                null) {
                              setState(() {
                                format =
                                    value;
                              });
                            }
                          },
              ),

              const SizedBox(height: 20),

              /*
               * CAPTIONS
               */

              const Text(
                'Captions',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(height: 10),

              buildDropdown(
                value: captions,
                items: const [
                  'Animated',
                  'Bold',
                  'Clean',
                  'Minimal',
                  'None',
                ],
                onChanged:
                    isAnalyzing
                        ? null
                        : (value) {
                            if (value !=
                                null) {
                              setState(() {
                                captions =
                                    value;
                              });
                            }
                          },
              ),

              const SizedBox(height: 26),

              /*
               * PROGRESS
               */

              if (isAnalyzing) ...[
                Container(
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets.all(
                    18,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF141419,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(
                              strokeWidth:
                                  2,
                            ),
                          ),
                          const SizedBox(
                            width: 12,
                          ),
                          Expanded(
                            child: Text(
                              statusText,
                              style:
                                  const TextStyle(
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(
                        height: 14,
                      ),

                      LinearProgressIndicator(
                        value:
                            progress,
                        borderRadius:
                            BorderRadius
                                .circular(
                          20,
                        ),
                      ),

                      const SizedBox(
                        height: 8,
                      ),

                      Text(
                        '${(progress * 100).round()}%',
                        style:
                            TextStyle(
                          fontSize: 12,
                          color: Colors
                              .grey
                              .shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(
                  height: 20,
                ),
              ],

              /*
               * FIND BUTTON
               */

              SizedBox(
                width: double.infinity,
                height: 58,
                child:
                    FilledButton.icon(
                  onPressed:
                      isAnalyzing
                          ? null
                          : analyzeVideo,
                  icon: const Icon(
                    Icons
                        .auto_awesome,
                  ),
                  label: Text(
                    isAnalyzing
                        ? 'Analyzing...'
                        : 'Find Best Clips',
                    style:
                        const TextStyle(
                      fontSize: 16,
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),
                  style:
                      Filled
