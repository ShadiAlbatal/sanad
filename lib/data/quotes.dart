class Quote {
  final String arabic;
  final String english;
  final String source;
  const Quote({
    required this.arabic,
    required this.english,
    required this.source,
  });
}

// Short, widely-known ayat and authentic ahadith. Arabic is fully diacritized
// and must be human-verified before release (see task note).
const quotes = <Quote>[
  Quote(
    arabic: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا\nإِنَّ مَعَ الْعُسْرِ يُسْرًا',
    english: 'For indeed, with hardship comes ease. Indeed, with hardship comes ease.',
    source: 'Qurʾān 94:5–6',
  ),
  Quote(
    arabic: 'فَاذْكُرُونِي أَذْكُرْكُمْ وَاشْكُرُوا لِي وَلَا تَكْفُرُونِ',
    english: 'So remember Me; I will remember you. And be grateful to Me, and do not deny Me.',
    source: 'Qurʾān 2:152',
  ),
  Quote(
    arabic: 'أَلَا بِذِكْرِ اللَّهِ تَطْمَئِنُّ الْقُلُوبُ',
    english: 'Verily, in the remembrance of Allah do hearts find rest.',
    source: 'Qurʾān 13:28',
  ),
  Quote(
    arabic: 'وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا',
    english: 'And whoever is mindful of Allah, He will make for him a way out.',
    source: 'Qurʾān 65:2',
  ),
  Quote(
    arabic: 'وَيَرْزُقْهُ مِنْ حَيْثُ لَا يَحْتَسِبُ',
    english: 'And He provides for him from where he does not expect.',
    source: 'Qurʾān 65:3',
  ),
  Quote(
    arabic: 'لَا يُكَلِّفُ اللَّهُ نَفْسًا إِلَّا وُسْعَهَا',
    english: 'Allah does not burden a soul beyond that it can bear.',
    source: 'Qurʾān 2:286',
  ),
  Quote(
    arabic: 'وَلَا تَهِنُوا وَلَا تَحْزَنُوا وَأَنتُمُ الْأَعْلَوْنَ إِن كُنتُم مُّؤْمِنِينَ',
    english: 'Do not lose heart nor grieve; you shall be superior if you are true believers.',
    source: 'Qurʾān 3:139',
  ),
  Quote(
    arabic: 'سَيَجْعَلُ اللَّهُ بَعْدَ عُسْرٍ يُسْرًا',
    english: 'Allah will bring about ease after hardship.',
    source: 'Qurʾān 65:7',
  ),
  Quote(
    arabic: 'إِنَّ اللَّهَ مَعَ الصَّابِرِينَ',
    english: 'Indeed, Allah is with the patient.',
    source: 'Qurʾān 2:153',
  ),
  Quote(
    arabic: 'حَسْبُنَا اللَّهُ وَنِعْمَ الْوَكِيلُ',
    english: 'Allah is sufficient for us, and He is the best Disposer of affairs.',
    source: 'Qurʾān 3:173',
  ),
  Quote(
    arabic: 'وَقَالَ رَبُّكُمُ ادْعُونِي أَسْتَجِبْ لَكُمْ',
    english: 'And your Lord says: Call upon Me; I will respond to you.',
    source: 'Qurʾān 40:60',
  ),
  Quote(
    arabic: 'وَقُل رَّبِّ زِدْنِي عِلْمًا',
    english: 'And say: My Lord, increase me in knowledge.',
    source: 'Qurʾān 20:114',
  ),
  Quote(
    arabic: 'اتَّقِ اللَّهَ حَيْثُمَا كُنْتَ',
    english: 'Be mindful of Allah wherever you are.',
    source: 'Sunan al-Tirmidhī',
  ),
  Quote(
    arabic: 'مَنْ كَانَ يُؤْمِنُ بِاللَّهِ وَالْيَوْمِ الْآخِرِ فَلْيَقُلْ خَيْرًا أَوْ لِيَصْمُتْ',
    english: 'Whoever believes in Allah and the Last Day, let him speak good or remain silent.',
    source: 'Ṣaḥīḥ al-Bukhārī',
  ),
];

Quote dailyQuote(DateTime t) {
  final dayOfYear =
      DateTime(t.year, t.month, t.day).difference(DateTime(t.year)).inDays;
  return quotes[dayOfYear % quotes.length];
}
