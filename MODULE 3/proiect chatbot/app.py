import streamlit as st

from src.chatbot import ask_book_question
from src.config import OPENAI_CHAT_MODEL, OPENAI_EMBEDDING_MODEL
from src.data_loader import load_books
from src.models import MessagePayload
from src.ui_text import (
    APP_DESCRIPTION,
    APP_TITLE,
    CHAT_PLACEHOLDER,
    RAG_EXPANDER_LABEL,
    SEARCH_SPINNER,
    STATUS_DESCRIPTION,
    STATUS_HEADER,
    SUGGESTIONS,
    SUGGESTIONS_HEADER,
)
from src.vector_store import get_indexed_books_count


st.set_page_config(page_title=APP_TITLE, page_icon="📚", layout="centered")

st.title(APP_TITLE)
st.write(APP_DESCRIPTION)

books = load_books()
indexed_books_count = get_indexed_books_count()

if "messages" not in st.session_state:
    st.session_state.messages = []

if "pending_question" not in st.session_state:
    st.session_state.pending_question = None

with st.sidebar:
    st.subheader(STATUS_HEADER)
    st.write(f"Carti in dataset: {len(books)}")
    st.write(f"Carti indexate in ChromaDB: {indexed_books_count}")
    st.write(f"Model chat: {OPENAI_CHAT_MODEL}")
    st.write(f"Model embeddings: {OPENAI_EMBEDDING_MODEL}")
    st.write(STATUS_DESCRIPTION)

with st.expander(SUGGESTIONS_HEADER):
    for index, suggestion in enumerate(SUGGESTIONS):
        if st.button(suggestion, key=f"suggestion_{index}", use_container_width=True):
            st.session_state.pending_question = suggestion
            st.rerun()


# Afiseaza cartile gasite prin cautarea semantica.
def render_rag_matches(matches: list[dict]) -> None:
    with st.expander(RAG_EXPANDER_LABEL):
        for match in matches:
            metadata = match["metadata"]
            st.markdown(f"**{metadata['title']}** de {metadata['author']}")
            st.write(f"Teme: {metadata['themes']}")
            st.write(metadata["short_summary"])


for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

        if message["role"] == "assistant" and message.get("matches"):
            render_rag_matches(message["matches"])

if st.session_state.pending_question is not None:
    st.session_state.chat_input = st.session_state.pending_question
    st.session_state.pending_question = None

question = st.chat_input(CHAT_PLACEHOLDER, key="chat_input")

if question:
    st.session_state.messages.append({"role": "user", "content": question})

    with st.chat_message("user"):
        st.markdown(question)

    with st.chat_message("assistant"):
        with st.spinner(SEARCH_SPINNER):
            result = ask_book_question(question)

        st.markdown(result.answer)

        if result.matches:
            render_rag_matches(result.matches)

    st.session_state.messages.append(
        MessagePayload(
            role="assistant",
            content=result.answer,
            matches=result.matches,
            recommended_title=result.recommended_title,
            tool_summary_found=result.tool_summary_found,
            tool_call_source=result.tool_call_source,
        ).__dict__
    )
