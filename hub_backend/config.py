from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    hub_host: str = "0.0.0.0"
    hub_port: int = 8000
    mqtt_broker: str = "localhost"
    mqtt_port: int = 1883
    esp32_ip: str = "adhanbox.local"
    claude_api_key: str = ""
    database_url: str = "sqlite+aiosqlite:///./hub.db"

    class Config:
        env_file = ".env"


settings = Settings()
