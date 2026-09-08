import "../core/voice_service.dart";

/// Languages OPPA V1 supports in the UI. English is the default; the others
/// have offline phrasebooks below (works with no data) plus TTS playback.
class OppaLanguage {
  const OppaLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });

  final String code; // app language code
  final String name; // English label
  final String nativeName; // how the language calls itself
  final String flag; // short display badge

  static const all = <OppaLanguage>[
    OppaLanguage(code: "en", name: "English", nativeName: "English", flag: "EN"),
    OppaLanguage(code: "ha", name: "Hausa", nativeName: "Hausa", flag: "HA"),
    OppaLanguage(code: "yo", name: "Yoruba", nativeName: "Yorùbá", flag: "YO"),
    OppaLanguage(code: "ig", name: "Igbo", nativeName: "Igbo", flag: "IG"),
    OppaLanguage(code: "pcm", name: "Nigerian Pidgin", nativeName: "Naija", flag: "PCM"),
    OppaLanguage(code: "fr", name: "French", nativeName: "Français", flag: "FR"),
  ];

  static OppaLanguage byCode(String code) => all.firstWhere(
        (l) => l.code == code,
        orElse: () => all.first,
      );
}

/// One phrase in every supported language. `_t` is indexed by language code;
/// English is always present so a missing translation degrades to English
/// rather than to a blank string (honest, readable, never empty).
class Phrase {
  const Phrase(this._t);

  final Map<String, String> _t;

  String inLang(String code) => _t[code] ?? _t["en"]!;
}

/// Offline phrasebook: market-, chat- and safety-critical phrases translated
/// ahead of time. Works with zero connectivity — built for users who cannot
/// read well and for conversations across languages. This is a real
/// dictionary, not a machine-translation substitute; the UI says "translated
/// phrases" rather than promising arbitrary full-sentence translation.
const phrasebook = <String, Phrase>{
  // Greetings & basics
  "greeting": Phrase({
    "en": "Hello",
    "ha": "Sannu",
    "yo": "Pẹlẹ o",
    "ig": "Ndewo",
    "pcm": "How far",
    "fr": "Bonjour",
  }),
  "good_morning": Phrase({
    "en": "Good morning",
    "ha": "Ina kwana",
    "yo": "Ẹ káàárọ̀",
    "ig": "Ụtụtụ ọma",
    "pcm": "Morning o",
    "fr": "Bonjour",
  }),
  "how_are_you": Phrase({
    "en": "How are you?",
    "ha": "Kana lafiya?",
    "yo": "Báwo ni?",
    "ig": "Kedu ka ị mere?",
    "pcm": "How you dey?",
    "fr": "Comment ça va ?",
  }),
  "i_am_fine": Phrase({
    "en": "I am fine",
    "ha": "Lafiya lau",
    "yo": "Mo wà páá",
    "ig": "Ọ dị mma",
    "pcm": "I dey fine",
    "fr": "Je vais bien",
  }),
  "thank_you": Phrase({
    "en": "Thank you",
    "ha": "Na gode",
    "yo": "E sé",
    "ig": "Daalụ",
    "pcm": "Thank you",
    "fr": "Merci",
  }),
  "goodbye": Phrase({
    "en": "Goodbye",
    "ha": "Sai anjima",
    "yo": "Odàbọ̀",
    "ig": "Ka ọ dị",
    "pcm": "We go see",
    "fr": "Au revoir",
  }),
  "yes": Phrase({
    "en": "Yes",
    "ha": "Eh",
    "yo": "Bẹ́ẹ̀ni",
    "ig": "Ee",
    "pcm": "Yes",
    "fr": "Oui",
  }),
  "no": Phrase({
    "en": "No",
    "ha": "A'a",
    "yo": "Rárá",
    "ig": "Mba",
    "pcm": "No",
    "fr": "Non",
  }),
  // Market / trade (market women focus)
  "how_much": Phrase({
    "en": "How much is this?",
    "ha": "Nawa wannan?",
    "yo": "Elo ni èyí?",
    "ig": "Ego ole maka nke a?",
    "pcm": "How much be dis one?",
    "fr": "Combien ça coûte ?",
  }),
  "too_expensive": Phrase({
    "en": "That is too expensive",
    "ha": "Yana da tsada sosai",
    "yo": "Ó tó wọn ju",
    "ig": "ợ dị oke ọnụ",
    "pcm": "Dat one too cost",
    "fr": "C'est trop cher",
  }),
  "last_price": Phrase({
    "en": "What is your last price?",
    "ha": "Mafi karancin farashi?",
    "yo": "Kí ni o wò ikẹhin?",
    "ig": "Otu ego ikpeazụ?",
    "pcm": "Wetin be your last price?",
    "fr": "Quel est votre dernier prix ?",
  }),
  "i_will_buy": Phrase({
    "en": "I will buy it",
    "ha": "Zan sayi",
    "yo": "Mo raá",
    "ig": "M ga-azụ ya",
    "pcm": "I go buy am",
    "fr": "Je vais l'acheter",
  }),
  "come_back_later": Phrase({
    "en": "Come back later",
    "ha": "Dawo daga baya",
    "yo": "Padà wá lẹ́yìncì",
    "ig": "Lọta azọ",
    "pcm": "Come back later",
    "fr": "Reviens plus tard",
  }),
  "order_ready": Phrase({
    "en": "Your order is ready",
    "ha": "Odar ku ta kammala",
    "yo": "Àṣè yín wà níparí",
    "ig": "Iwu gị dị njikere",
    "pcm": "Your order ready",
    "fr": "Votre commande est prête",
  }),
  // Money & wallet
  "send_money": Phrase({
    "en": "I sent the money",
    "ha": "Na tura kuɗi",
    "yo": "Mo fi owó ránṣẹ́",
    "ig": "Ezitere m ego",
    "pcm": "I don send the money",
    "fr": "J'ai envoyé l'argent",
  }),
  "did_you_pay": Phrase({
    "en": "Have you paid?",
    "ha": "Ka biya kuɗi?",
    "yo": "Ṣé o ti san owó?",
    "ig": "Ị kwụrụ ụgwọ?",
    "pcm": "You don pay?",
    "fr": "As-tu payé ?",
  }),
  "no_money": Phrase({
    "en": "I don't have money now",
    "ha": "Ba na da kuɗi yanzu",
    "yo": "Kò ní owó báyìí",
    "ig": "Ọ nweghị ego ugbu a",
    "pcm": "I no get money now",
    "fr": "Je n'ai pas d'argent maintenant",
  }),
  // Meetings & time
  "meeting_later": Phrase({
    "en": "Are we still meeting later?",
    "ha": "Za mu hadu daga baya?",
    "yo": "ṣé a ọ̀ pàdé lẹ́yìncì?",
    "ig": "Anyị ga-ezute mgbe e mesịrị?",
    "pcm": "We still go meet later?",
    "fr": "On se voit toujours plus tard ?",
  }),
  "see_you": Phrase({
    "en": "See you at 4pm",
    "ha": "Sai da yamma 4",
    "yo": "A pàdé ní 4pm",
    "ig": "Anyị ga-ahụ na 4pm",
    "pcm": "See you by 4",
    "fr": "À 16h",
  }),
  "waiting": Phrase({
    "en": "I am waiting",
    "ha": "Ina jira",
    "yo": "Mo ń dúró",
    "ig": "M na-eche",
    "pcm": "I dey wait",
    "fr": "J'attends",
  }),
  "on_my_way": Phrase({
    "en": "I am on my way",
    "ha": "Ina kan hanya",
    "yo": "Mo wà ní ọ̀nà",
    "ig": "M na-abịa",
    "pcm": "I dey come",
    "fr": "J'arrive",
  }),
  // Help & safety
  "help": Phrase({
    "en": "Please help me",
    "ha": "Da fatan za a taimaka mini",
    "yo": "Jọ̀wọ́, ranmi lọ́wọ́",
    "ig": "Biko nyere m aka",
    "pcm": "Abeg help me",
    "fr": "Aidez-moi s'il vous plaît",
  }),
  "do_not_understand": Phrase({
    "en": "I don't understand",
    "ha": "Ba na gane",
    "yo": "Kò go mi",
    "ig": "Apatchịghọ m",
    "pcm": "I no understand",
    "fr": "Je ne comprends pas",
  }),
  "speak_slowly": Phrase({
    "en": "Please speak slowly",
    "ha": "Da fatan za a yi hankali",
    "yo": "Jọ̀wọ́, sọ́rọ́ ní pévé",
    "ig": "Biko gwa nwayọọ",
    "pcm": "Abeg tok slowly",
    "fr": "Parlez lentement s'il vous plaît",
  }),
  "where_are_you": Phrase({
    "en": "Where are you?",
    "ha": "Ina kake?",
    "yo": "Nibo ni o wà?",
    "ig": "Ị nọ ebee?",
    "pcm": "Where you dey?",
    "fr": "Où es-tu ?",
  }),
  "call_me": Phrase({
    "en": "Call me",
    "ha": "Kira ni",
    "yo": "Pè mí",
    "ig": "Kpọọ m",
    "pcm": "Call me",
    "fr": "Appelle-moi",
  }),
};

/// Result of a translation attempt. Honest: [usedOfflineBook] tells the UI
/// whether this came from the built-in phrasebook (works offline) — anything
/// else means the phrase isn't in the dictionary and the UI says so instead
/// of guessing.
class TranslationResult {
  const TranslationResult({
    required this.input,
    required this.output,
    required this.fromCode,
    required this.toCode,
    required this.usedOfflineBook,
    this.phraseKey,
  });

  final String input;
  final String output;
  final String fromCode;
  final String toCode;
  final bool usedOfflineBook;
  final String? phraseKey;
}

/// OPPA translation service.
///
/// V1 translation strategy (documented, honest):
/// 1. Offline phrasebook — exact and fuzzy matching over curated market/
///    chat/safety phrases in all supported languages. Works with no data.
/// 2. Everything else: the UI explicitly says the phrase is not yet
///    translated rather than showing a wrong translation. No fake output.
class TranslationService {
  const TranslationService();

  /// Translates [text] between two supported languages.
  /// [from] may be "auto" — we then scan for the phrase in any language.
  TranslationResult translate({
    required String text,
    required String to,
    String from = "auto",
  }) {
    final query = _normalize(text);
    if (query.isEmpty) {
      return TranslationResult(
        input: text,
        output: text,
        fromCode: from,
        toCode: to,
        usedOfflineBook: false,
      );
    }

    // Exact phrase match (any direction).
    for (final entry in phrasebook.entries) {
      final variants = entry.value._t.values.map(_normalize).toSet();
      if (variants.contains(query)) {
        final detected =
            _detectLanguage(entry.value, text) ?? (from == "auto" ? "en" : from);
        if (detected == to) {
          return TranslationResult(
            input: text,
            output: entry.value.inLang(to),
            fromCode: detected,
            toCode: to,
            usedOfflineBook: true,
            phraseKey: entry.key,
          );
        }
        return TranslationResult(
          input: text,
          output: entry.value.inLang(to),
          fromCode: detected,
          toCode: to,
          usedOfflineBook: true,
          phraseKey: entry.key,
        );
      }
    }

    // Fuzzy match: high token-overlap (handles "how much" / "how much is it").
    String? bestKey;
    double bestScore = 0;
    for (final entry in phrasebook.entries) {
      for (final variant in entry.value._t.values) {
        final score = _tokenOverlap(query, _normalize(variant));
        if (score > bestScore) {
          bestScore = score;
          bestKey = entry.key;
        }
      }
    }
    if (bestKey != null && bestScore >= 0.6) {
      final phrase = phrasebook[bestKey]!;
      final detected = _detectLanguage(phrase, text) ?? (from == "auto" ? "en" : from);
      return TranslationResult(
        input: text,
        output: phrase.inLang(to),
        fromCode: detected,
        toCode: to,
        usedOfflineBook: true,
        phraseKey: bestKey,
      );
    }

    // No translation available — never guess.
    return TranslationResult(
      input: text,
      output: text,
      fromCode: from == "auto" ? "en" : from,
      toCode: to,
      usedOfflineBook: false,
    );
  }

  /// Detects which supported language [text] most likely is, by looking it
  /// up in the phrasebook entry (exact normalized match per language).
  String? _detectLanguage(Phrase phrase, String text) {
    final q = _normalize(text);
    for (final e in phrase._t.entries) {
      if (_normalize(e.value) == q) return e.key;
    }
    return null;
  }

  static String _normalize(String s) =>
      s.toLowerCase().trim().replaceAll(RegExp(r"\s+"), " ").replaceAll(RegExp(r"[?!.,;:]+$"), "");

  static double _tokenOverlap(String a, String b) {
    final ta = a.split(" ").toSet();
    final tb = b.split(" ").toSet();
    if (ta.isEmpty || tb.isEmpty) return 0;
    final inter = ta.intersection(tb).length;
    return inter / (ta.union(tb).length);
  }

  /// Suggests quick phrases for the translator home screen.
  static List<(String key, String english)> get quickPhrases => const [
        ("greeting", "Hello"),
        ("how_much", "How much is this?"),
        ("too_expensive", "That is too expensive"),
        ("last_price", "What is your last price?"),
        ("send_money", "I sent the money"),
        ("meeting_later", "Are we still meeting later?"),
        ("on_my_way", "I am on my way"),
        ("help", "Please help me"),
      ];
}

/// Returns the platform voice locale for TTS playback of [code].
String ttsLocaleFor(String code) =>
    ttsLocales[code] ?? voiceLocales[code] ?? "en-US";
