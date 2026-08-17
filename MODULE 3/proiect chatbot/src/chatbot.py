from openai import OpenAI

from src.config import OPENAI_API_KEY, OPENAI_CHAT_MODEL, TOP_K_RESULTS, validate_environment
from src.data_loader import find_book_by_title, normalize_title
from src.embeddings import create_query_embedding
from src.models import BookQuestionResult, ToolResolution
from src.prompts import (
    DEVELOPER_PROMPT,
    FINAL_ANSWER_PROMPT,
    TITLE_FALLBACK_PROMPT,
    build_final_answer_prompt,
    build_rag_prompt,
    build_title_fallback_prompt,
)
from src.tools import (
    SUMMARY_NOT_FOUND_MESSAGE,
    TOOLS,
    build_tool_output,
    extract_title_from_tool_call,
    get_summary_by_title,
)
from src.vector_store import get_indexed_books_count, search_books


# Creeaza clientul pentru conectarea la OpenAI.
def create_openai_client() -> OpenAI:
    validate_environment()
    return OpenAI(api_key=OPENAI_API_KEY)


# Extrage apelurile de tool din raspunsul modelului.
def extract_tool_calls(response) -> list:
    tool_calls = []

    for item in response.output:
        if getattr(item, "type", "") == "function_call":
            tool_calls.append(item)

    return tool_calls


# Cauta cartile relevante pentru intrebarea utilizatorului.
def retrieve_relevant_books(client: OpenAI, question: str) -> list[dict]:
    query_embedding = create_query_embedding(client, question)
    return search_books(query_embedding, TOP_K_RESULTS)


# Cere modelului sa aleaga o carte pe baza rezultatelor RAG.
def request_recommendation_from_model(client: OpenAI, question: str, matches: list[dict]):
    prompt = build_rag_prompt(question, matches)

    return client.responses.create(
        model=OPENAI_CHAT_MODEL,
        instructions=DEVELOPER_PROMPT,
        input=[{"role": "user", "content": prompt}],
        tools=TOOLS,
    )


# Proceseaza apelurile de tool facute de model.
def resolve_tool_phase(client: OpenAI, response) -> ToolResolution:
    current_response = response
    resolution = ToolResolution(response=current_response)

    for _ in range(3):
        tool_calls = extract_tool_calls(current_response)

        if not tool_calls:
            break

        resolution.tool_requested_by_model = True

        for tool_call in tool_calls:
            title = extract_title_from_tool_call(tool_call)
            if title:
                resolution.recommended_title = title

        tool_outputs = [build_tool_output(tool_call) for tool_call in tool_calls]
        if tool_outputs:
            resolution.detailed_summary = tool_outputs[-1]["output"]

        current_response = client.responses.create(
            model=OPENAI_CHAT_MODEL,
            instructions=DEVELOPER_PROMPT,
            previous_response_id=current_response.id,
            input=tool_outputs,
            tools=TOOLS,
        )

    resolution.response = current_response
    return resolution


# Ia titlurile cartilor gasite prin cautarea semantica.
def get_candidate_titles(matches: list[dict]) -> list[str]:
    return [match["metadata"]["title"] for match in matches]


# Incearca sa gaseasca un titlu valid in textul primit.
def extract_title_from_text(text: str, candidate_titles: list[str]) -> str | None:
    normalized_text = normalize_title(text.replace('"', " ").replace("'", " "))

    for title in candidate_titles:
        if normalize_title(title) == normalized_text:
            return title

    for title in candidate_titles:
        if normalize_title(title) in normalized_text:
            return title

    return None


# Alege un titlu de rezerva daca modelul nu a apelat tool-ul.
def choose_fallback_title(client: OpenAI, question: str, matches: list[dict], initial_text: str) -> str | None:
    candidate_titles = get_candidate_titles(matches)

    title_from_initial_text = extract_title_from_text(initial_text, candidate_titles)
    if title_from_initial_text:
        return title_from_initial_text

    response = client.responses.create(
        model=OPENAI_CHAT_MODEL,
        instructions=TITLE_FALLBACK_PROMPT,
        input=[{"role": "user", "content": build_title_fallback_prompt(question, matches)}],
    )

    title_from_fallback = extract_title_from_text(response.output_text, candidate_titles)
    if title_from_fallback:
        return title_from_fallback

    if candidate_titles:
        return candidate_titles[0]

    return None


# Se asigura ca avem un titlu recomandat valid.
def ensure_recommended_title(
    client: OpenAI,
    question: str,
    matches: list[dict],
    tool_resolution: ToolResolution,
) -> str | None:
    if tool_resolution.recommended_title is not None:
        return tool_resolution.recommended_title

    return choose_fallback_title(client, question, matches, tool_resolution.response.output_text)


# Obtine rezumatul complet folosind tool-ul local.
def ensure_detailed_summary(
    recommended_title: str | None,
    tool_resolution: ToolResolution,
) -> tuple[str, str]:
    if tool_resolution.detailed_summary is not None:
        source = "model_function_call" if tool_resolution.tool_requested_by_model else "local_fallback"
        return tool_resolution.detailed_summary, source

    if recommended_title is not None:
        return get_summary_by_title(recommended_title), "local_fallback"

    return SUMMARY_NOT_FOUND_MESSAGE, "not_called"


# Construieste raspunsul final pentru utilizator.
def build_final_answer(
    client: OpenAI,
    question: str,
    recommended_title: str | None,
    detailed_summary: str,
) -> str:
    selected_book = find_book_by_title(recommended_title) if recommended_title else None

    response = client.responses.create(
        model=OPENAI_CHAT_MODEL,
        instructions=FINAL_ANSWER_PROMPT,
        input=[
            {
                "role": "user",
                "content": build_final_answer_prompt(question, selected_book, detailed_summary),
            }
        ],
    )

    answer = response.output_text.strip()

    if answer:
        return answer

    if selected_book is None:
        return "Nu am reusit sa identific o carte valida din dataset. Incearca o intrebare mai specifica."

    return (
        f"Iti recomand cartea **{selected_book['title']}** de {selected_book['author']}.\n\n"
        f"Se potriveste pentru ca abordeaza teme precum {', '.join(selected_book['themes'])}.\n\n"
        f"Rezumat detaliat:\n{detailed_summary}"
    )


# Creeaza mesajul afisat cand baza de date este goala.
def build_empty_index_result() -> BookQuestionResult:
    return BookQuestionResult(
        answer=(
            "Baza vectoriala este goala. Ruleaza mai intai scriptul ingest_books.py "
            "pentru a incarca cartile in ChromaDB."
        )
    )


# Coordoneaza tot fluxul pentru o intrebare despre carti.
def ask_book_question(question: str) -> BookQuestionResult:
    client = create_openai_client()

    if get_indexed_books_count() == 0:
        return build_empty_index_result()

    matches = retrieve_relevant_books(client, question)
    first_response = request_recommendation_from_model(client, question, matches)
    tool_resolution = resolve_tool_phase(client, first_response)

    # Accepta raspunsul final doar dupa selectarea titlului si folosirea tool-ului.
    recommended_title = ensure_recommended_title(client, question, matches, tool_resolution)
    detailed_summary, tool_call_source = ensure_detailed_summary(recommended_title, tool_resolution)
    tool_summary_found = detailed_summary != SUMMARY_NOT_FOUND_MESSAGE
    answer = build_final_answer(client, question, recommended_title, detailed_summary)

    return BookQuestionResult(
        answer=answer,
        matches=matches,
        recommended_title=recommended_title,
        tool_called=recommended_title is not None,
        tool_summary_found=tool_summary_found,
        tool_call_source=tool_call_source,
    )
