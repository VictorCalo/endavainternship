# Smart Librarian

Smart Librarian este un chatbot pentru recomandarea de cărți, construit în Python și bazat pe căutare semantică și OpenAI. Aplicația primește o întrebare în limbaj natural, găsește cele mai potrivite cărți din datasetul local, recomandă una și oferă un rezumat complet folosind un tool local.

## Ce include proiectul

- căutare semantică folosind embeddings OpenAI
- stocare vectorială locală în ChromaDB
- recomandare de carte generată de modelul de chat
- apel de tool local pentru rezumatul complet al cărții
- interfață web în Streamlit

## Stack tehnologic

- Python
- OpenAI API
- ChromaDB
- Streamlit
- Python dotenv

## Structura proiectului

```text
proiect chatbot/
├─ .env
├─ .gitignore
├─ .venv/
├─ app.py
├─ ingest_books.py
├─ requirements.txt
├─ README.md
├─ chroma_db/
│  ├─ chroma.sqlite3
│  └─ ...
├─ data/
│  └─ books.json
├─ src/
│  ├─ __init__.py
│  ├─ chatbot.py
│  ├─ config.py
│  ├─ data_loader.py
│  ├─ embeddings.py
│  ├─ models.py
│  ├─ prompts.py
│  ├─ tools.py
│  ├─ ui_text.py
│  └─ vector_store.py
└─ .venv/
```

## Cerințe preliminare

Asigură-te că ai instalat Python 3.10+ și că poți crea un mediu virtual.

## Configurare

1. Creează mediul virtual:

```powershell
python -m venv .venv
```

2. Activează mediul virtual:

```powershell
.\.venv\Scripts\Activate.ps1
```

3. Instalează dependențele:

```powershell
python -m pip install --upgrade pip
pip install -r requirements.txt
```

4. Creează fișierul `.env` în rădăcina proiectului și adaugă cheia API OpenAI:

```env
OPENAI_API_KEY=your_openai_api_key_here
OPENAI_CHAT_MODEL=gpt-4.1-mini
OPENAI_EMBEDDING_MODEL=text-embedding-3-small
TOP_K_RESULTS=3
```

> Fișierul `.env` este folosit pentru variabilele de configurare și nu trebuie trimis în Git.

## Pornirea aplicației

### 1. Încarcă cărțile în baza vectorială

```powershell
python ingest_books.py
```

Acest pas citește datele din `data/books.json`, generează embedding-uri și le stochează în directorul `chroma_db/`.

### 2. Rulează aplicația Streamlit

```powershell
.\.venv\Scripts\streamlit.exe run app.py
```

## Cum funcționează fluxul

1. utilizatorul scrie o întrebare
2. aplicația caută cărțile relevante folosind embedding-uri și ChromaDB
3. modelul recomandă o carte potrivită
4. se apelează tool-ul `get_summary_by_title()` pentru rezumatul complet
5. răspunsul final este afișat în UI, împreună cu cărțile candidate din căutarea semantică

## Exemple de întrebări

- Vreau o carte despre libertate și control social.
- Ce îmi recomanzi dacă iubesc poveștile fantastice?
- Aș vrea o carte despre război și supraviețuire.
- Recomandă-mi o carte cu teme de iubire și diferențe sociale.

## Observații

- datasetul principal este local în `data/books.json`
- app.py este punctul de intrare al interfeței web
- logica principală din spatele aplicației se află în directorul `src/`
- UI-ul este format din chat, sidebar și sugestii de întrebări

## Important

Pentru a rula corect proiectul, trebuie să existe un `.env` valid și să fie executat primul pas de ingestie pentru a genera indexul ChromaDB.
