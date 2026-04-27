from fastapi import APIRouter, HTTPException
from models.schemas import DeviceStatus, AdhanTriggerRequest, LedControlRequest, AudioRequest
from services.mqtt_client import mqtt

router = APIRouter(prefix="/devices", tags=["Devices IoT"])


@router.get("/", response_model=list[DeviceStatus])
async def list_devices():
    """Liste tous les devices connus."""
    adhanbox_state = mqtt.get_device_state("adhanbox")
    return [
        DeviceStatus(
            id="adhanbox",
            name="AdhanBox",
            type="esp32_adhan",
            online=bool(adhanbox_state),
            ip=adhanbox_state.get("ip"),
            last_seen=adhanbox_state.get("last_seen"),
            state=adhanbox_state,
        )
    ]


@router.post("/adhanbox/adhan")
async def trigger_adhan(req: AdhanTriggerRequest):
    """Déclenche l'adhan sur l'ESP32 via MQTT."""
    await mqtt.trigger_adhan(req.track)
    return {"ok": True, "track": req.track}


@router.post("/adhanbox/led")
async def control_led(req: LedControlRequest):
    """Change le scénario LED de l'AdhanBox."""
    await mqtt.set_led_scenario(req.scenario)
    if req.brightness is not None:
        await mqtt.set_led_brightness(req.brightness)
    return {"ok": True}


@router.post("/adhanbox/audio")
async def control_audio(req: AudioRequest):
    """Contrôle audio de l'AdhanBox (play/stop/volume)."""
    if req.action == "play" and req.track:
        await mqtt.play_track(req.track)
    elif req.action == "stop":
        await mqtt.stop_audio()
    elif req.action == "volume" and req.volume is not None:
        v = max(0, min(30, req.volume))
        await mqtt.set_volume(v)
    else:
        raise HTTPException(400, "Action invalide")
    return {"ok": True}


@router.get("/adhanbox/status")
async def adhanbox_status():
    state = mqtt.get_device_state("adhanbox")
    return {
        "online": bool(state),
        "mqtt_connected": mqtt.is_connected(),
        "state": state,
    }
