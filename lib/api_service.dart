import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class ApiService {
  // Emülatör kullanıyorsanız 10.0.2.2, gerçek cihaz için IP adresiniz
  final String _baseUrl = 'http://10.0.2.2:8000';

  late final Dio _dio;

  ApiService() {
    // Dio yapılandırmasını burada yaparak Timeout hatalarının önüne geçiyoruz
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        // Sunucuya bağlanma ve yanıt alma sürelerini 30 saniyeye çıkardık
        connectTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 5),
        responseType: ResponseType.json,
        contentType: "application/json",
      ),
    );
  }

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

      final response = await _dio.post('/predict', data: requestData);

      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } on DioException catch (e) {
      debugPrint("Tahmin API Hatası: ${e.message}");
      return null;
    }
  }

  /// 🚀 AKILLI ÖNERİ SİSTEMİ
  /// target: Haritada tıklanan varış noktası
  /// user: Emülatördeki/Kullanıcının o anki sanal konumu
  Future<Map<String, dynamic>?> getSmartRecommendation(
    LatLng target,
    LatLng user,
  ) async {
    try {
      final requestData = {
        "target_lat": target.latitude,
        "target_lon": target.longitude,
        "user_lat": user.latitude,
        "user_lon": user.longitude,
      };

      debugPrint("API İsteği Gönderiliyor: $requestData");

      // Not: Timeout süreleri BaseOptions içinde tanımlandığı için burada tekrar yazmaya gerek yoktur.
      final response = await _dio.post('/recommend', data: requestData);

      if (response.statusCode == 200) {
        // FastAPI'den 'recommended_parking' ve 'all_parkings' döner
        return response.data;
      } else {
        debugPrint("Öneri Hatası Kodu: ${response.statusCode}");
        return null;
      }
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        debugPrint("Zaman Aşımı Hatası: Sunucu çok geç yanıt verdi.");
      } else if (e.response != null) {
        debugPrint(
          "Sunucu Hatası (${e.response?.statusCode}): ${e.response?.data}",
        );
      } else {
        debugPrint("Bağlantı Hatası: ${e.message}");
      }
      return null;
    } catch (e) {
      debugPrint("Beklenmedik Hata: $e");
      return null;
    }
  }
}
