import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_service.dart';
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
  LatLng _initialTarget = const LatLng(38.7223, -9.1393);
  static const double _initialZoom = 14;

  Map<String, LatLng> _parkingLocations = {};
  StreamSubscription<QuerySnapshot>? _parkingSubscription;

  // --- Yeni Eklenen Hafıza Değişkenleri ---
  Map<String, dynamic>? _selectedParkData; // O an kartta gösterilen park
  List<dynamic> _allCandidates = []; // API'den gelen tüm hesaplanmış parklar
  bool _isLoadingRecommendation = false;
  String? _recommendedParkId; // En iyi parkın ID'si (farklı renk için)

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

  Future<void> _moveCameraToTarget(LatLng target) async {
    if (_controller.isCompleted) {
      final GoogleMapController controller = await _controller.future;
      await controller.animateCamera(CameraUpdate.newLatLngZoom(target, 15));
    }
  }

  void _listenToParkingData() {
    _parkingSubscription = FirebaseFirestore.instance
        .collection('otoparklar')
        .snapshots()
        .listen((snapshot) {
          final Map<String, LatLng> tempLocations = {};
          for (final doc in snapshot.docs) {
            final data = doc.data();
            if (data['latitude'] != null && data['longitude'] != null) {
              tempLocations[doc.id] = LatLng(
                (data['latitude'] as num).toDouble(),
                (data['longitude'] as num).toDouble(),
              );
            }
          }
          setState(() => _parkingLocations = tempLocations);
          _refreshMarkers(); // Sadece marker'ları çiz, tahminleri dokunmatik sakla
        });
  }

  // --- Haritaya Tıklama: Yeni Öneri Al ---
  void _onMapTap(LatLng position) async {
    setState(() {
      _isLoadingRecommendation = true;
      _selectedParkData = null; // Eski kartı kapat
      _recommendedParkId = null;
      _allCandidates = [];

      // Hedef Marker'ı ekle
      _markers.removeWhere((m) => m.markerId.value == "destination");
      _markers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: "Hedefiniz"),
        ),
      );
    });

    final result = await _apiService.getSmartRecommendation(position);

    setState(() => _isLoadingRecommendation = false);

    if (result != null && result['recommended_parking'] != null) {
      setState(() {
        _allCandidates = result['all_parkings'] ?? [];
        _selectedParkData = result['recommended_parking'];
        _recommendedParkId = _selectedParkData!['park_id'];
      });

      _refreshMarkers(); // Yeni verilere göre renkleri güncelle
      _showInfoSheet(_selectedParkData!);
    }
  }

  // --- Marker'ları Yenileme (Renk Mantığı Burada) ---
  void _refreshMarkers() {
    final Set<Marker> newMarkers = {};

    // Varsa hedef marker'ı koru
    if (_markers.any((m) => m.markerId.value == "destination")) {
      newMarkers.add(
        _markers.firstWhere((m) => m.markerId.value == "destination"),
      );
    }

    for (final parkId in _parkingLocations.keys) {
      final LatLng pos = _parkingLocations[parkId]!;

      // Renk Kararı: Önerilen mi?
      double hue = BitmapDescriptor.hueBlue;
      if (parkId == _recommendedParkId) {
        hue = BitmapDescriptor.hueYellow; // En iyi otopark altın rengi
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(parkId),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => _onMarkerTap(parkId), // Marker'a basınca detay göster
        ),
      );
    }
    setState(() => _markers = newMarkers);
  }

  // --- Marker'a Basınca Detay Göster ---
  void _onMarkerTap(String parkId) {
    // API'den daha önce gelen hesaplanmış veriler içinde bu parkı bul
    final parkData = _allCandidates.firstWhere(
      (p) => p['park_id'] == parkId,
      orElse: () => null,
    );

    if (parkData != null) {
      setState(() => _selectedParkData = parkData);
      _showInfoSheet(parkData);
    } else {
      // Eğer henüz /recommend çalışmadıysa veya veri yoksa standart bilgi
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen önce haritada bir hedef seçin.")),
      );
    }
  }

  void _showInfoSheet(Map<String, dynamic> park) {
    bool isBest = park['park_id'] == _recommendedParkId;

    showModalBottomSheet(
      context: context,
      barrierColor: Colors.black12,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isBest ? Icons.stars : Icons.local_parking,
                  color: isBest ? Colors.orange : Colors.blue,
                  size: 30,
                ),
                const SizedBox(width: 10),
                Text(
                  isBest
                      ? "Yapay Zeka Önerisi: ${park['park_id']}"
                      : "Otopark: ${park['park_id']}",
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(),
            _infoRow(
              Icons.timer,
              "Tahmini Varış",
              "${park['duration_min']} dk",
            ),
            _infoRow(
              Icons.directions_car,
              "Uzaklık",
              "${park['distance_km']} km",
            ),
            _infoRow(
              Icons.pie_chart,
              "Doluluk Oranı",
              "%${(park['occupancy_ratio'] * 100).toInt()}",
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.navigation),
                label: const Text("Navigasyonu Başlat"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Text("$label: "),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Akıllı Otopark Asistanı"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget,
              zoom: _initialZoom,
            ),
            markers: _markers,
            onTap: _onMapTap,
            onMapCreated: (controller) => _controller.complete(controller),
          ),
          if (_isLoadingRecommendation)
            const Center(child: CircularProgressIndicator(strokeWidth: 5)),
        ],
      ),
    );
  }
}
