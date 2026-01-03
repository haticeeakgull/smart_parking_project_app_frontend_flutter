import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'api_service.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ApiService _apiService = ApiService();
  int _predictionMinutes = 30;
  bool _isPredicting = false;
  final Map<String, double> _predictedRatios = {};

  // 🔥 DEĞİŞİKLİK: Listenin son halini hafızada tutuyoruz ki API'ye giderken Firestore'u tekrar okumayalım
  List<QueryDocumentSnapshot> _currentFavDocs = [];

  @override
  void initState() {
    super.initState();
    // İlk açılışta Stream'den veri gelmesini bekleyip sonra otomatik tahmin alacağız
  }

  // 🚀 OPTİMİZE EDİLMİŞ PARALEL TAHMİNLEME
  Future<void> _fetchPredictions() async {
    if (!mounted || _currentFavDocs.isEmpty) return;

    setState(() => _isPredicting = true);

    try {
      // 🛡️ OPTİMİZASYON: Tüm istekleri aynı anda (paralel) başlatıyoruz
      final List<Future<void>> predictionTasks = _currentFavDocs.map((
        doc,
      ) async {
        final data = doc.data() as Map<String, dynamic>;
        final String parkId = data['park_id'].toString();

        final result = await _apiService.getPrediction(
          parkId,
          _predictionMinutes,
        );

        if (result != null && result['predicted_occupancy_ratio'] != null) {
          _predictedRatios[parkId] =
              (result['predicted_occupancy_ratio'] as num).toDouble();
        }
      }).toList();

      await Future.wait(predictionTasks); // Hepsinin bitmesini bekle

      if (mounted) setState(() => _isPredicting = false);
    } catch (e) {
      debugPrint("❌ Tahminleme Hatası: $e");
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text(
          "Favorilerim",
          style: TextStyle(
            color: Color(0xFF0D47A1),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          if (_isPredicting)
            const Center(
              child: Padding(
                padding: EdgeInsets.only(right: 15),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildPredictionControl(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid)
                  .collection('favorites')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting)
                  return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const Center(
                    child: Text("Henüz favori otoparkınız yok."),
                  );

                // 🛡️ ÖNEMLİ: Mevcut listeyi güncelle (FetchPredictions bunu kullanacak)
                _currentFavDocs = snapshot.data!.docs;

                // Eğer sayfa yeni açıldıysa ve tahminler boşsa bir kere çek
                if (_predictedRatios.isEmpty && !_isPredicting) {
                  Future.microtask(() => _fetchPredictions());
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _currentFavDocs.length,
                  itemBuilder: (context, index) {
                    final data =
                        _currentFavDocs[index].data() as Map<String, dynamic>;
                    final String parkId = data['park_id'].toString();
                    double? apiRatio = _predictedRatios[parkId];
                    double firestoreRatio =
                        (data['occupancy_ratio'] as num?)?.toDouble() ?? 0.0;

                    return _buildFavoriteCard(
                      data,
                      _currentFavDocs[index].id,
                      apiRatio ?? firestoreRatio,
                      isPredicted: apiRatio != null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionControl() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Tahmin Penceresi",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "$_predictionMinutes dk sonra",
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _predictionMinutes.toDouble(),
            min: 5,
            max: 240,
            divisions: 4,
            onChanged: (v) => setState(
              () => _predictionMinutes = v.toInt(),
            ), // Sadece sayı güncellenir (İstek yok)
            onChangeEnd: (v) =>
                _fetchPredictions(), // 🛡️ Sadece parmağını çekince 1 kez istek atar
          ),
        ],
      ),
    );
  }

  // Card tasarımı ve Rename dialog kısımları aynı kalabilir (Zaten temizler)...
  // (Kısalık adına o kısımları tekrar eklemedim ama senin kodundaki hali okeydir)
  Widget _buildFavoriteCard(
    Map<String, dynamic> data,
    String docId,
    double occupancy, {
    bool isPredicted = false,
  }) {
    // Senin mevcut Card kodun...
    return Card(
      child: ListTile(
        title: Text(data['custom_name'] ?? "Otopark"),
        trailing: Text("%${(occupancy * 100).toInt()}"),
      ),
    );
  }
}
