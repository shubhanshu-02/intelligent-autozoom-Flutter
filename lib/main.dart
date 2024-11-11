import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:realtime_obj_detection/object_detection.dart';

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
      home: objectDetection(
        cameras: cameras,
      ),
    );
  }
}
