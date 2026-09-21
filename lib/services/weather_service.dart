import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class WeatherService {
  static final WeatherService instance = WeatherService._internal();
  WeatherService._internal();

  Future<String> fetchWeather() async {
    final prefs = await SharedPreferences.getInstance();
    final zip = prefs.getString('weather_zip_code');
    if (zip == null || zip.isEmpty) {
      return "Please set your zip code in settings to get the weather.";
    }

    try {
      // Get coordinates for zip code using Zippopotam.us
      final geoResponse = await http.get(Uri.parse('https://api.zippopotam.us/us/$zip'));
      if (geoResponse.statusCode != 200) return "Could not find location for zip code $zip.";
      
      final geoData = jsonDecode(geoResponse.body);
      final place = geoData['places'][0];
      final lat = place['latitude'];
      final lon = place['longitude'];

      // Get weather from Open-Meteo
      final weatherResponse = await http.get(Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto'
      ));
      if (weatherResponse.statusCode != 200) return "Weather service unavailable.";

      final weatherData = jsonDecode(weatherResponse.body);
      final currentTemp = weatherData['current']['temperature_2m'];
      final condition = _getCondition(weatherData['current']['weather_code']);
      final todayMax = weatherData['daily']['temperature_2m_max'][0];
      final todayMin = weatherData['daily']['temperature_2m_min'][0];
      
      return "Currently in ${place['place name']}, it is $currentTemp degrees and $condition. Today's high is $todayMax and low is $todayMin.";
    } catch (e) {
      return "Error fetching weather: $e";
    }
  }

  String _getCondition(int code) {
    if (code == 0) return "clear sky";
    if (code <= 3) return "partly cloudy";
    if (code <= 67) return "rainy";
    if (code <= 77) return "snowy";
    if (code <= 82) return "foggy";
    return "cloudy";
  }
}
