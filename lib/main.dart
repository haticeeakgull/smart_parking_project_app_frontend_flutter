import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_service.dart'; // ApiService'in var olduğunu varsayıyoruz
import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("FATAL ERROR: Firebase başlangıcı başarısız: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Akıllı Otopark',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final Completer<GoogleMapController> _controller = Completer();
  final ApiService _apiService = ApiService();

  Set<Marker> _markers = {};
  final double _selectedTime = 0; // final kaldırıldı

  // ⚠️ Haritanın ilk odaklanacağı yer (Örneğin Lizbon değil, Türkiye'de bir yer)
  // Eğer otoparklarınız Portekiz'de ise bu değer kalabilir. Ben İstanbul'a yakın bir merkez koyuyorum.
  LatLng _initialTarget = const LatLng(
    41.0082,
    28.9784,
  ); // İstanbul/Türkiye varsayılan konum
  static const double _initialZoom = 12; // Zoom seviyesi

  Map<String, LatLng> _parkingLocations = {};
  StreamSubscription<QuerySnapshot>? _parkingSubscription;

  @override
  void initState() {
    super.initState();
    _listenToParkingData();
  }

  @override
  void dispose() {
    _parkingSubscription?.cancel();
    super.dispose();
  }

  // Haritayı verilen konuma hareket ettirir
  Future<void> _moveCameraToTarget(LatLng target) async {
    if (_controller.isCompleted) {
      final GoogleMapController controller = await _controller.future;
      // Yeni konuma animasyonlu hareket
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(target, _initialZoom),
      );
    }
  }

  void _listenToParkingData() {
    _parkingSubscription = FirebaseFirestore.instance
        .collection('otoparklar')
        .snapshots()
        .listen(
          (snapshot) {
            final Map<String, LatLng> tempLocations = {};

            for (final doc in snapshot.docs) {
              final data = doc.data();

              final dynamic latDynamic = data['latitude'];
              final dynamic lonDynamic = data['longitude'];

              if (latDynamic != null && lonDynamic != null) {
                try {
                  // Firebase'de Number (Sayı) olduğu için güvenli dönüşüm:
                  final double lat = (latDynamic as num).toDouble();
                  final double lon = (lonDynamic as num).toDouble();

                  // Koordinatlar geçerliyse (0,0 değilse) ekle.
                  if (lat != 0.0 && lon != 0.0) {
                    tempLocations[doc.id] = LatLng(lat, lon);
                  } else {
                    debugPrint(
                      "❌ Otopark ${doc.id}: Koordinat 0.0 olarak geldi.",
                    );
                  }
                } catch (e) {
                  // Eğer tür uyuşmazlığı olursa (gelen veri num değilse)
                  debugPrint(
                    "❌ Otopark ${doc.id} koordinat dönüşüm hatası: $e",
                  );
                }
              }
            }
            setState(() {
              _parkingLocations = tempLocations;
            });

            // 1. Otoparklar yüklendikten sonra haritayı odakla
            if (tempLocations.isNotEmpty) {
              // İlk otoparkın konumunu haritanın yeni başlangıç noktası yap
              _initialTarget = tempLocations.values.first;
              _moveCameraToTarget(_initialTarget);
            }

            // 2. Marker'ları oluşturup haritaya yerleştir
            _refreshPredictions();
          },
          onError: (error) {
            debugPrint("❌ Firestore Dinleme Hatası: $error");
          },
        );
  }

  String _getTimeLabel(double value) {
    if (value == 0) return "Şimdi (Anlık Tahmin)";
    if (value == 30) return "30 dk sonra";
    if (value == 60) return "1 saat sonra";
    if (value == 90) return "1.5 saat sonra";
    if (value == 120) return "2 saat sonra";
    return "${value.toInt()} dk sonra";
  }

  Future<void> _refreshPredictions() async {
    if (_parkingLocations.isEmpty) {
      debugPrint("⏳ Otopark konumları Firebase'den bekleniyor...");
      return;
    }

    final Set<Marker> newMarkers = {};

    for (final parkId in _parkingLocations.keys) {
      final LatLng position = _parkingLocations[parkId]!;

      // 🛑 GEÇİCİ TEST İÇİN API KISMI:
      // Eğer marker'ları hala göremiyorsanız, aşağıdaki 12 satırı kullanın.
      // API'niz (FastAPI) dışarıdan erişilebilir ve çalışır durumda değilse marker oluşmaz.

      newMarkers.add(
        Marker(
          markerId: MarkerId(parkId),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: "TEST: Otopark $parkId",
            snippet: "Konum doğru, API test ediliyor.",
          ),
        ),
      );

      // 🛑 GEÇİCİ TEST KISMI BİTTİ. Normal kodu kullanmak için yukarıdaki bloğu yorumlayın.

      // Normal Akış (API'den veri çekme)
      final result = await _apiService.getPrediction(
        parkId,
        _selectedTime.toInt(),
      );

      if (result == null) {
        debugPrint(
          "API'den $parkId için tahmin alınamadı. Marker oluşturulmadı.",
        );
        continue;
      }

      final double ratio = (result['occupancy_ratio'] as num).toDouble();
      final int cars = result['estimated_cars'];
      final int maxCapacity = result['max_capacity'];

      double hue;
      if (ratio <= 0.25) {
        hue = BitmapDescriptor.hueGreen;
      } else if (ratio <= 0.50) {
        hue = BitmapDescriptor.hueYellow;
      } else if (ratio <= 0.75) {
        hue = BitmapDescriptor.hueOrange;
      } else {
        hue = BitmapDescriptor.hueRed;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(parkId),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          infoWindow: InfoWindow(
            title: "Otopark $parkId (${_getTimeLabel(_selectedTime)})",
            snippet:
                "Doluluk: %${(ratio * 100).toInt()} ($cars araç / $maxCapacity kapasite)",
          ),
        ),
      );
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Akıllı Otopark Tahmini")),
      body: GoogleMap(
        // ⚠️ Haritanın başlangıç konumu artık _initialTarget değişkenini kullanıyor
        initialCameraPosition: CameraPosition(
          target: _initialTarget,
          zoom: _initialZoom,
        ),
        markers: _markers,
        onMapCreated: (controller) {
          if (!_controller.isCompleted) {
            _controller.complete(controller);
          }
        },
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendItem({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }
}
