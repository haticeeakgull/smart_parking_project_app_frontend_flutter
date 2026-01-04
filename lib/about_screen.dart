import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Hakkında"),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0D47A1),
        elevation: 1,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Icon(
                Icons.smart_toy_rounded,
                size: 80,
                color: Color(0xFF0D47A1),
              ),
            ),
            const SizedBox(height: 20),
            const Center(
              child: Text(
                "ParkAsistan v1.0",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
            const Divider(height: 40),
            _buildFeatureItem(
              Icons.auto_graph,
              "Yapay Zeka Destekli Tahminleme",
              "Uygulamamız, otopark doluluk oranlarını yarım saatlik aralıklarla analiz eder ve gelecek zaman dilimleri için yüksek doğrulukla tahminlerde bulunur.",
            ),
            _buildFeatureItem(
              Icons.my_location,
              "Akıllı Rota Optimizasyonu",
              "Gitmek istediğiniz konumu işaretlediğinizde, sadece en yakın değil; doluluk oranı, yürüme mesafesi ve sürüş süresi açısından 'en mantıklı' otoparkı sizin için seçer.",
            ),
            _buildFeatureItem(
              Icons.favorite,
              "Favori Otopark Yönetimi",
              "Sık kullandığınız otoparkları favorilerinize ekleyerek, tek bir dokunuşla güncel doluluk bilgilerine ve konumlarına ulaşabilirsiniz.",
            ),
            _buildFeatureItem(
              Icons.bar_chart_rounded,
              "Gelişmiş Analiz Ekranı",
              "Her otopark için özel olarak hazırlanan grafikler sayesinde, günün hangi saatinde ne kadar doluluk beklendiğini görebilir, seyahatinizi buna göre planlayabilirsiniz.",
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Bu uygulama, şehir içi park sorunlarını teknoloji ile minimize etmek ve sürücülere zaman kazandırmak amacıyla geliştirilmiştir.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.blueGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF0D47A1), size: 30),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
