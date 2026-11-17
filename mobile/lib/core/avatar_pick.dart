import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// اختيار صورة وتصغيرها لـ 192×192 (نفس الموقع) قبل الرفع
Future<String?> pickAvatar() async {
  final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 90);
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  final im = img.decodeImage(bytes);
  if (im == null) throw Exception('الصورة مش مدعومة');
  final sq = img.copyResizeCropSquare(im, size: 192, interpolation: img.Interpolation.average);
  return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(sq, quality: 82))}';
}
