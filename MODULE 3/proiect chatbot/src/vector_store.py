import chromadb
from chromadb.config import Settings

from src.config import CHROMA_DIR, COLLECTION_NAME
from src.embeddings import build_book_document


# Creeaza clientul pentru baza de date ChromaDB.
def get_chroma_client() -> chromadb.PersistentClient:
    CHROMA_DIR.mkdir(exist_ok=True)

    return chromadb.PersistentClient(
        path=str(CHROMA_DIR),
        settings=Settings(anonymized_telemetry=False),
    )


# Obtine colectia unde sunt salvate cartile.
def get_collection():
    client = get_chroma_client()
    return client.get_or_create_collection(name=COLLECTION_NAME)


# Creeaza un identificator unic pentru o carte.
def build_book_id(book: dict) -> str:
    return book["title"].lower().replace(" ", "_").replace("-", "_")


# Salveaza cartile si embeddingsurile in ChromaDB.
def upsert_books(books: list[dict], embeddings: list[list[float]]) -> None:
    collection = get_collection()

    ids = []
    documents = []
    metadatas = []

    for book in books:
        ids.append(build_book_id(book))
        documents.append(build_book_document(book))
        metadatas.append(
            {
                "title": book["title"],
                "author": book["author"],
                "themes": ", ".join(book["themes"]),
                "short_summary": book["short_summary"],
            }
        )

    collection.upsert(
        ids=ids,
        documents=documents,
        embeddings=embeddings,
        metadatas=metadatas,
    )


# Cauta cele mai apropiate carti pentru un embedding.
def search_books(query_embedding: list[float], top_k: int) -> list[dict]:
    collection = get_collection()

    if collection.count() == 0:
        return []

    results = collection.query(
        query_embeddings=[query_embedding],
        n_results=top_k,
    )

    books = []
    ids = results.get("ids", [[]])[0]
    documents = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]
    distances = results.get("distances", [[]])[0]

    for book_id, document, metadata, distance in zip(ids, documents, metadatas, distances):
        books.append(
            {
                "id": book_id,
                "document": document,
                "metadata": metadata,
                "distance": distance,
            }
        )

    return books


# Returneaza numarul de carti din ChromaDB.
def get_indexed_books_count() -> int:
    collection = get_collection()
    return collection.count()
