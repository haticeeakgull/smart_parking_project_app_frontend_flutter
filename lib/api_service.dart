import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ApiService {
  final String _baseUrl = 'http://10.0.2.2:8000'; // Emülatör için standart IP
  late final Dio _dio;

  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        responseType: ResponseType.json,
        contentType: "application/json",
      ),
    );
  }

  /// Otopark doluluk tahmini
  Future<Map<String, dynamic>?> getPrediction(
    String parkId,
    int minutesLater,
  ) async {
    try {
      DateTime predictionTime = DateTime.now().add(
        Duration(minutes: minutesLater),
      );

      final response = await _dio.post(
        '/predict',
        data: {
          "park_id": parkId,
          "prediction_time": predictionTime.toIso8601String(),
        },
      );

      if (response.statusCode == 200) return response.data;
      return null;
    } on DioException catch (e) {
      debugPrint("Tahmin Hatası: ${e.message}");
      return null;
    }
  }

  /// Akıllı Öneriyi Getir
  Future<Map<String, dynamic>?> getSmartRecommendation(
    LatLng target,
    LatLng user,
    int maxWalkTime,
  ) async {
    try {
      final requestData = {
        "target_lat": target.latitude,
        "target_lon": target.longitude,
        "user_lat": user.latitude,
        "user_lon": user.longitude,
        "max_walk_time": maxWalkTime,
      };

      debugPrint("İstek Atılıyor: $requestData");

      final response = await _dio.post('/recommend', data: requestData);

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        debugPrint("Sunucu 404 Döndü: Uygun otopark yok.");
      } else {
        debugPrint("API Bağlantı Hatası: ${e.type} - ${e.message}");
      }
      return null;
    } catch (e) {
      debugPrint("Beklenmedik Hata: $e");
      return null;
    }
  }
}
