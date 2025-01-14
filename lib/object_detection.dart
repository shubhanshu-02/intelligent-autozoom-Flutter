import 'package:flutter/material.dart';
import 'package:realtime_obj_detection/bouding_boxes.dart';
import 'package:tflite_v2/tflite_v2.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:camera/camera.dart';
import 'package:realtime_obj_detection/full_screen_image.dart';



class objectDetection extends StatefulWidget {
  final List<CameraDescription> cameras;

  const objectDetection({super.key, required this.cameras});

  @override
  _objectDetectionState createState() =>
      _objectDetectionState();
}

class _objectDetectionState extends State<objectDetection> {
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
  try {
    XFile picture = await _controller.takePicture();
    Uint8List imageBytes = await picture.readAsBytes();

    img.Image? originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      print("Failed to decode the image.");
      return;
    }

    var object = recognitions![0];
    int x = (object['rect']['x'] * originalImage.width).toInt();
    int y = (object['rect']['y'] * originalImage.height).toInt();
    int width = (object['rect']['w'] * originalImage.width).toInt();
    int height = (object['rect']['h'] * originalImage.height).toInt();


    try {
      img.Image croppedImage = img.copyCrop(originalImage,
          x: x, y: y, width: width, height: height);

      String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      File croppedFile =
          File('${Directory.systemTemp.path}/cropped_image_$timestamp.png');
      await croppedFile.writeAsBytes(img.encodePng(croppedImage));

      setState(() {
        _captureImages.add(croppedFile);
        recognitions = [];
      });

      print("Cropped image saved at ${croppedFile.path}");
    } catch (cropError) {
      print("Error during image cropping: $cropError");
    }
  } catch (e) {
    print("Error capturing and processing image: $e");
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
        title: const Text('Intelligent AutoZoom Camera'),
      ),
      body: Column(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    // fit: BoxFit.fitWidth,
                    width: MediaQuery.of(context).size.width*.9,
                    height: MediaQuery.of(context).size.height*.7,
                    child: Stack(
                      children: [
                        CameraPreview(_controller),
                        if (recognitions != null)
                          BoundingBoxes(
                            recognitions: recognitions!,
                            previewH: MediaQuery.of(context).size.height,
                            previewW: MediaQuery.of(context).size.width,
                            screenH: MediaQuery.of(context).size.height*.7,
                            screenW: MediaQuery.of(context).size.width*.9,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                    onPressed: _captureImage,
                    icon: const Icon(
                      Icons.camera,
                      size: 30,
                      color: Colors.blueAccent,
                    ))
              ],
            ),
            SizedBox(
              height: 75,
              child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  scrollDirection: Axis.horizontal,
                  itemCount: _captureImages.length,
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: () => _openImage(_captureImages[index]),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image.file(
                            _captureImages[index],
                            width: 70,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  }),
            ),
          ],
        ),
    );
  }
}
