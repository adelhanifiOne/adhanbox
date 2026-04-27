from fastapi import APIRouter, HTTPException
from datetime import datetime, timezone, timedelta
from models.schemas import PrayerTimesResponse, PrayerConfig, UserPreferences
from services.prayer_times import calculate_prayer_times

router = APIRouter(prefix="/prayers", tags=["Prières"])

# Prefs stockées en mémoire (Phase 1 — persisté en DB Phase 2)
_prefs = UserPreferences()


@router.get("/times", response_model=PrayerTimesResponse)
async def get_prayer_times(date: str | None = None):
    """Horaires de prière pour la date donnée (défaut: aujourd'hui)."""
    if date:
        try:
            d = datetime.strptime(date, "%Y-%m-%d")
        except ValueError:
            raise HTTPException(400, "Format de date invalide, utilise YYYY-MM-DD")
    else:
        d = datetime.now(timezone(timedelta(minutes=_prefs.timezone_offset)))

    return calculate_prayer_times(
        latitude=_prefs.latitude,
        longitude=_prefs.longitude,
        date=d,
        method=_prefs.calculation_method,
        madhab=_prefs.madhab,
        timezone_offset_min=_prefs.timezone_offset,
    )


@router.get("/next")
async def get_next_prayer():
    """Retourne uniquement la prochaine prière."""
    now = datetime.now(timezone(timedelta(minutes=_prefs.timezone_offset)))
    result = calculate_prayer_times(
        latitude=_prefs.latitude,
        longitude=_prefs.longitude,
        date=now,
        method=_prefs.calculation_method,
        madhab=_prefs.madhab,
        timezone_offset_min=_prefs.timezone_offset,
    )
    next_p = next((p for p in result.prayers if p.is_next), None)
    if not next_p:
        next_p = result.prayers[0]  # Fajr du lendemain
    return next_p


@router.post("/config")
async def update_config(config: PrayerConfig):
    """Met à jour la configuration de calcul."""
    global _prefs
    _prefs.latitude = config.latitude
    _prefs.longitude = config.longitude
    _prefs.calculation_method = config.method
    _prefs.madhab = config.madhab
    _prefs.timezone_offset = config.timezone_offset
    return {"ok": True, "config": config}


@router.get("/config")
async def get_config():
    return {
        "latitude": _prefs.latitude,
        "longitude": _prefs.longitude,
        "method": _prefs.calculation_method,
        "madhab": _prefs.madhab,
        "timezone_offset": _prefs.timezone_offset,
    }
