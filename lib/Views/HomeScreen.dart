import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  File? video;
  VideoPlayerController? _videoController;
  VideoPlayerController? _processedVideoController;
  bool isLoading = false;
  bool isCancelled = false;
  http.StreamedResponse? currentResponse;
  final FocusNode _focusNode = FocusNode();
  final TextEditingController _textEditingController = TextEditingController();
  bool _read = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {});

    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        _saveUrlAndLock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeControllers();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _videoController?.pause();
      _processedVideoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        _videoController?.play();
      }
      if (_processedVideoController != null &&
          _processedVideoController!.value.isInitialized) {
        _processedVideoController?.play();
      }
    }
  }

  String url = '';
  void _pickVideo(BuildContext context) async {
    final ImagePicker picker = ImagePicker();
    final XFile? pickedFile =
        await picker.pickVideo(source: ImageSource.gallery);

    if (pickedFile != null) {
      _disposeControllers();

      setState(() {
        video = File(pickedFile.path);
        isLoading = true;
        isCancelled = false;
      });

      _initializeVideoPlayer(video!, context);
      await _uploadVideo(video!, context);
    }
  }

  Future<void> _uploadVideo(File videoFile, BuildContext context) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://$url:5000/process_video'), // Update the URL here
      );
      request.files.add(await http.MultipartFile.fromPath(
          'video', videoFile.path)); // Change 'file' to 'video'

      currentResponse = await request.send();

      if (isCancelled) return;

      if (currentResponse!.statusCode == 200) {
        var bytes = await currentResponse!.stream.toBytes();

        // Get the temporary directory
        Directory tempDir = await getTemporaryDirectory();
        String filePath = p.join(tempDir.path, 'processed_video.mp4');

        File processedVideo = File(filePath);
        await processedVideo.writeAsBytes(bytes);

        _showSnackbar(context, 'Video saved at $filePath');
        _initializeProcessedVideoPlayer(processedVideo, context);
      } else {
        _showSnackbar(context, 'Failed to process video');
      }
    } catch (e) {
      if (!isCancelled) {
        _showSnackbar(context, 'Error: $e');
      }
    } finally {
      setState(() {
        isLoading = false;
        currentResponse = null;
      });
    }
  }

  void _initializeVideoPlayer(File videoFile, BuildContext context) {
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }

    setState(() {
      _videoController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          setState(() {});
          _videoController?.play();
        }).catchError((error) {
          _showSnackbar(context, 'Error initializing video player: $error');
          log('Error initializing video player: $error',
              error: error); // More detailed logging
        });

      _videoController?.addListener(() {
        if (_videoController!.value.hasError) {
          _showSnackbar(context,
              'Video playback error: ${_videoController!.value.errorDescription}');
        }
      });
    });
  }

  void _initializeProcessedVideoPlayer(File videoFile, BuildContext context) {
    if (_processedVideoController != null) {
      _processedVideoController!.dispose();
      _processedVideoController = null;
    }

    setState(() {
      _processedVideoController = VideoPlayerController.file(videoFile)
        ..initialize().then((_) {
          setState(() {});
          _processedVideoController?.setVolume(0.0); // Mute processed video
          _processedVideoController?.play();
        }).catchError((error) {
          _showSnackbar(
              context, 'Error initializing processed video player: $error');
          log('Error initializing processed video player: $error',
              error: error); // More detailed logging
        });

      _processedVideoController?.addListener(() {
        if (_processedVideoController!.value.hasError) {
          _showSnackbar(context,
              'Processed video playback error: ${_processedVideoController!.value.errorDescription}');
          log('Processed video playback error: ${_processedVideoController!.value.errorDescription}'); // More detailed logging
        }
      });
    });
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _cancelProcess(BuildContext context) {
    if (isLoading) {
      setState(() {
        isCancelled = true;
        isLoading = false;
        currentResponse?.stream.listen(null).cancel();
        _showSnackbar(context, 'Processing cancelled');
      });
    }
  }

  void _disposeControllers() {
    _videoController?.dispose();
    _processedVideoController?.dispose();
    _videoController = null;
    _processedVideoController = null;
  }

  void _saveUrlAndLock() {
    setState(() {
      url = _textEditingController.text;
      _read = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.deepPurple,
        centerTitle: true,
        title: const Text(
          'Speed Detection',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  focusNode: _focusNode,
                  readOnly: _read,
                  controller: _textEditingController,
                  decoration: InputDecoration(
                    suffix: InkWell(
                      onTap: () {
                        setState(() {
                          _read = !_read;
                          if (_read) {
                            _saveUrlAndLock();
                          }
                        });
                      },
                      child: Icon(_read ? Icons.lock : Icons.lock_open),
                    ),
                    labelText: 'Enter your IP',
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.blue),
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                    border: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.circular(30.0),
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onEditingComplete: () {
                    _saveUrlAndLock();
                  },
                  onSubmitted: (v) {
                    _saveUrlAndLock();
                  },
                ),
                ElevatedButton(
                  onPressed: () {
                    _pickVideo(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'Pick Video',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
                if (isLoading)
                  Column(
                    children: [
                      const SizedBox(height: 20),
                      const SpinKitFadingCircle(
                        color: Colors.deepPurple,
                        size: 50.0,
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () {
                          _cancelProcess(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 30, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontSize: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 30),
                if (_videoController != null &&
                    _videoController!.value.isInitialized)
                  _buildVideoPlayerContainer(_videoController!),
                const SizedBox(height: 20),
                if (_processedVideoController != null &&
                    _processedVideoController!.value.isInitialized)
                  _buildVideoPlayerContainer(_processedVideoController!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayerContainer(VideoPlayerController controller) {
    return Card(
      elevation: 5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: SizedBox(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      ),
    );
  }
}
