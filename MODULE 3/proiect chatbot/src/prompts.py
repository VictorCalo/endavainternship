DEVELOPER_PROMPT = """
You are a helpful book recommendation assistant.
Always answer in Romanian.
Use only the books you receive in the RAG context.
Do not invent books, authors, or summaries.
Choose the single best book for the user's request.
Before you give a final answer, call the tool get_summary_by_title with the exact title you selected.
Never produce a detailed summary from memory.
""".strip()


TITLE_FALLBACK_PROMPT = """
You help a book recommendation app recover the exact title selected from a RAG context.
Always answer in Romanian.
Return only the exact title of the single best recommendation.
Do not add explanations, punctuation, or extra text.
""".strip()


FINAL_ANSWER_PROMPT = """
You are a helpful book recommendation assistant.
Always answer in Romanian.
Use only the information provided by the application.
Do not invent books, authors, or summaries.
Write the final answer using this exact Markdown structure:
## Carte recomandata
2-3 sentences with the title and author.
## De ce se potriveste
2-3 sentences that explain why the recommendation matches the user's request.
## Rezumat detaliat
Present the detailed summary from the tool in a clear paragraph or short paragraphs.
""".strip()


# Construieste promptul cu intrebarea si cartile gasite.
def build_rag_prompt(question: str, matches: list[dict]) -> str:
    if not matches:
        return (
            "Intrebarea utilizatorului:\n"
            f"{question}\n\n"
            "Nu exista rezultate in vector store. Explica politicos acest lucru si cere o reformulare."
        )

    lines = [
        "Intrebarea utilizatorului:",
        question,
        "",
        "Context RAG cu cartile recuperate din ChromaDB:",
    ]

    for index, match in enumerate(matches, start=1):
        metadata = match["metadata"]
        lines.append(f"{index}. Titlu: {metadata['title']}")
        lines.append(f"   Autor: {metadata['author']}")
        lines.append(f"   Teme: {metadata['themes']}")
        lines.append(f"   Rezumat scurt: {metadata['short_summary']}")
        lines.append("")

    lines.append("Alege cea mai potrivita carte din contextul de mai sus.")
    lines.append("Dupa ce alegi titlul exact, apeleaza tool-ul get_summary_by_title cu titlul exact.")
    lines.append("Nu da raspunsul final inainte sa folosesti tool-ul.")

    return "\n".join(lines)


# Construieste promptul folosit pentru alegerea unui titlu de rezerva.
def build_title_fallback_prompt(question: str, matches: list[dict]) -> str:
    lines = [
        "Intrebarea utilizatorului:",
        question,
        "",
        "Alege exact un titlu din lista de mai jos si raspunde doar cu titlul:",
    ]

    for match in matches:
        metadata = match["metadata"]
        lines.append(f"- {metadata['title']}")

    return "\n".join(lines)


# Construieste promptul pentru raspunsul final.
def build_final_answer_prompt(question: str, book: dict | None, detailed_summary: str) -> str:
    if book is None:
        return (
            "Intrebarea utilizatorului:\n"
            f"{question}\n\n"
            "Nu am putut identifica o carte valida din dataset.\n"
            f"Rezultat tool: {detailed_summary}\n\n"
            "Explica politicos problema si cere utilizatorului sa reformuleze cererea."
        )

    return (
        "Intrebarea utilizatorului:\n"
        f"{question}\n\n"
        "Cartea recomandata:\n"
        f"Titlu: {book['title']}\n"
        f"Autor: {book['author']}\n"
        f"Teme: {', '.join(book['themes'])}\n"
        f"Rezumat scurt: {book['short_summary']}\n\n"
        "Rezumat complet obtinut prin tool local:\n"
        f"{detailed_summary}\n\n"
        "Construieste raspunsul final in romana."
    )
