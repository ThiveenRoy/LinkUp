import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

Future<Uint8List?> pickWallpaperBytes() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
  return x == null ? null : x.readAsBytes();
}
