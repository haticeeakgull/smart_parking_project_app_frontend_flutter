import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ApiService {
  // Emülatör kullanıyorsanız 10.0.2.2, gerçek cihaz için kendi yerel IP'niz
  final String _baseUrl = 'http://10.0.2.2:8000';
  final Dio _dio = Dio();

  /// Belirli bir otoparkın belirli bir süre sonraki doluluk tahminini getirir.
  Future<Map<String, dynamic>?> getPrediction(
    String parkId,
    int minutesLater,
  ) async {
    try {
      DateTime predictionTime = DateTime.now().add(
        Duration(minutes: minutesLater),
      );

      final requestData = {
        "park_id": parkId,
        "prediction_time": predictionTime.toIso8601String(),
      };

      final response = await _dio.post(
        '$_baseUrl/predict',
        data: requestData,
        options: Options(
          responseType: ResponseType.json,
          contentType: "application/json",
        ),
      );

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } on DioException catch (e) {
      debugPrint("Tahmin API Hatası: ${e.message}");
      return null;
    }
  }

  /// 🚀 YENİ: Akıllı Öneri Sistemi
  /// Kullanıcının gitmek istediği yere göre en mantıklı otoparkı getirir.
  Future<Map<String, dynamic>?> getSmartRecommendation(LatLng target) async {
    try {
      final requestData = {
        "target_lat": target.latitude,
        "target_lon": target.longitude,
        "arrival_time": DateTime.now().toIso8601String(),
      };

      final response = await _dio.post(
        '$_baseUrl/recommend',
        data: requestData,
        options: Options(
          responseType: ResponseType.json,
          contentType: "application/json",
        ),
      );

      if (response.statusCode == 200) {
        // Bu data içinde 'recommended_park' ve 'all_candidates' listesi dönecek.
        return response.data;
      } else {
        debugPrint("Öneri Hatası Kodu: ${response.statusCode}");
        return null;
      }
    } on DioException catch (e) {
      debugPrint("Bağlantı Hatası (Öneri): ${e.type} - ${e.message}");
      // Sunucu kapalıysa veya IP yanlışsa buraya düşer.
      return null;
    } catch (e) {
      debugPrint("Beklenmedik Öneri Hatası: $e");
      return null;
    }
  }
}
