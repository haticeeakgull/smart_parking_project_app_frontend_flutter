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
  List<dynamic> _allCandidates = [];
  bool _isLoading = false;

  bool _isNavigationMode = false;
  Map<String, dynamic>? _selectedPark;
  String? _recommendedParkId;

  // Yeni Eklenen: Kullanıcının tercih ettiği yürüme süresi
  int _maxWalkTime = 10;

  final LatLng _initialTarget = const LatLng(38.729062, -9.145312);

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

  void _onMarkerTap(String parkId) {
    if (_allCandidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Lütfen önce haritadan bir varış noktası seçin."),
        ),
      );
      return;
    }

    final clickedPark = _allCandidates.firstWhere(
      (p) => p['park_id'].toString() == parkId,
      orElse: () => null,
    );

    if (clickedPark != null) {
      setState(() {
        _selectedPark = clickedPark;
        _isNavigationMode = true;
      });
      _refreshMarkers();
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

    if (_markers.any((m) => m.markerId.value == "destination")) {
      newMarkers.add(
        _markers.firstWhere((m) => m.markerId.value == "destination"),
      );
    }

    _parkingLocations.forEach((id, pos) {
      double hue = BitmapDescriptor.hueBlue;

      if (id == _recommendedParkId) {
        hue = BitmapDescriptor.hueYellow;
      }

      if (_selectedPark != null && id == _selectedPark!['park_id'].toString()) {
        hue = BitmapDescriptor.hueGreen;
      }

      newMarkers.add(
        Marker(
          markerId: MarkerId(id),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
          onTap: () => _onMarkerTap(id),
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
    });

    // API'ye yürüme sınırını gönderiyoruz
    final result = await _apiService.getSmartRecommendation(
      position,
      const LatLng(38.722282, -9.135389), // Kendi konumun
      _maxWalkTime,
    );

    setState(() => _isLoading = false);

    if (result != null && result['recommended_parking'] != null) {
      setState(() {
        _allCandidates = result['all_parkings'];
        _selectedPark = result['recommended_parking'];
        _recommendedParkId = _selectedPark!['park_id'].toString();
        _isNavigationMode = true;
      });
      _refreshMarkers();
      _moveCamera(
        LatLng(_selectedPark!['latitude'], _selectedPark!['longitude']),
        15,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Sunucudan veri alınamadı, lütfen internetinizi kontrol edin.",
          ),
        ),
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

          // YENİ EKLENEN: Maksimum Yürüme Süresi Sürgüsü (Slider)
          Positioned(
            top: 15,
            left: 15,
            right: 15,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_walk, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Text(
                      "Max:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Expanded(
                      child: Slider(
                        value: _maxWalkTime.toDouble(),
                        min: 2,
                        max: 20,
                        divisions: 9,
                        label: "$_maxWalkTime dk",
                        onChanged: (value) {
                          setState(() => _maxWalkTime = value.toInt());
                        },
                      ),
                    ),
                    Text(
                      "$_maxWalkTime dk",
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                              label: const Text("Git"),
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
