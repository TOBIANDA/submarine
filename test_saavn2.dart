import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final query = 'Ado';
  final instances = [
    'https://saavn.me',
    'https://jiosaavn-api-privatecvc.vercel.app',
    'https://jiosaavn-api-v3.vercel.app'
  ];
  
  for (final baseUrl in instances) {
    final url = '$baseUrl/search/songs?query=$query';
    try {
      print('Testing $baseUrl...');
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));
      if (response.statusCode == 200) {
        print('Success at $baseUrl');
        break;
      } else {
        print('Failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Error: $e');
    }
  }
}
