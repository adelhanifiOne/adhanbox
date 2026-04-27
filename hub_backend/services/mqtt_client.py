"""
MQTT client async — pub/sub vers Mosquitto (Raspberry Pi 5)
"""
import asyncio
import json
import logging
from typing import Callable
from config import settings

logger = logging.getLogger(__name__)

# State partagé des devices
_device_states: dict = {}
_callbacks: list[Callable] = []

# Topics
TOPIC_ADHAN_TRIGGER  = "adhanbox/adhan/trigger"
TOPIC_AUDIO_PLAY     = "adhanbox/audio/play"
TOPIC_AUDIO_STOP     = "adhanbox/audio/stop"
TOPIC_AUDIO_VOLUME   = "adhanbox/audio/volume"
TOPIC_LED_SCENARIO   = "adhanbox/led/scenario"
TOPIC_LED_BRIGHTNESS = "adhanbox/led/brightness"
TOPIC_STATUS         = "adhanbox/status"
TOPIC_AUDIO_STATUS   = "adhanbox/audio/status"
TOPIC_PRAYER_FIRED   = "adhanbox/prayer/fired"


class MQTTClient:
    def __init__(self):
        self._client = None
        self._connected = False

    async def connect(self):
        try:
            import asyncio_mqtt as aiomqtt
            self._aiomqtt = aiomqtt
            logger.info(f"MQTT connecting to {settings.mqtt_broker}:{settings.mqtt_port}")
            # La connexion réelle se fait dans la task de background
            asyncio.create_task(self._listen_loop())
        except ImportError:
            logger.warning("asyncio-mqtt not installed, MQTT disabled")
        except Exception as e:
            logger.error(f"MQTT connect error: {e}")

    async def _listen_loop(self):
        import asyncio_mqtt as aiomqtt
        while True:
            try:
                async with aiomqtt.Client(settings.mqtt_broker, settings.mqtt_port) as client:
                    self._connected = True
                    logger.info("MQTT connected")
                    await client.subscribe(TOPIC_STATUS)
                    await client.subscribe(TOPIC_AUDIO_STATUS)
                    await client.subscribe(TOPIC_PRAYER_FIRED)
                    async for message in client.messages:
                        await self._on_message(str(message.topic), message.payload.decode())
            except Exception as e:
                self._connected = False
                logger.warning(f"MQTT disconnected: {e} — retry in 5s")
                await asyncio.sleep(5)

    async def _on_message(self, topic: str, payload: str):
        logger.debug(f"MQTT ← {topic}: {payload}")
        try:
            data = json.loads(payload)
        except Exception:
            data = payload

        if topic == TOPIC_STATUS:
            _device_states["adhanbox"] = data
        elif topic == TOPIC_AUDIO_STATUS:
            if "adhanbox" not in _device_states:
                _device_states["adhanbox"] = {}
            _device_states["adhanbox"]["audio"] = data
        elif topic == TOPIC_PRAYER_FIRED:
            logger.info(f"Prayer fired: {data}")

    async def _publish(self, topic: str, payload: str):
        if not self._connected:
            logger.warning(f"MQTT not connected, cannot publish to {topic}")
            return
        import asyncio_mqtt as aiomqtt
        try:
            async with aiomqtt.Client(settings.mqtt_broker, settings.mqtt_port) as client:
                await client.publish(topic, payload)
        except Exception as e:
            logger.error(f"MQTT publish error: {e}")

    async def trigger_adhan(self, track: int = 2):
        await self._publish(TOPIC_ADHAN_TRIGGER, str(track))

    async def play_track(self, track: int):
        await self._publish(TOPIC_AUDIO_PLAY, str(track))

    async def stop_audio(self):
        await self._publish(TOPIC_AUDIO_STOP, "stop")

    async def set_volume(self, volume: int):
        await self._publish(TOPIC_AUDIO_VOLUME, str(volume))

    async def set_led_scenario(self, scenario: int):
        await self._publish(TOPIC_LED_SCENARIO, str(scenario))

    async def set_led_brightness(self, brightness: int):
        await self._publish(TOPIC_LED_BRIGHTNESS, str(brightness))

    def get_device_state(self, device_id: str) -> dict:
        return _device_states.get(device_id, {})

    def is_connected(self) -> bool:
        return self._connected


mqtt = MQTTClient()
