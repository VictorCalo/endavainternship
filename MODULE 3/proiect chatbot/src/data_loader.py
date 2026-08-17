import json

from src.config import BOOKS_PATH


REQUIRED_FIELDS = ["title", "author", "themes", "short_summary", "full_summary"]


# Citeste cartile din fisierul JSON.
def load_books() -> list[dict]:
    with BOOKS_PATH.open("r", encoding="utf-8") as file:
        books = json.load(file)

    validate_books(books)
    return books


# Verifica daca datasetul are suficiente carti si campuri.
def validate_books(books: list[dict]) -> None:
    if len(books) < 10:
        raise ValueError("Dataset-ul trebuie sa contina minimum 10 carti.")

    for book in books:
        for field_name in REQUIRED_FIELDS:
            if field_name not in book:
                raise ValueError(f"Campul '{field_name}' lipseste dintr-o carte din dataset.")


# Normalizeaza titlul pentru comparatii mai usoare.
def normalize_title(title: str) -> str:
    return " ".join(title.lower().strip().split())


# Cauta o carte dupa titlul ei.
def find_book_by_title(title: str) -> dict | None:
    normalized_title = normalize_title(title)

    for book in load_books():
        if normalize_title(book["title"]) == normalized_title:
            return book

    return None
