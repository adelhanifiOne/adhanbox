from pydantic import BaseModel
from typing import Optional
from enum import IntEnum


# ── Prières ──────────────────────────────────────────────────────────────────

class PrayerName(str):
    pass


class PrayerTime(BaseModel):
    name: str
    name_ar: str
    time: str           # "HH:MM"
    timestamp: int      # unix timestamp
    is_next: bool = False
    passed: bool = False


class PrayerTimesResponse(BaseModel):
    date: str
    location: str
    method: str
    madhab: str
    prayers: list[PrayerTime]


class PrayerConfig(BaseModel):
    latitude: float
    longitude: float
    method: str = "MWL"       # MWL, ISNA, Egypt, Makkah, Karachi, Tehran, Jafari
    madhab: str = "hanafi"    # hanafi, shafi
    timezone_offset: int = 0  # minutes from UTC


# ── Azkar ─────────────────────────────────────────────────────────────────────

class AzkarCategory(str):
    MORNING = "morning"
    EVENING = "evening"
    AFTER_PRAYER = "after_prayer"
    SLEEP = "sleep"
    WAKE = "wake"
    EATING = "eating"
    GENERAL = "general"


class Zikr(BaseModel):
    id: int
    text_ar: str
    text_fr: str
    text_en: str
    source: str
    count: int = 1
    category: str


class AzkarResponse(BaseModel):
    category: str
    azkar: list[Zikr]


# ── Coran ─────────────────────────────────────────────────────────────────────

class Surah(BaseModel):
    number: int
    name_ar: str
    name_en: str
    name_fr: str
    verses_count: int
    revelation_type: str  # Meccan / Medinan


class ReciterInfo(BaseModel):
    id: int
    name: str
    style: str


class QuranPlayRequest(BaseModel):
    surah: int
    reciter_id: int = 7  # Mishary Rashid default
    verse_from: int = 1
    verse_to: Optional[int] = None


# ── Assistant ─────────────────────────────────────────────────────────────────

class ChatMessage(BaseModel):
    role: str   # "user" | "assistant"
    content: str


class ChatRequest(BaseModel):
    message: str
    madhab: str = "hanafi"
    language: str = "fr"  # fr | ar | en
    history: list[ChatMessage] = []


class ChatResponse(BaseModel):
    answer: str
    sources: list[str] = []
    madhab: str
    language: str


# ── Devices / IoT ─────────────────────────────────────────────────────────────

class DeviceStatus(BaseModel):
    id: str
    name: str
    type: str    # esp32_adhan | light | plug | sensor
    online: bool
    ip: Optional[str] = None
    last_seen: Optional[str] = None
    state: dict = {}


class AdhanTriggerRequest(BaseModel):
    track: int = 2
    prayer_index: Optional[int] = None


class LedControlRequest(BaseModel):
    scenario: int
    brightness: Optional[int] = None


class AudioRequest(BaseModel):
    action: str   # play | stop | volume
    track: Optional[int] = None
    volume: Optional[int] = None


# ── User preferences ─────────────────────────────────────────────────────────

class UserPreferences(BaseModel):
    madhab: str = "hanafi"
    language: str = "fr"
    latitude: float = 48.8566
    longitude: float = 2.3522
    timezone_offset: int = 60
    calculation_method: str = "MWL"
    favorite_reciter_id: int = 7
    azkar_morning_enabled: bool = True
    azkar_evening_enabled: bool = True
    azkar_after_prayer_enabled: bool = True
