import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final query = 'Ado';
  final url = 'https://saavn.me/search/songs?query=$query';
  
  final response = await http.get(Uri.parse(url));
  print(response.body);
}
