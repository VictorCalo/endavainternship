import json

from src.data_loader import find_book_by_title


SUMMARY_NOT_FOUND_MESSAGE = "Nu am gasit un rezumat complet pentru acest titlu in datasetul local."


TOOLS = [
    {
        "type": "function",
        "name": "get_summary_by_title",
        "description": (
            "Returneaza rezumatul complet pentru un titlu exact din datasetul local de carti. "
            "Apeleaza acest tool dupa ce ai ales cartea recomandata."
        ),
        "parameters": {
            "type": "object",
            "properties": {
                "title": {
                    "type": "string",
                    "description": "Titlul exact al cartii recomandate.",
                }
            },
            "required": ["title"],
            "additionalProperties": False,
        },
        "strict": True,
    }
]


# Cauta si returneaza rezumatul complet al unei carti.
def get_summary_by_title(title: str) -> str:
    book = find_book_by_title(title)

    if book is None:
        return SUMMARY_NOT_FOUND_MESSAGE

    return book["full_summary"]


# Extrage titlul din argumentele apelului de tool.
def extract_title_from_tool_call(tool_call) -> str | None:
    arguments = json.loads(tool_call.arguments)
    title = arguments.get("title", "").strip()

    if not title:
        return None

    return title


# Pregateste rezultatul care este trimis inapoi modelului.
def build_tool_output(tool_call) -> dict:
    title = extract_title_from_tool_call(tool_call)

    if title is None:
        title = ""

    summary = get_summary_by_title(title)

    return {
        "type": "function_call_output",
        "call_id": tool_call.call_id,
        "output": summary,
    }
