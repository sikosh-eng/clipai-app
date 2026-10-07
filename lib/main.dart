import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
        scaffoldBackgroundColor: const Color(0xFF08080D),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF2D75),
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
  VideoPlayerController? _videoController;

  String? _videoName;
  bool _analyzing = false;
  double _progress = 0;

  Future<void> pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
    );

    if (result == null) return;

    final path = result.files.single.path;

    if (path == null) return;

    await _videoController?.dispose();

    final controller = VideoPlayerController.file(
      File(path),
    );

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _videoController = controller;
      _videoName = result.files.single.name;
    });

    controller.setLooping(true);
    controller.play();
  }

  Future<void> analyzeVideo() async {
    if (_videoController == null) return;

    setState(() {
      _analyzing = true;
      _progress = 0;
    });

    for (int i = 1; i <= 20; i++) {
      await Future.delayed(
        const Duration(milliseconds: 150),
      );

      if (!mounted) return;

      setState(() {
        _progress = i / 20;
      });
    }

    if (!mounted) return;

    setState(() {
      _analyzing = false;
    });

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111118),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (context) {
        return const ClipResults();
      },
    );
  }

  void removeVideo() async {
    await _videoController?.dispose();

    setState(() {
      _videoController = null;
      _videoName = null;
      _progress = 0;
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF2D75),
                    Color(0xFFFF5C35),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.auto_awesome,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'ClipAI',
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            30,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              const Text(
                'Turn long videos into\nviral short clips.',
                style: TextStyle(
                  fontSize: 32,
                  height: 1.08,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Upload your video and let ClipAI find '
                'the most interesting moments.',
                style: TextStyle(
                  color: Colors.white.withOpacity(.55),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 25),

              if (_videoController == null)
                _buildUploadBox()
              else
                _buildVideoSection(),

              const SizedBox(height: 24),

              _buildFeatureCards(),

              const SizedBox(height: 25),

              if (_videoController != null)
                _buildAnalyzeButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadBox() {
    return GestureDetector(
      onTap: pickVideo,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          vertical: 42,
          horizontal: 20,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF111118),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withOpacity(.08),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFFF2D75)
                    .withOpacity(.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library_outlined,
                size: 34,
                color: Color(0xFFFF2D75),
              ),
            ),

            const SizedBox(height: 18),

            const Text(
              'Upload a video',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 7),

            Text(
              'MP4, MOV or other video files',
              style: TextStyle(
                color: Colors.white.withOpacity(.45),
              ),
            ),

            const SizedBox(height: 22),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 13,
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF2D75),
                    Color(0xFFFF4F5E),
                  ],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Text(
                'Choose Video',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    final controller = _videoController!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
          ),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(controller),

                GestureDetector(
                  onTap: () {
                    setState(() {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    });
                  },
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.55),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            const Icon(
              Icons.video_file,
              size: 19,
              color: Color(0xFFFF2D75),
            ),
            const SizedBox(width: 8),

            Expanded(
              child: Text(
                _videoName ?? 'Video',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            IconButton(
              onPressed: removeVideo,
              icon: const Icon(
                Icons.close,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCards() {
    return Row(
      children: [
        Expanded(
          child: _featureCard(
            Icons.auto_awesome,
            'AI Clips',
            'Finds the best moments',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _featureCard(
            Icons.subtitles_outlined,
            'Captions',
            'Beautiful subtitle styles',
          ),
        ),
      ],
    );
  }

  Widget _featureCard(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF111118),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Colors.white.withOpacity(.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFFFF2D75),
            size: 25,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(.42),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton() {
    return Column(
      children: [
        if (_analyzing) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'AI is analyzing your video...',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                  color: Color(0xFFFF2D75),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 7,
              backgroundColor: Colors.white.withOpacity(.08),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF2D75),
              ),
            ),
          ),

          const SizedBox(height: 18),
        ],

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _analyzing ? null : analyzeVideo,
            icon: Icon(
              _analyzing
                  ? Icons.hourglass_top
                  : Icons.auto_awesome,
            ),
            label: Text(
              _analyzing
                  ? 'Analyzing...'
                  : 'Find Best Clips',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2D75),
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  const Color(0xFFFF2D75).withOpacity(.45),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ClipResults extends StatelessWidget {
  const ClipResults({super.key});

  final List<Map<String, dynamic>> clips = const [
    {
      'start': '00:14',
      'end': '00:43',
      'score': 96,
    },
    {
      'start': '01:27',
      'end': '01:58',
      'score': 93,
    },
    {
      'start': '03:12',
      'end': '03:46',
      'score': 91,
    },
    {
      'start': '05:04',
      'end': '05:39',
      'score': 88,
    },
    {
      'start': '07:21',
      'end': '07:53',
      'score': 85,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          18,
          20,
          18,
          25,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFF2D75),
                ),
                SizedBox(width: 9),
                Text(
                  'Best Clips',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Text(
              'AI found these potentially viral moments.',
              style: TextStyle(
                color: Colors.white.withOpacity(.5),
              ),
            ),

            const SizedBox(height: 18),

            ...clips.map(
              (clip) => _clipCard(
                context,
                clip,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipCard(
    BuildContext context,
    Map<String, dynamic> clip,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF191921),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFF2D75)
                  .withOpacity(.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.play_arrow,
              color: Color(0xFFFF2D75),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '${clip['start']} — ${clip['end']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Viral score: ${clip['score']}%',
                  style: TextStyle(
                    color: Colors.white.withOpacity(.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.chevron_right,
            color: Colors.white38,
          ),
        ],
      ),
    );
  }
}
