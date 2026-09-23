import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'ideas_repository.dart';

class IdeasScreen extends StatefulWidget {
  final IdeasRepository? repository;
  const IdeasScreen({super.key, this.repository});
  @override
  State<IdeasScreen> createState() => _IdeasScreenState();
}

class _IdeasScreenState extends State<IdeasScreen> {
  late Future<List<ExerciseIdea>> future;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    future = (widget.repository ?? IdeasRepository()).load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Exercise ideas')),
    body: FutureBuilder<List<ExerciseIdea>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    widget.repository == null &&
                            IdeasRepository.endpoint.isEmpty
                        ? 'Exercise ideas are not connected yet.'
                        : 'Could not load exercise ideas. Check your connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(reload),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Text('No exercise ideas yet. Check back soon.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Movement guides & tips',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (final idea in snapshot.data!)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        idea.category.toUpperCase(),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        idea.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (idea.video != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: IdeaVideo(uri: idea.video!),
                        )
                      else
                        const AspectRatio(
                          aspectRatio: 16 / 9,
                          child: ColoredBox(
                            color: Color(0xFF292C23),
                            child: Center(
                              child: Text('Movement video coming soon'),
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      Text(idea.tips),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class IdeaVideo extends StatefulWidget {
  final Uri uri;
  const IdeaVideo({super.key, required this.uri});
  @override
  State<IdeaVideo> createState() => _IdeaVideoState();
}

class _IdeaVideoState extends State<IdeaVideo> {
  VideoPlayerController? controller;
  bool failed = false;
  bool loading = false;
  Future<void> play() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await controller?.dispose();
      final video = VideoPlayerController.networkUrl(widget.uri);
      controller = video;
      await video.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      video.addListener(changed);
      await video.play();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    controller?.removeListener(changed);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = controller;
    if (loading) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (failed || video?.value.hasError == true) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: TextButton.icon(
            onPressed: play,
            icon: const Icon(Icons.refresh),
            label: const Text('Video unavailable · Retry'),
          ),
        ),
      );
    }
    if (video == null || !video.value.isInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: const Color(0xFF292C23),
          child: Center(
            child: FilledButton.icon(
              onPressed: play,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Watch movement'),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: video.value.aspectRatio,
          child: VideoPlayer(video),
        ),
        VideoProgressIndicator(video, allowScrubbing: true),
        IconButton(
          tooltip: video.value.isPlaying ? 'Pause video' : 'Play video',
          onPressed: () async {
            if (video.value.isPlaying) {
              await video.pause();
            } else {
              await video.play();
            }
          },
          icon: Icon(video.value.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
      ],
    );
  }
}
