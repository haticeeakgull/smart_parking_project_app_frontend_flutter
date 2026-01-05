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
  List<QueryDocumentSnapshot> _currentFavDocs = [];

  Future<void> _fetchPredictions() async {
    if (!mounted || _currentFavDocs.isEmpty) return;
    setState(() => _isPredicting = true);
    try {
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
      await Future.wait(predictionTasks);
      if (mounted) setState(() => _isPredicting = false);
    } catch (e) {
      if (mounted) setState(() => _isPredicting = false);
    }
  }

  void _editParkingName(String docId, String currentName) {
    final TextEditingController controller = TextEditingController(
      text: currentName,
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Otopark Adını Düzenle"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: "Otopark Takma Adı"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İptal"),
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

  // FAVORİLERDEN ÇIKARMA FONKSİYONU
  void _removeFavorite(String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Favorilerden Çıkar"),
        content: const Text(
          "Bu otoparkı favorilerinizden silmek istediğinize emin misiniz?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Vazgeç"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .collection('favorites')
                    .doc(docId)
                    .delete();
                if (mounted) Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Favorilerden çıkarıldı.")),
                );
              }
            },
            child: const Text("Sil"),
          ),
        ],
      ),
    );
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
                _currentFavDocs = snapshot.data!.docs;
                if (_predictedRatios.isEmpty && !_isPredicting)
                  Future.microtask(() => _fetchPredictions());

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: _currentFavDocs.length,
                  itemBuilder: (context, index) {
                    final doc = _currentFavDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final String parkId = data['park_id'].toString();
                    double? apiRatio = _predictedRatios[parkId];
                    double firestoreRatio =
                        (data['occupancy_ratio'] as num?)?.toDouble() ?? 0.0;
                    return _buildFavoriteCard(
                      data,
                      doc.id,
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
            min: 0,
            max: 300,
            divisions: 10,
            activeColor: const Color(0xFF0D47A1),
            onChanged: (v) => setState(() => _predictionMinutes = v.toInt()),
            onChangeEnd: (v) => _fetchPredictions(),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteCard(
    Map<String, dynamic> data,
    String docId,
    double occupancy, {
    bool isPredicted = false,
  }) {
    String displayName = data['custom_name'] ?? "Otopark: ${data['park_id']}";
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 10,
        ),
        leading: CircleAvatar(
          backgroundColor: isPredicted
              ? Colors.blue.shade100
              : Colors.grey.shade200,
          child: Icon(
            Icons.local_parking,
            color: isPredicted ? const Color(0xFF0D47A1) : Colors.grey,
          ),
        ),
        title: Text(
          displayName,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text(isPredicted ? "Tahmini Doluluk" : "Anlık Doluluk"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "%${(occupancy * 100).toInt()}",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: occupancy > 0.8 ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.edit_note, color: Colors.blueGrey),
              onPressed: () => _editParkingName(docId, displayName),
            ),
            // SİLME BUTONU
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _removeFavorite(docId),
            ),
          ],
        ),
      ),
    );
  }
}
