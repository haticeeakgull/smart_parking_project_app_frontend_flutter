import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'api_service.dart';

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  final ApiService _apiService = ApiService();
  String? _selectedParkId;
  List<dynamic> _graphData = [];
  bool _isLoading = false;
  List<Map<String, String>> _dynamicParks = [];

  // --- Analiz Yardımcı Fonksiyonları ---

  // En yoğun saat dilimini bulur
  String get _peakHour {
    if (_graphData.isEmpty) return "--:--";
    var peak = _graphData.reduce(
      (curr, next) => curr['ratio'] > next['ratio'] ? curr : next,
    );
    return peak['time'];
  }

  // En müsait (boş) saat dilimini bulur
  String get _emptyHour {
    if (_graphData.isEmpty) return "--:--";
    var empty = _graphData.reduce(
      (curr, next) => curr['ratio'] < next['ratio'] ? curr : next,
    );
    return empty['time'];
  }

  // Günlük ortalama doluluk oranını hesaplar
  String get _averageOccupancy {
    if (_graphData.isEmpty) return "%0";
    double sum = _graphData.fold(0, (prev, element) => prev + element['ratio']);
    return "%${((sum / _graphData.length) * 100).toStringAsFixed(0)}";
  }

  @override
  void initState() {
    super.initState();
    _fetchParksFromFirebase();
  }

  Future<void> _fetchParksFromFirebase() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('otoparklar')
          .get();
      final List<Map<String, String>> fetchedParks = snapshot.docs.map((doc) {
        return {"id": doc.id, "name": "Otopark: ${doc.id}"};
      }).toList();

      setState(() {
        _dynamicParks = fetchedParks;
      });
    } catch (e) {
      debugPrint("Firebase otopark listesi hatası: $e");
    }
  }

  Future<void> _loadGraphData(String parkId) async {
    setState(() => _isLoading = true);
    final data = await _apiService.getOccupancyGraph(parkId);
    setState(() {
      _graphData = data ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // Hafif gri arka plan
      appBar: AppBar(
        title: const Text("Yoğunluk Analizi"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        // Taşmaları önlemek için
        child: Column(
          children: [
            // Otopark Seçimi
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  labelText: "Otopark Seçiniz",
                  prefixIcon: const Icon(Icons.local_parking),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                value: _selectedParkId,
                items: _dynamicParks.isEmpty
                    ? [
                        const DropdownMenuItem(
                          value: null,
                          child: Text("Yükleniyor..."),
                        ),
                      ]
                    : _dynamicParks.map((park) {
                        return DropdownMenuItem(
                          value: park['id'],
                          child: Text(park['name']!),
                        );
                      }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedParkId = val);
                    _loadGraphData(val);
                  }
                },
              ),
            ),

            // Grafik Alanı
            Container(
              height: 300,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.only(
                top: 20,
                right: 25,
                left: 10,
                bottom: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _graphData.isEmpty
                  ? const Center(
                      child: Text("Veri göstermek için otopark seçin"),
                    )
                  : _buildMainChart(),
            ),

            const SizedBox(height: 20),

            // Analiz Kartları (KPIs)
            if (_graphData.isNotEmpty) _buildQuickStats(),

            if (_graphData.isNotEmpty) _buildLegend(),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMainChart() {
    return LineChart(
      LineChartData(
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (touchedSpot) =>
                const Color(0xFF0D47A1).withOpacity(0.8),
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                final time = _graphData[spot.x.toInt()]['time'];
                return LineTooltipItem(
                  "$time\n%${spot.y.toStringAsFixed(1)}",
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              }).toList();
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 20,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 20,
              getTitlesWidget: (value, meta) => Text(
                "%${value.toInt()}",
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              reservedSize: 35,
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 4,
              getTitlesWidget: (value, meta) {
                int index = value.toInt();
                if (index < _graphData.length && index % 4 == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _graphData[index]['time'],
                      style: const TextStyle(color: Colors.grey, fontSize: 10),
                    ),
                  );
                }
                return const SizedBox();
              },
              reservedSize: 30,
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_graphData.length - 1).toDouble(),
        minY: 0,
        maxY: 100,
        lineBarsData: [
          LineChartBarData(
            spots: _graphData.asMap().entries.map((e) {
              return FlSpot(
                e.key.toDouble(),
                (e.value['ratio'] as double) * 100,
              );
            }).toList(),
            isCurved: true,
            curveSmoothness: 0.35,
            color: const Color(0xFF0D47A1),
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF0D47A1).withOpacity(0.3),
                  const Color(0xFF0D47A1).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _statCard("En Yoğun", _peakHour, Icons.trending_up, Colors.redAccent),
          const SizedBox(width: 12),
          _statCard("En Uygun", _emptyHour, Icons.trending_down, Colors.green),
          const SizedBox(width: 12),
          _statCard(
            "Ortalama",
            _averageOccupancy,
            Icons.analytics,
            Colors.blue,
          ),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF263238),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                "Yapay zeka modeline göre önümüzdeki 24 saatlik tahmin.",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
