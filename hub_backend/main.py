from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging

from database import init_db
from services.mqtt_client import mqtt
from services.rag_engine import init_rag
from routers import prayers, azkar, assistant, quran, devices

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🕌 AdhanBox Hub starting...")
    await init_db()
    await mqtt.connect()
    await init_rag()
    logger.info("✅ Hub ready")
    yield
    logger.info("Hub shutting down")


app = FastAPI(
    title="AdhanBox Hub API",
    description="Islamic Smart Home Assistant — backend RPi5",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(prayers.router)
app.include_router(azkar.router)
app.include_router(assistant.router)
app.include_router(quran.router)
app.include_router(devices.router)


@app.get("/", tags=["Status"])
async def root():
    return {
        "name": "AdhanBox Hub",
        "version": "1.0.0",
        "status": "running",
        "mqtt": mqtt.is_connected(),
    }


@app.get("/health", tags=["Status"])
async def health():
    return {"ok": True}
