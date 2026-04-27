from fastapi import APIRouter
from models.schemas import AzkarResponse, Zikr

router = APIRouter(prefix="/azkar", tags=["Azkar"])

# Hisn al-Muslim — extrait structuré (source complète à ingérer Phase 3)
_AZKAR_DB: list[dict] = [
    # ── Matin ────────────────────────────────────────────────────────────────
    {"id": 1, "category": "morning", "count": 3, "source": "Sahih Muslim 2691",
     "text_ar": "أَعُوذُ بِاللهِ مِنَ الشَّيْطَانِ الرَّجِيمِ",
     "text_fr": "Je cherche refuge auprès d'Allah contre le diable maudit",
     "text_en": "I seek refuge in Allah from the accursed devil"},
    {"id": 2, "category": "morning", "count": 1, "source": "Quran 40:55",
     "text_ar": "اللَّهُمَّ بِكَ أَصْبَحْنَا وَبِكَ أَمْسَيْنَا وَبِكَ نَحْيَا وَبِكَ نَمُوتُ وَإِلَيْكَ النُّشُورُ",
     "text_fr": "Ô Allah, c'est par Toi que nous entrons dans le matin, par Toi dans le soir, par Toi nous vivons et par Toi nous mourons, et vers Toi est la résurrection",
     "text_en": "O Allah, by You we enter the morning, by You we enter the evening, by You we live and die, and to You is the resurrection"},
    {"id": 3, "category": "morning", "count": 1, "source": "Sunan Abu Dawud 5068",
     "text_ar": "اللَّهُمَّ أَنْتَ رَبِّي لاَ إِلَهَ إِلاَّ أَنْتَ، خَلَقْتَنِي وَأَنَا عَبْدُكَ",
     "text_fr": "Ô Allah, Tu es mon Seigneur, il n'y a de divinité que Toi, Tu m'as créé et je suis Ton serviteur",
     "text_en": "O Allah, You are my Lord, there is none worthy of worship except You, You created me and I am Your servant"},
    {"id": 4, "category": "morning", "count": 100, "source": "Sahih Bukhari 6406",
     "text_ar": "سُبْحَانَ اللهِ وَبِحَمْدِهِ",
     "text_fr": "Gloire à Allah et louange à Lui",
     "text_en": "Glory be to Allah and praise be to Him"},
    # ── Soir ─────────────────────────────────────────────────────────────────
    {"id": 10, "category": "evening", "count": 1, "source": "Sunan Abu Dawud 5071",
     "text_ar": "اللَّهُمَّ بِكَ أَمْسَيْنَا وَبِكَ أَصْبَحْنَا وَبِكَ نَحْيَا وَبِكَ نَمُوتُ وَإِلَيْكَ الْمَصِيرُ",
     "text_fr": "Ô Allah, c'est par Toi que nous entrons dans le soir, par Toi dans le matin, par Toi nous vivons et mourons, et vers Toi est le retour",
     "text_en": "O Allah, by You we enter the evening, by You the morning, by You we live and die, and to You is the return"},
    {"id": 11, "category": "evening", "count": 3, "source": "Sunan Abu Dawud 5088",
     "text_ar": "أَمْسَيْنَا وَأَمْسَى الْمُلْكُ لِلَّهِ",
     "text_fr": "Nous entrons dans le soir et le royaume appartient à Allah",
     "text_en": "We have entered the evening and all sovereignty belongs to Allah"},
    {"id": 12, "category": "evening", "count": 100, "source": "Sahih Bukhari 6406",
     "text_ar": "سُبْحَانَ اللهِ وَبِحَمْدِهِ",
     "text_fr": "Gloire à Allah et louange à Lui",
     "text_en": "Glory be to Allah and praise be to Him"},
    # ── Après prière ─────────────────────────────────────────────────────────
    {"id": 20, "category": "after_prayer", "count": 33, "source": "Sahih Muslim 597",
     "text_ar": "سُبْحَانَ اللهِ",
     "text_fr": "Gloire à Allah",
     "text_en": "Glory be to Allah"},
    {"id": 21, "category": "after_prayer", "count": 33, "source": "Sahih Muslim 597",
     "text_ar": "الْحَمْدُ لِلَّهِ",
     "text_fr": "Louange à Allah",
     "text_en": "All praise is due to Allah"},
    {"id": 22, "category": "after_prayer", "count": 33, "source": "Sahih Muslim 597",
     "text_ar": "اللهُ أَكْبَرُ",
     "text_fr": "Allah est le plus grand",
     "text_en": "Allah is the greatest"},
    {"id": 23, "category": "after_prayer", "count": 1, "source": "Sahih Muslim 597",
     "text_ar": "لاَ إِلَهَ إِلاَّ اللهُ وَحْدَهُ لاَ شَرِيكَ لَهُ، لَهُ الْمُلْكُ وَلَهُ الْحَمْدُ وَهُوَ عَلَى كُلِّ شَيْءٍ قَدِيرٌ",
     "text_fr": "Il n'y a de divinité qu'Allah Seul sans associé, à Lui appartient le règne et la louange, et Il est omnipotent",
     "text_en": "There is none worthy of worship except Allah alone, with no partner, His is the dominion, His is the praise, and He has power over all things"},
    # ── Coucher ──────────────────────────────────────────────────────────────
    {"id": 30, "category": "sleep", "count": 1, "source": "Sahih Bukhari 6311",
     "text_ar": "بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا",
     "text_fr": "En Ton nom, ô Allah, je meurs et je vis",
     "text_en": "In Your name, O Allah, I die and I live"},
    {"id": 31, "category": "sleep", "count": 1, "source": "Sahih Bukhari 6320",
     "text_ar": "اللَّهُمَّ قِنِي عَذَابَكَ يَوْمَ تَبْعَثُ عِبَادَكَ",
     "text_fr": "Ô Allah, préserve-moi de Ton châtiment le jour où Tu ressusciteras Tes serviteurs",
     "text_en": "O Allah, protect me from Your punishment on the day You resurrect Your servants"},
    # ── Réveil ───────────────────────────────────────────────────────────────
    {"id": 40, "category": "wake", "count": 1, "source": "Sahih Bukhari 6312",
     "text_ar": "الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا وَإِلَيْهِ النُّشُورُ",
     "text_fr": "Louange à Allah qui nous a ramenés à la vie après nous avoir fait mourir, et vers Lui est la résurrection",
     "text_en": "Praise be to Allah who gave us life after causing us to die, and to Him is the resurrection"},
]


@router.get("/{category}", response_model=AzkarResponse)
async def get_azkar(category: str):
    """Retourne les azkar d'une catégorie : morning, evening, after_prayer, sleep, wake."""
    filtered = [Zikr(**z) for z in _AZKAR_DB if z["category"] == category]
    return AzkarResponse(category=category, azkar=filtered)


@router.get("/", response_model=list[str])
async def list_categories():
    cats = sorted(set(z["category"] for z in _AZKAR_DB))
    return cats
