"""
RAG Engine — LLM + ChromaDB knowledge base islamique
Phase 2 : stub qui retourne des réponses mock jusqu'à installation Ollama/ChromaDB
"""
import logging
from models.schemas import ChatRequest, ChatResponse

logger = logging.getLogger(__name__)

_rag_ready = False


async def init_rag():
    """Initialise ChromaDB + Ollama. Appelé au démarrage si dispo."""
    global _rag_ready
    try:
        import chromadb  # noqa
        logger.info("ChromaDB available")
        _rag_ready = True
    except ImportError:
        logger.info("ChromaDB not installed — RAG in stub mode (Phase 2)")


async def chat(request: ChatRequest) -> ChatResponse:
    """Répond à une question islamique via RAG + LLM."""
    if not _rag_ready:
        return _stub_response(request)
    # TODO Phase 2 : pipeline LangChain → ChromaDB → Ollama
    return _stub_response(request)


def _stub_response(request: ChatRequest) -> ChatResponse:
    msg = request.message.lower()
    lang = request.language

    if any(w in msg for w in ["fajr", "salat", "prière", "prayer", "salah"]):
        answer = {
            "fr": "La prière du Fajr est obligatoire et doit être accomplie à l'aube. Elle comprend 2 rak'at.",
            "ar": "صلاة الفجر فريضة تؤدى عند الفجر، وهي ركعتان.",
            "en": "Fajr prayer is obligatory and performed at dawn. It consists of 2 rak'at.",
        }.get(lang, "Fajr prayer is 2 rak'at, performed at dawn.")
        sources = ["Sahih Bukhari 347", "Quran 17:78"]
    elif any(w in msg for w in ["zakat", "zakât"]):
        answer = {
            "fr": "La Zakat est le 3ème pilier de l'Islam. Elle est due sur les biens atteignant le nissab après une année lunaire.",
            "ar": "الزكاة ركن من أركان الإسلام، تجب على من بلغ ماله النصاب بعد حول.",
            "en": "Zakat is the 3rd pillar of Islam, due on wealth reaching the nisab after one lunar year.",
        }.get(lang, "Zakat is the 3rd pillar of Islam.")
        sources = ["Quran 2:177", "Sahih Muslim 979"]
    else:
        answer = {
            "fr": f"⚠️ Le moteur RAG islamique est en cours d'installation (Phase 2). Question reçue : « {request.message} »",
            "ar": f"⚠️ محرك الذكاء الاصطناعي الإسلامي قيد التثبيت.",
            "en": f"⚠️ Islamic RAG engine is being set up (Phase 2). Question: « {request.message} »",
        }.get(lang, request.message)
        sources = []

    return ChatResponse(
        answer=answer,
        sources=sources,
        madhab=request.madhab,
        language=lang,
    )
