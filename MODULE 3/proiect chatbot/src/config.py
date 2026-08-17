import os
from pathlib import Path

from dotenv import load_dotenv


BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
BOOKS_PATH = DATA_DIR / "books.json"
CHROMA_DIR = BASE_DIR / "chroma_db"

load_dotenv(BASE_DIR / ".env")

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_CHAT_MODEL = os.getenv("OPENAI_CHAT_MODEL", "gpt-4.1-mini")
OPENAI_EMBEDDING_MODEL = os.getenv("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
TOP_K_RESULTS = int(os.getenv("TOP_K_RESULTS", "3"))
COLLECTION_NAME = "smart_librarian_books"


# Verifica daca exista cheia necesara pentru OpenAI.
def validate_environment() -> None:
    if not OPENAI_API_KEY:
        raise RuntimeError(
            "Lipseste cheia OPENAI_API_KEY. Adauga cheia in fisierul .env inainte sa rulezi proiectul."
        )
