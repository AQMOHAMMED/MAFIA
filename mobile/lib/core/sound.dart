import 'package:audioplayers/audioplayers.dart';

// نغمات قصيرة (نفس اللي بالموقع): 330 ليل، 660 صبح، 780 دعوة، 220 مافيا، 880 صالح
class Sound {
  static Future<void> play(int tone) async {
    try {
      final p = AudioPlayer();
      await p.setPlayerMode(PlayerMode.lowLatency);
      p.onPlayerComplete.listen((_) => p.dispose());
      await p.play(AssetSource('sfx/t$tone.wav'), volume: .8);
    } catch (_) {}
  }
}
