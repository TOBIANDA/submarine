import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final query = 'Ado';
  final url = 'https://saavn.dev/api/search/songs?query=$query';
  
  try {
    print('Searching JioSaavn: $url');
    final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));
    print('Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final results = data['data']['results'] as List;
      if (results.isNotEmpty) {
        final first = results.first;
        print('Found: ${first['name']} by ${first['primaryArtists']}');
        
        final downloadUrls = first['downloadUrl'] as List;
        final bestUrl = downloadUrls.last['url']; // usually the highest quality is last
        print('Stream URL: $bestUrl');
        
        // Test download URL
        final streamRes = await http.head(Uri.parse(bestUrl));
        print('Stream status: ${streamRes.statusCode}');
      } else {
        print('No results.');
      }
    } else {
      print('Body: ${response.body}');
    }
  } catch (e) {
    print('Error: $e');
  }
}
