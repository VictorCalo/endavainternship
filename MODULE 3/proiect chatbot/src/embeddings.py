from openai import OpenAI

from src.config import OPENAI_EMBEDDING_MODEL


# Transforma datele unei carti intr-un text pentru embedding.
def build_book_document(book: dict) -> str:
    themes_text = ", ".join(book["themes"])

    return (
        f"Titlu: {book['title']}\n"
        f"Autor: {book['author']}\n"
        f"Teme: {themes_text}\n"
        f"Rezumat scurt: {book['short_summary']}"
    )


# Genereaza embeddings pentru mai multe texte.
def create_embeddings(client: OpenAI, texts: list[str]) -> list[list[float]]:
    response = client.embeddings.create(
        model=OPENAI_EMBEDDING_MODEL,
        input=texts,
    )
    return [item.embedding for item in response.data]


# Genereaza embeddingul pentru intrebarea utilizatorului.
def create_query_embedding(client: OpenAI, question: str) -> list[float]:
    return create_embeddings(client, [question])[0]
