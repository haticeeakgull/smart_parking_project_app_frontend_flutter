import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ApiService {
  final String _baseUrl = 'http://10.0.2.2:8000';

  final Dio _dio = Dio();

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
        options: Options(responseType: ResponseType.json),
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        debugPrint("Hata Kodu: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      debugPrint("Bağlantı Hatası: $e");
      return null;
    }
  }
}
