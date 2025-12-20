import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_service.dart';
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

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
      title: 'Akıllı Otopark Asistanı',
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
  // Lizbon merkez başlangıç noktası
  final LatLng _initialTarget = const LatLng(38.7223, -9.1393);
  static const double _initialZoom = 14;

  Map<String, LatLng> _parkingLocations = {};
  StreamSubscription<QuerySnapshot>? _parkingSubscription;

  // Hafıza Değişkenleri
  Map<String, dynamic>? _selectedParkData;
  List<dynamic> _allCandidates = [];
  bool _isLoadingRecommendation = false;
  String? _recommendedParkId;

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

  // Firestore'dan otopark konumlarını canlı dinler
  void _listenToParkingData() {
    _parkingSubscription = FirebaseFirestore.instance
        .collection('otoparklar')
        .snapshots()
        .listen((snapshot) {
          final Map<String, LatLng> tempLocations = {};
          for (final doc in snapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (data['latitude'] != null && data['longitude'] != null) {
              tempLocations[doc.id] = LatLng(
                (data['latitude'] as num).toDouble(),
                (data['longitude'] as num).toDouble(),
              );
            }
          }
          setState(() => _parkingLocations = tempLocations);
          _refreshMarkers();
        });
  }

  // --- Haritaya Tıklama: Mevcut Konum + Hedef ile API'ye sorar ---
  void _onMapTap(LatLng position) async {
    setState(() {
      _isLoadingRecommendation = true;
      _selectedParkData = null;
      _recommendedParkId = null;
      _allCandidates = [];

      // Hedef Marker ekle
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

    // TEST: Emülatörde ayarladığın sanal Lizbon konumu (Senin başlangıç noktan)
    // Gerçek GPS verisi için Geolocator paketi eklenebilir.
    LatLng myCurrentLocation = const LatLng(38.7167, -9.1333);

    // API'ye hem senin konumunu hem hedefi gönderiyoruz
    final result = await _apiService.getSmartRecommendation(
      position,
      myCurrentLocation,
    );
    debugPrint("API'den Gelen Yanıt: $result");

    setState(() => _isLoadingRecommendation = false);

    if (result != null && result['recommended_parking'] != null) {
      setState(() {
        _allCandidates = result['all_parkings'] ?? [];
        _selectedParkData = result['recommended_parking'];
        _recommendedParkId = _selectedParkData!['park_id'].toString();
      });

      _refreshMarkers();
      _showInfoSheet(_selectedParkData!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Öneri alınamadı. Lütfen API'yi kontrol edin."),
        ),
      );
    }
  }

  // --- Marker'ları Yenileme (Önerilen Sarı, Diğerleri Mavi) ---
  void _refreshMarkers() {
    final Set<Marker> newMarkers = {};

    if (_markers.any((m) => m.markerId.value == "destination")) {
      newMarkers.add(
        _markers.firstWhere((m) => m.markerId.value == "destination"),
      );
    }

    for (final parkId in _parkingLocations.keys) {
      final LatLng pos = _parkingLocations[parkId]!;
      double hue = BitmapDescriptor.hueBlue;

      if (parkId.toString() == _recommendedParkId) {
        hue = BitmapDescriptor.hueYellow;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(parkId),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => _onMarkerTap(parkId),
        ),
      );
    }
    setState(() => _markers = newMarkers);
  }

  // --- Marker Tıklama ---
  void _onMarkerTap(String parkId) {
    final parkData = _allCandidates.firstWhere(
      (p) => p['park_id'].toString() == parkId.toString(),
      orElse: () => null,
    );

    if (parkData != null) {
      setState(() => _selectedParkData = parkData);
      _showInfoSheet(parkData);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Lütfen önce haritada bir hedef seçin.")),
      );
    }
  }

  // --- Navigasyon Başlatma ---
  Future<void> _launchNavigation(double targetLat, double targetLon) async {
    // Google Haritalar'ı "Cihazın GPS konumu -> Otopark" rotasıyla açar
    final String url =
        "https://www.google.com/maps/dir/?api=1&destination=$targetLat,$targetLon&travelmode=driving";

    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint("Haritalar başlatılamadı.");
      }
    } catch (e) {
      debugPrint("Navigasyon hatası: $e");
    }
  }

  // --- Alt Bilgi Paneli ---
  void _showInfoSheet(Map<String, dynamic> park) {
    bool isBest = park['park_id'].toString() == _recommendedParkId;

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
                      ? "En İyi Öneri: ${park['park_id']}"
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
              Icons.drive_eta,
              "Sürüş Süresi",
              "${park['duration_min']} dk",
            ),
            _infoRow(
              Icons.directions_walk,
              "Yürüme (Hedeften)",
              "${park['walk_min'] ?? '?'} dk",
            ),
            _infoRow(
              Icons.pie_chart,
              "Varışta Tahmini Doluluk",
              "%${(park['occupancy_ratio'] * 100).toInt()}",
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _launchNavigation(park['latitude'], park['longitude']);
                },
                icon: const Icon(Icons.navigation),
                label: const Text("Navigasyonu Başlat"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.all(15),
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
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          if (_isLoadingRecommendation)
            const Center(child: CircularProgressIndicator(strokeWidth: 5)),
        ],
      ),
    );
  }
}
