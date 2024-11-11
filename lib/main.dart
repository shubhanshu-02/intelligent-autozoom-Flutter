import 'dart:io';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:realtime_obj_detection/full_screen_image.dart';
import 'package:tflite_v2/tflite_v2.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RealTimeObjectDetection(
        cameras: cameras,
      ),
    );
  }
}

class RealTimeObjectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;

  const RealTimeObjectDetection({super.key, required this.cameras});

  @override
  _RealTimeObjectDetectionState createState() =>
      _RealTimeObjectDetectionState();
}

class _RealTimeObjectDetectionState extends State<RealTimeObjectDetection> {
  late CameraController _controller;
  final List<File> _captureImages = [];
  bool isModelLoaded = false;
  List<dynamic>? recognitions;
  int imageHeight = 0;
  int imageWidth = 0;

  @override
  void initState() {
    super.initState();
    loadModel();
    initializeCamera();
  }

  @override
  void dispose() {
    _controller.stopImageStream();
    _controller.dispose();
    Tflite.close();
    super.dispose();
  }

  Future<void> loadModel() async {
    String? res = await Tflite.loadModel(
      model: 'assets/detect.tflite',
      labels: 'assets/labelmap.txt',
    );
    setState(() {
      isModelLoaded = res != null;
    });
  }

  void initializeCamera() async {
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    await _controller.initialize();
    if (!mounted) {
      return;
    }
    _controller.startImageStream((CameraImage image) {
      if (isModelLoaded) {
        runModel(image);
      }
    });
    setState(() {});
  }

  void runModel(CameraImage image) async {
    if (image.planes.isEmpty) return;

    imageHeight = image.height;
    imageWidth = image.width;
    var recognitions = await Tflite.detectObjectOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      model: 'SSDMobileNet',
      imageHeight: imageHeight,
      imageWidth: imageWidth,
      imageMean: 127.5,
      imageStd: 127.5,
      numResultsPerClass: 1,
      threshold: 0.5,
    );

    setState(() {
      this.recognitions = recognitions;
    });
  }

  Future<void> _captureImage() async {
    if (recognitions != null && recognitions!.isNotEmpty) {
      await adjustZoomForObject(recognitions![0]);
    }
    try {
      XFile picture = await _controller.takePicture();
      setState(() {
        _captureImages.add(File(picture.path));
      });
      await _controller.setZoomLevel(1.0);
    } catch (e) {
      print("Error capturing image : $e");
    }
  }

Future<void> adjustZoomForObject(dynamic object) async {
  double objectWidth = object['rect']['w'] * imageWidth;
  double objectHeight = object['rect']['h'] * imageHeight;
  double objectSize = objectWidth * objectHeight;

  double frameSize = (imageWidth * imageHeight) as double;
  double objectProportion = objectSize / frameSize;

  print("Object Proportion: $objectProportion");

  double targetZoom;

  if (objectProportion > 0.5) {
    targetZoom = 1.0;
  } else if (objectProportion > 0.3) {
    targetZoom = 1.5;
  } else if (objectProportion > 0.2) {
    targetZoom = 2.0;
  } else if (objectProportion > 0.1) {
    targetZoom = 2.5;
  } else {
    targetZoom = 3.0;
  }

  try {
    await smoothZoomToLevel(targetZoom);
  } catch (e) {
    print("Error adjusting zoom: $e");
  }
}

  Future<void> smoothZoomToLevel(double targetZoom) async {
    double currentZoom = 1.0;
    double increment = (targetZoom - currentZoom) / 10;

    for (int i = 0; i < 10; i++) {
      currentZoom += increment;
      await _controller.setZoomLevel(currentZoom);
      await Future.delayed(Duration(milliseconds: 50));
    }
  }

  void _openImage(File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenImage(imageFile: imageFile),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Real-time Object Detection'),
      ),
      body: Center(
        child: Column(
          children: [
            SizedBox(
              // fit: BoxFit.fitWidth,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height * 0.7,
              child: Stack(
                children: [
                  CameraPreview(_controller),
                  if (recognitions != null)
                    BoundingBoxes(
                      recognitions: recognitions!,
                      previewH: imageHeight.toDouble(),
                      previewW: imageWidth.toDouble(),
                      screenH: MediaQuery.of(context).size.height,
                      screenW: MediaQuery.of(context).size.width * 0.7,
                    ),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: _captureImage,
                    icon: const Icon(
                      Icons.camera,
                    ))
              ],
            ),
            SizedBox(
              height: 80,
              child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _captureImages.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _openImage(_captureImages[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Image.file(
                          _captureImages[index],
                          width: 70,
                        ),
                      ),
                    );
                  }),
            ),
          ],
        ),
      ),
    );
  }
}

class BoundingBoxes extends StatelessWidget {
  final List<dynamic> recognitions;
  final double previewH;
  final double previewW;
  final double screenH;
  final double screenW;

  const BoundingBoxes({
    super.key,
    required this.recognitions,
    required this.previewH,
    required this.previewW,
    required this.screenH,
    required this.screenW,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: recognitions.map((rec) {
        var x = rec["rect"]["x"] * screenW;
        var y = rec["rect"]["y"] * screenH * 0.7;
        double w = rec["rect"]["w"] * screenW;
        double h = rec["rect"]["h"] * screenH * 0.7;

        return Positioned(
          left: x,
          top: y,
          width: w,
          height: h,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.red,
                width: 3,
              ),
            ),
            child: Text(
              "${rec["detectedClass"]} ${(rec["confidenceInClass"] * 100).toStringAsFixed(0)}% Width:${(w).ceil()} Height: ${h.ceil()}",
              style: TextStyle(
                color: Colors.red,
                fontSize: 15,
                background: Paint()..color = Colors.black,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
