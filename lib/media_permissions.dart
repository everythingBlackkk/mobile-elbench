import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';

/// Uses the platform photo picker: Android grants access only to the selected
/// item, and iOS asks for any necessary photo access when the picker opens.
Future<XFile?> pickUploadImage({
  required String Function(String, String) tr,
  double? maxWidth,
  int? imageQuality,
}) async {
  try {
    return await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
      maxWidth: maxWidth,
      imageQuality: imageQuality,
    );
  } on PlatformException catch (error) {
    if (error.code.contains('denied') || error.code.contains('restricted')) {
      throw ApiFailure(
        tr(
          'Photo access is off. Allow ElBench to access selected photos in your device Settings, then try again.',
          'الوصول للصور متوقف. اسمح لتطبيق ElBench بالوصول للصور المختارة من إعدادات الجهاز ثم حاول مرة أخرى.',
        ),
      );
    }
    throw ApiFailure(
      tr(
        'Could not open the photo picker. Please try again.',
        'تعذر فتح الصور. حاول مرة أخرى.',
      ),
    );
  }
}
