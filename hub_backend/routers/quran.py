from fastapi import APIRouter, HTTPException
import httpx
from models.schemas import Surah, ReciterInfo, QuranPlayRequest

router = APIRouter(prefix="/quran", tags=["Coran"])

QURAN_API = "https://api.quran.com/api/v4"

RECITERS = [
    ReciterInfo(id=7,  name="Mishary Rashid Al-Afasy", style="Murattal"),
    ReciterInfo(id=1,  name="AbdulBaset AbdulSamad",   style="Murattal"),
    ReciterInfo(id=9,  name="Mahmoud Khalil Al-Hussary", style="Murattal"),
    ReciterInfo(id=10, name="Mohamed Siddiq Al-Minshawi", style="Murattal"),
    ReciterInfo(id=2,  name="Abu Bakr Al-Shatri",       style="Murattal"),
]


@router.get("/surahs", response_model=list[Surah])
async def get_surahs():
    """Liste des 114 sourates."""
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            r = await client.get(f"{QURAN_API}/chapters?language=fr")
            r.raise_for_status()
            data = r.json()["chapters"]
            return [
                Surah(
                    number=s["id"],
                    name_ar=s["name_arabic"],
                    name_en=s["name_simple"],
                    name_fr=s.get("translated_name", {}).get("name", s["name_simple"]),
                    verses_count=s["verses_count"],
                    revelation_type=s["revelation_place"],
                )
                for s in data
            ]
        except Exception as e:
            raise HTTPException(503, f"Quran API unavailable: {e}")


@router.get("/surahs/{number}")
async def get_surah(number: int):
    """Détail d'une sourate avec versets."""
    async with httpx.AsyncClient(timeout=10) as client:
        try:
            r = await client.get(
                f"{QURAN_API}/verses/by_chapter/{number}",
                params={"language": "fr", "words": True, "translations": "136", "per_page": 300},
            )
            r.raise_for_status()
            return r.json()
        except Exception as e:
            raise HTTPException(503, f"Quran API unavailable: {e}")


@router.get("/reciters", response_model=list[ReciterInfo])
async def get_reciters():
    return RECITERS


@router.get("/audio/{surah}/{reciter_id}")
async def get_audio_url(surah: int, reciter_id: int = 7):
    """
    Retourne l'URL audio d'une sourate pour un récitateur.
    L'app Flutter stream directement depuis cette URL.
    """
    # Mapping reciter_id → code évrsaan Quran.com
    reciter_map = {
        7:  "ar.alafasy",
        1:  "ar.abdulbasitmurattal",
        9:  "ar.husary",
        10: "ar.minshawi",
        2:  "ar.abubackrshatri",
    }
    style = reciter_map.get(reciter_id, "ar.alafasy")
    url = f"https://verses.quran.com/{style}/{surah:03d}.mp3"
    return {"surah": surah, "reciter_id": reciter_id, "url": url}
