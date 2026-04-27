from fastapi import APIRouter
from models.schemas import ChatRequest, ChatResponse
from services.rag_engine import chat

router = APIRouter(prefix="/assistant", tags=["Assistant islamique"])


@router.post("/chat", response_model=ChatResponse)
async def assistant_chat(request: ChatRequest):
    """
    Question islamique → réponse sourcée (RAG + LLM).
    Phase 1 : réponses mockées. Phase 2 : Ollama + ChromaDB.
    """
    return await chat(request)
