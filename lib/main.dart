import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_service.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase Hatası: $e");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
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
  Map<String, LatLng> _parkingLocations = {};
  List<dynamic> _allCandidates = []; // API'den gelen tüm otoparkların listesi
  bool _isLoading = false;

  bool _isNavigationMode = false;
  Map<String, dynamic>? _selectedPark; // O an kartta detayları gösterilen park
  String? _recommendedParkId; // API'nin "en iyi" dediği parkın ID'si

  final LatLng _initialTarget = const LatLng(38.7223, -9.1393);

  @override
  void initState() {
    super.initState();
    _listenToParkingData();
  }

  void _listenToParkingData() {
    FirebaseFirestore.instance.collection('otoparklar').snapshots().listen((
      snapshot,
    ) {
      final Map<String, LatLng> temp = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        temp[doc.id] = LatLng(data['latitude'], data['longitude']);
      }
      setState(() => _parkingLocations = temp);
      _refreshMarkers();
    });
  }

  // Kullanıcı herhangi bir otopark marker'ına tıkladığında
  void _onMarkerTap(String parkId) {
    // Eğer henüz bir hedef seçilmemişse allCandidates boştur, işlem yapma
    if (_allCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lütfen önce haritadan bir varış noktası seçin."),
        ),
      );
      return;
    }

    // Tıklanan ID'ye sahip otoparkı API listesinden bul
    final clickedPark = _allCandidates.firstWhere(
      (p) => p['park_id'].toString() == parkId,
      orElse: () => null,
    );

    if (clickedPark != null) {
      setState(() {
        _selectedPark = clickedPark;
        _isNavigationMode = true; // Kartı göster/güncelle
      });
      _refreshMarkers(); // Seçili marker rengini yeşil yapmak için yenile
      _moveCamera(
        LatLng(clickedPark['latitude'], clickedPark['longitude']),
        15,
      );
    }
  }

  void _backToMainMap() {
    setState(() {
      _isNavigationMode = false;
      _selectedPark = null;
      _recommendedParkId = null;
      _allCandidates = [];
      _markers.removeWhere((m) => m.markerId.value == "destination");
    });
    _refreshMarkers();
    _moveCamera(_initialTarget, 14);
  }

  void _refreshMarkers() {
    final Set<Marker> newMarkers = {};

    // Hedef marker'ını (mavi damla) koru
    if (_markers.any((m) => m.markerId.value == "destination")) {
      newMarkers.add(
        _markers.firstWhere((m) => m.markerId.value == "destination"),
      );
    }

    _parkingLocations.forEach((id, pos) {
      double hue = BitmapDescriptor.hueBlue; // Varsayılan: Mavi

      // Eğer bu park API'nin önerdiği EN İYİ park ise: SARI
      if (id == _recommendedParkId) {
        hue = BitmapDescriptor.hueYellow;
      }

      // Eğer kullanıcı şu an bu otoparkın kartına bakıyorsa: YEŞİL
      if (_selectedPark != null && id == _selectedPark!['park_id'].toString()) {
        hue = BitmapDescriptor.hueGreen;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(id),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => _onMarkerTap(id), // Tıklama olayını bağla
        ),
      );
    });
    setState(() => _markers = newMarkers);
  }

  Future<void> _moveCamera(LatLng pos, double zoom) async {
    final controller = await _controller.future;
    controller.animateCamera(CameraUpdate.newLatLngZoom(pos, zoom));
  }

  void _onMapTap(LatLng position) async {
    setState(() {
      _isLoading = true;
      _markers.removeWhere((m) => m.markerId.value == "destination");
      _markers.add(
        Marker(
          markerId: const MarkerId("destination"),
          position: position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
      );
    });

    final result = await _apiService.getSmartRecommendation(
      position,
      const LatLng(38.7167, -9.1333),
    );

    setState(() => _isLoading = false);

    if (result != null) {
      setState(() {
        _allCandidates =
            result['all_parkings'] ?? []; // Tüm alternatifleri listeye al
        _selectedPark =
            result['recommended_parking']; // Varsayılan olarak en iyiyi seç
        _recommendedParkId = _selectedPark!['park_id'].toString();
        _isNavigationMode = true;
      });
      _refreshMarkers();
      _moveCamera(
        LatLng(_selectedPark!['latitude'], _selectedPark!['longitude']),
        15,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNavigationMode ? "Otopark Seçimi" : "Akıllı Otopark Asistanı",
        ),
        leading: _isNavigationMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _backToMainMap,
              )
            : const Icon(Icons.map),
        backgroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _initialTarget,
              zoom: 14,
            ),
            markers: _markers,
            onTap: _onMapTap,
            onMapCreated: (c) => _controller.complete(c),
            zoomControlsEnabled: false,
          ),

          if (_selectedPark != null)
            Positioned(
              bottom: 20,
              left: 15,
              right: 15,
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Otopark: ${_selectedPark!['park_id']}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // Eğer en iyi öneriyse bir etiket göster
                          if (_selectedPark!['park_id'].toString() ==
                              _recommendedParkId)
                            const Chip(
                              label: Text(
                                "En İyi Öneri",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: Colors.orange,
                            ),
                        ],
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _statIcon(
                            Icons.drive_eta,
                            "${_selectedPark!['duration_min']} dk",
                          ),
                          _statIcon(
                            Icons.directions_walk,
                            "${_selectedPark!['walk_min']} dk",
                          ),
                          _statIcon(
                            Icons.pie_chart,
                            "%${(_selectedPark!['occupancy_ratio'] * 100).toInt()}",
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _backToMainMap,
                              child: const Text("Temizle"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _launchExternalMap(),
                              icon: const Icon(Icons.navigation),
                              label: const Text("Navigasyon"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_isLoading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _statIcon(IconData icon, String text) => Column(
    children: [
      Icon(icon, color: Colors.blue),
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
    ],
  );

  void _launchExternalMap() async {
    final lat = _selectedPark!['latitude'];
    final lon = _selectedPark!['longitude'];
    final url = Uri.parse("google.navigation:q=$lat,$lon&mode=d");
    if (await canLaunchUrl(url)) await launchUrl(url);
  }
}
