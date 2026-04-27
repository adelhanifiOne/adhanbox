"""
Prayer times calculation — port of PrayTimes algorithm (praytimes.org)
Supports: MWL, ISNA, Egypt, Makkah, Karachi, Tehran, Jafari
"""
import math
from datetime import datetime, timezone, timedelta
from models.schemas import PrayerTime, PrayerTimesResponse


# ── Method parameters ─────────────────────────────────────────────────────────

METHODS = {
    "MWL":     {"fajr": 18.0, "isha": 17.0},
    "ISNA":    {"fajr": 15.0, "isha": 15.0},
    "Egypt":   {"fajr": 19.5, "isha": 17.5},
    "Makkah":  {"fajr": 18.5, "isha": "90min"},
    "Karachi": {"fajr": 18.0, "isha": 18.0},
    "Tehran":  {"fajr": 17.7, "isha": 14.0},
    "Jafari":  {"fajr": 16.0, "isha": 14.0},
}

PRAYER_NAMES = {
    "Fajr":    "الفجر",
    "Sunrise": "الشروق",
    "Dhuhr":   "الظهر",
    "Asr":     "العصر",
    "Maghrib": "المغرب",
    "Isha":    "العشاء",
}


# ── Math helpers ──────────────────────────────────────────────────────────────

def _dtr(d): return d * math.pi / 180
def _rtd(r): return r * 180 / math.pi
def _sin(d): return math.sin(_dtr(d))
def _cos(d): return math.cos(_dtr(d))
def _tan(d): return math.tan(_dtr(d))
def _asin(x): return _rtd(math.asin(x))
def _acos(x): return _rtd(math.acos(x))
def _atan2(y, x): return _rtd(math.atan2(y, x))

def _fix_hour(h):
    h = h - 24 * math.floor(h / 24)
    return h + 24 if h < 0 else h

def _julian_day(year, month, day):
    if month <= 2:
        year -= 1
        month += 12
    A = math.floor(year / 100)
    B = 2 - A + math.floor(A / 4)
    return math.floor(365.25 * (year + 4716)) + math.floor(30.6001 * (month + 1)) + day + B - 1524.5

def _sun_position(jd):
    D = jd - 2451545.0
    g = _fix_hour(357.529 + 0.98560028 * D)
    q = _fix_hour(280.459 + 0.98564736 * D)
    L = _fix_hour(q + 1.915 * _sin(g) + 0.020 * _sin(2 * g))
    e = 23.439 - 0.00000036 * D
    RA = _atan2(_cos(e) * _sin(L), _cos(L)) / 15
    dec = _asin(_sin(e) * _sin(L))
    EqT = q / 15 - _fix_hour(RA)
    return dec, EqT

def _prayer_time_for_angle(angle, jd, lat, direction="ccw"):
    dec, _ = _sun_position(jd)
    t = _acos((-_sin(angle) - _sin(dec) * _sin(lat)) / (_cos(dec) * _cos(lat))) / 15
    return t if direction == "ccw" else -t

def _asr_time(factor, jd, lat):
    dec, _ = _sun_position(jd)
    angle = -_rtd(math.atan(1.0 / (factor + math.tan(abs(_dtr(lat - dec))))))
    return _prayer_time_for_angle(angle, jd, lat)


# ── Main calculation ──────────────────────────────────────────────────────────

def calculate_prayer_times(
    latitude: float,
    longitude: float,
    date: datetime,
    method: str = "MWL",
    madhab: str = "hanafi",
    timezone_offset_min: int = 0,
) -> PrayerTimesResponse:
    year, month, day = date.year, date.month, date.day
    jd = _julian_day(year, month, day)
    lat = latitude
    tz = timezone_offset_min / 60.0

    _, EqT = _sun_position(jd)
    transit = 12 + tz - longitude / 15 - EqT

    params = METHODS.get(method, METHODS["MWL"])
    fajr_angle = params["fajr"]
    isha_param = params["isha"]

    fajr_t  = transit - _prayer_time_for_angle(fajr_angle, jd, lat)
    sunrise = transit - _prayer_time_for_angle(0.833, jd, lat)
    dhuhr   = transit
    asr_t   = transit + _asr_time(1 if madhab == "hanafi" else 0, jd, lat)
    sunset  = transit + _prayer_time_for_angle(0.833, jd, lat)
    maghrib = sunset

    if isinstance(isha_param, str) and "min" in isha_param:
        isha_t = sunset + float(isha_param.replace("min", "")) / 60
    else:
        isha_t = transit + _prayer_time_for_angle(float(isha_param), jd, lat, "cw")

    def to_hhmm(h):
        h = _fix_hour(h)
        hh = int(h)
        mm = int(round((h - hh) * 60))
        if mm == 60:
            hh += 1; mm = 0
        return f"{hh:02d}:{mm:02d}"

    def to_unix(h):
        h = _fix_hour(h)
        hh = int(h)
        mm = int(round((h - hh) * 60))
        dt = datetime(year, month, day, hh % 24, mm % 60,
                      tzinfo=timezone(timedelta(minutes=timezone_offset_min)))
        return int(dt.timestamp())

    now_unix = int(datetime.now(timezone.utc).timestamp())

    raw = [
        ("Fajr",    "الفجر",    fajr_t),
        ("Sunrise", "الشروق",   sunrise),
        ("Dhuhr",   "الظهر",    dhuhr),
        ("Asr",     "العصر",    asr_t),
        ("Maghrib", "المغرب",   maghrib),
        ("Isha",    "العشاء",   isha_t),
    ]

    prayers: list[PrayerTime] = []
    next_found = False
    for name, name_ar, t in raw:
        ts = to_unix(t)
        is_next = not next_found and ts > now_unix
        if is_next:
            next_found = True
        prayers.append(PrayerTime(
            name=name,
            name_ar=name_ar,
            time=to_hhmm(t),
            timestamp=ts,
            is_next=is_next,
            passed=ts <= now_unix,
        ))

    return PrayerTimesResponse(
        date=date.strftime("%Y-%m-%d"),
        location=f"{latitude:.4f},{longitude:.4f}",
        method=method,
        madhab=madhab,
        prayers=prayers,
    )
