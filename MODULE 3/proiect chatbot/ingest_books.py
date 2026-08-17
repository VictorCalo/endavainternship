from openai import OpenAI

from src.config import OPENAI_API_KEY, validate_environment
from src.data_loader import load_books
from src.embeddings import build_book_document, create_embeddings
from src.vector_store import upsert_books


# Incarca cartile si embeddingsurile in ChromaDB.
def main() -> None:
    validate_environment()

    books = load_books()
    documents = [build_book_document(book) for book in books]

    client = OpenAI(api_key=OPENAI_API_KEY)
    embeddings = create_embeddings(client, documents)

    upsert_books(books, embeddings)

    print(f"Au fost incarcate {len(books)} carti in ChromaDB.")


if __name__ == "__main__":
    main()
