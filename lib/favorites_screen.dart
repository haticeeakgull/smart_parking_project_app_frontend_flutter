import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // LatLng için gerekli
import 'api_service.dart'; // ApiService sınıfınızın burada olduğundan emin olun

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final ApiService _apiService = ApiService();
  int _predictionMinutes = 30; // Varsayılan tahmin süresi
  bool _isPredicting = false;

  // API'den gelen tahminleri park_id bazlı tutar
  final Map<String, double> _predictedRatios = {};

  @override
  void initState() {
    super.initState();
    // Sayfa ilk açıldığında varsayılan 30dk için tahminleri çek
    _fetchPredictions();
  }

  // 🚀 GERÇEK TAHMİNLEME FONKSİYONU
  Future<void> _fetchPredictions() async {
    setState(() => _isPredicting = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final favDocs = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('favorites')
          .get();

      for (var doc in favDocs.docs) {
        final data = doc.data();
        final String parkId = data['park_id'].toString();

        // ✅ DEĞİŞİKLİK: getSmartRecommendation yerine getPrediction kullanıyoruz
        // Çünkü getPrediction fonksiyonun 'prediction_time' gönderiyor.
        final result = await _apiService.getPrediction(
          parkId,
          _predictionMinutes, // Slider'dan gelen dakika
        );

        if (result != null && result['predicted_occupancy_ratio'] != null) {
          setState(() {
            // Backend'den dönen anahtar ismine göre (örn: 'predicted_occupancy') güncelleyin
            _predictedRatios[parkId] = result['predicted_occupancy_ratio']
                .toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint("Hata: $e");
    } finally {
      setState(() => _isPredicting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FE),
      appBar: AppBar(
        title: const Text(
          "Favori Otoparklarım",
          style: TextStyle(
            color: Color(0xFF0D47A1),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        centerTitle: true,
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
          // ÜST PANEL: Dakika Ayarı
          _buildPredictionControl(),

          // LİSTE: Favori Otoparklar
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid)
                  .collection('favorites')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("Henüz favori otoparkınız yok."),
                  );
                }

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final String parkId = data['park_id'].toString();

                    // API'den gelen tahmin varsa onu al, yoksa Firestore'daki anlık veriyi kullan
                    double displayRatio =
                        _predictedRatios[parkId] ??
                        (data['occupancy_ratio'] ?? 0.0);

                    return _buildFavoriteCard(
                      data,
                      docs[index].id,
                      displayRatio,
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

  // ⏱️ Slider Kontrol Paneli
  Widget _buildPredictionControl() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Tahmin Süresi:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$_predictionMinutes dk Sonra",
                  style: const TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            value: _predictionMinutes.toDouble(),
            min: 5,
            max: 120,
            divisions: 23,
            label: "$_predictionMinutes dk",
            // Kullanıcı sürüklerken sadece arayüzü güncelle, istek atma
            onChanged: (v) {
              setState(() {
                _predictionMinutes = v.toInt();
              });
            },
            // Kullanıcı parmağını çektiğinde TEK BİR KEZ istek at
            onChangeEnd: (v) {
              _fetchPredictions();
            },
          ),
          const Text(
            "Slider'ı bırakınca tahminler güncellenir.",
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // 🚗 Otopark Kart Tasarımı
  Widget _buildFavoriteCard(
    Map<String, dynamic> data,
    String docId,
    double occupancy,
  ) {
    String customName = data['custom_name'] ?? "Otopark: ${data['park_id']}";
    Color statusColor = occupancy > 0.8
        ? Colors.red
        : (occupancy > 0.5 ? Colors.orange : Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFF0D47A1),
            child: const Icon(Icons.local_parking, color: Colors.white),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.edit,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      onPressed: () => _showRenameDialog(docId, customName),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: occupancy,
                  backgroundColor: Colors.grey.shade100,
                  color: statusColor,
                  minHeight: 8,
                ),
              ],
            ),
          ),
          const SizedBox(width: 15),
          Text(
            "%${(occupancy * 100).toInt()}",
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }

  // 📝 Otopark İsmini Güncelleme Penceresi
  void _showRenameDialog(String docId, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Otoparkı Yeniden Adlandır"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: "Yeni İsim",
            hintText: "Örn: İş Yeri Otoparkı",
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Vazgeç"),
          ),
          ElevatedButton(
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null && controller.text.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('favorites')
                    .doc(docId)
                    .update({'custom_name': controller.text});
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text("Kaydet"),
          ),
        ],
      ),
    );
  }
}
