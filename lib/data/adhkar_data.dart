class Dhikr {
  final String id;
  final String arabic;
  final String translit;
  final String translation;
  final int repeat;
  const Dhikr({
    required this.id,
    required this.arabic,
    required this.translit,
    required this.translation,
    this.repeat = 1,
  });
}

class AdhkarCategory {
  final String title;
  final String subtitle;
  final List<Dhikr> items;
  const AdhkarCategory(this.title, this.subtitle, this.items);
}

// Starter set — widely-memorized adhkar. Expand over time.
const adhkarCategories = <AdhkarCategory>[
  AdhkarCategory('Tasbih', 'General remembrance', [
    Dhikr(
      id: 'subhanallah',
      arabic: 'سُبْحَانَ اللَّهِ',
      translit: 'Subḥān Allāh',
      translation: 'Glory be to Allah',
      repeat: 33,
    ),
    Dhikr(
      id: 'alhamdulillah',
      arabic: 'الْحَمْدُ لِلَّهِ',
      translit: 'Al-ḥamdu lillāh',
      translation: 'All praise is due to Allah',
      repeat: 33,
    ),
    Dhikr(
      id: 'allahuakbar',
      arabic: 'اللَّهُ أَكْبَرُ',
      translit: 'Allāhu akbar',
      translation: 'Allah is the Greatest',
      repeat: 34,
    ),
    Dhikr(
      id: 'tahlil',
      arabic:
          'لَا إِلَٰهَ إِلَّا اللَّهُ وَحْدَهُ لَا شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَىٰ كُلِّ شَيْءٍ قَدِيرٌ',
      translit:
          'Lā ilāha illā-llāhu waḥdahu lā sharīka lah, lahu-l-mulku wa lahu-l-ḥamd, wa huwa ʿalā kulli shayʾin qadīr',
      translation:
          'There is no god but Allah alone, with no partner. His is the dominion and His is the praise, and He is over all things competent.',
      repeat: 10,
    ),
    Dhikr(
      id: 'istighfar',
      arabic: 'أَسْتَغْفِرُ اللَّهَ',
      translit: 'Astaghfiru-llāh',
      translation: 'I seek forgiveness from Allah',
      repeat: 100,
    ),
    Dhikr(
      id: 'salawat',
      arabic: 'اللَّهُمَّ صَلِّ وَسَلِّمْ عَلَىٰ نَبِيِّنَا مُحَمَّدٍ',
      translit: 'Allāhumma ṣalli wa sallim ʿalā nabiyyinā Muḥammad',
      translation: 'O Allah, send blessings and peace upon our Prophet Muhammad',
      repeat: 10,
    ),
  ]),
  AdhkarCategory('Morning & Evening', 'Adhkar of protection', [
    Dhikr(
      id: 'me_hasbi',
      arabic:
          'حَسْبِيَ اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ، عَلَيْهِ تَوَكَّلْتُ، وَهُوَ رَبُّ الْعَرْشِ الْعَظِيمِ',
      translit:
          'Ḥasbiya-llāhu lā ilāha illā huwa, ʿalayhi tawakkaltu, wa huwa rabbu-l-ʿarshi-l-ʿaẓīm',
      translation:
          'Allah is sufficient for me; there is no god but Him. Upon Him I rely, and He is the Lord of the Great Throne.',
      repeat: 7,
    ),
    Dhikr(
      id: 'me_bismillah',
      arabic:
          'بِسْمِ اللَّهِ الَّذِي لَا يَضُرُّ مَعَ اسْمِهِ شَيْءٌ فِي الْأَرْضِ وَلَا فِي السَّمَاءِ وَهُوَ السَّمِيعُ الْعَلِيمُ',
      translit:
          'Bismi-llāhi-lladhī lā yaḍurru maʿa-smihi shayʾun fi-l-arḍi wa lā fi-s-samāʾi wa huwa-s-samīʿu-l-ʿalīm',
      translation:
          'In the name of Allah, with whose name nothing on earth or in heaven can cause harm, and He is the All-Hearing, the All-Knowing.',
      repeat: 3,
    ),
    Dhikr(
      id: 'me_radhitu',
      arabic:
          'رَضِيتُ بِاللَّهِ رَبًّا، وَبِالْإِسْلَامِ دِينًا، وَبِمُحَمَّدٍ صَلَّى اللَّهُ عَلَيْهِ وَسَلَّمَ نَبِيًّا',
      translit:
          'Raḍītu bi-llāhi rabban, wa bi-l-islāmi dīnan, wa bi-Muḥammadin ṣalla-llāhu ʿalayhi wa sallama nabiyyan',
      translation:
          'I am pleased with Allah as Lord, with Islam as religion, and with Muhammad (peace be upon him) as Prophet.',
      repeat: 3,
    ),
  ]),
];
