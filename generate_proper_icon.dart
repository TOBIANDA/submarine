import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  // Create a 96x96 image with transparent background
  final image = img.Image(width: 96, height: 96);
  img.fill(image, color: img.ColorRgba8(0, 0, 0, 0));

  // Draw a solid white circle in the middle (radius 32)
  img.fillCircle(
    image,
    x: 48,
    y: 48,
    radius: 32,
    color: img.ColorRgba8(255, 255, 255, 255),
  );

  // Save the image
  final png = img.encodePng(image);
  final file = File('android/app/src/main/res/drawable/ic_notification.png');
  
  if (!file.parent.existsSync()) {
    file.parent.createSync(recursive: true);
  }
  
  file.writeAsBytesSync(png);
  print('Proper white silhouette icon generated at ${file.path}');
}
