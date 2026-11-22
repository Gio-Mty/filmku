"""REST API filmku: serial domain publik dari Internet Archive dan info film dari TMDB.

- GET /api/catalog            daftar serial (API pencarian Archive; deskripsi HTML dibersihkan)
- GET /api/episodes?slug=...  episode satu serial, di-scrape dari HTML halaman detail item
- GET /api/subtitle?slug=...&file=...  file subtitle Archive diteruskan dengan header CORS
- GET /api/tmdb/popular, /api/tmdb/search?q=...  info film TMDB (tanpa video)
- GET /api/tmdb/movie/{id}    detail TMDB + pemain, trailer YouTube, dan layanan streaming
                              resmi di Indonesia (butuh TMDB_API_KEY di backend/.env)

Halaman pencarian archive.org dirender JavaScript, jadi katalog memakai API pencariannya.
Daftar episode ada di HTML halaman detail: atribut `playlist` pada elemen <play-av>.

Jalankan dari folder ini:
    .venv\\Scripts\\python -m uvicorn main:app --port 8000 --reload
"""

from __future__ import annotations

import asyncio
import base64
import json
import os
import re
import secrets
import time
import warnings
from collections.abc import Callable
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Any, NamedTuple
from urllib.parse import quote, unquote, urljoin, urlsplit

import httpx
from bs4 import BeautifulSoup, MarkupResemblesLocatorWarning, SoupStrainer
from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel

try:
    import psycopg2
except ImportError:
    psycopg2 = None


def normalize_db_url(url: str) -> str:
    """Normalisasi format URL PostgreSQL untuk Supabase / cloud database."""
    url = url.strip().strip("\"'")
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://") :]
    if "@" in url and "://" in url:
        scheme, rest = url.split("://", 1)
        auth, host_part = rest.split("@", 1)
        if ":" in auth:
            user, pwd = auth.split(":", 1)
            pwd = pwd.replace("#", "%23")
            url = f"{scheme}://{user}:{pwd}@{host_part}"
    if "supabase" in url and "sslmode" not in url:
        sep = "&" if "?" in url else "?"
        url = f"{url}{sep}sslmode=require"
    return url


DEFAULT_TMDB_API_KEY = "01dc9c33c0d3409a40496ff8ff5bdb35"
DEFAULT_DATABASE_URL = "postgresql://postgres.mjywpvwfoiymdvfjvsig:%23Moty33Giovanny@aws-1-ap-southeast-1.pooler.supabase.com:5432/postgres"


ARCHIVE = "https://archive.org"
TMDB = "https://api.themoviedb.org/3"
TMDB_IMAGE = "https://image.tmdb.org/t/p"
# Detail film TMDB: negara untuk daftar layanan streaming resmi, urutan jenis layanan,
# dan bahasa trailer yang diutamakan (berurutan).
WATCH_REGION = "ID"
WATCH_KINDS = ("flatrate", "free", "ads", "rent", "buy")
TRAILER_LANGUAGES = ("id", "en")
MAX_CAST = 20


def _load_dotenv() -> None:
    """Muat backend/.env (KEY=VALUE per baris) tanpa dependensi tambahan."""
    for p in [
        Path(__file__).with_name(".env"),
        Path(__file__).resolve().parent.parent / "backend" / ".env",
        Path(__file__).resolve().parent.parent / ".env",
    ]:
        if p.is_file():
            for line in p.read_text(encoding="utf-8").splitlines():
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    key, _, value = line.partition("=")
                    os.environ.setdefault(key.strip(), value.strip().strip("\"'"))
            break


_load_dotenv()
PAGE_SIZE = 20
MAX_CONCURRENT_REQUESTS = 5

# Lisensi di Archive diisi sendiri oleh pengunggah (ada sitkom tahun 2006 yang diberi
# label domain publik), jadi katalog memakai tiga penyaring sekaligus:
#   1. koleksi yang dikurasi untuk konten domain publik, bukan Community Video;
#   2. label lisensi domain publik;
#   3. tahun <= 1963: hak cipta karya AS sesudahnya diperpanjang otomatis.
# Ini heuristik, bukan pemeriksaan hukum.
CATALOG_QUERY = (
    "mediatype:(movies) AND collection:(classic_tv OR feature_films)"
    " AND licenseurl:(*publicdomain*) AND year:[1900 TO 1963]"
    " AND title:(episodes OR episode OR serial OR chapters OR chapter OR season)"
    # Produksi BBC: hak cipta AS-nya dipulihkan (URAA) walau berlabel domain publik.
    " AND NOT title:(quatermass)"
)
SEARCH_FIELDS = ["identifier", "title", "year", "description", "downloads"]
SLUG_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$"
SUBTITLE_MAX_BYTES = 5_000_000

# Deskripsi Archive kadang hanya berisi URL; peringatan bs4 untuk itu tidak berguna di sini.
warnings.filterwarnings("ignore", category=MarkupResemblesLocatorWarning)


# --- Model respons -----------------------------------------------------------


class Series(BaseModel):
    slug: str
    title: str
    year: int | None
    description: str
    poster: str
    downloads: int


class CatalogPage(BaseModel):
    page: int
    total: int
    results: list[Series]


class Episode(BaseModel):
    season: int | None
    episode: int | None
    title: str
    duration: int | None  # detik
    thumbnail: str | None
    stream_url: str | None
    subtitle_url: str | None


class TmdbMovie(BaseModel):
    id: int
    title: str
    year: int | None
    overview: str
    poster: str | None
    backdrop: str | None
    rating: float
    genres: list[str] = []
    media_type: str = "movie"


class TmdbPage(BaseModel):
    page: int
    total: int
    results: list[TmdbMovie]


class TmdbCast(BaseModel):
    name: str
    character: str
    photo: str | None


class TmdbTrailer(BaseModel):
    name: str
    url: str  # halaman YouTube
    thumbnail: str


class TmdbProvider(BaseModel):
    name: str
    logo: str | None
    kind: str  # salah satu WATCH_KINDS


class TmdbMovieDetail(TmdbMovie):
    cast: list[TmdbCast]
    trailer: TmdbTrailer | None
    # Layanan streaming resmi di WATCH_REGION. Sumber datanya JustWatch, wajib disebut di app.
    providers: list[TmdbProvider]
    watch_link: str | None


class TvSeasonInfo(BaseModel):
    season_number: int
    name: str
    episode_count: int
    poster: str | None


class TvDetail(BaseModel):
    id: int
    title: str
    year: int | None
    overview: str
    poster: str | None
    backdrop: str | None
    rating: float
    genres: list[str] = []
    number_of_seasons: int
    number_of_episodes: int
    seasons: list[TvSeasonInfo] = []
    status: str = ""
    networks: list[str] = []
    next_episode: str | None = None
    providers: list[TmdbProvider] = []
    watch_link: str | None = None


class TvEpisode(BaseModel):
    id: int
    episode_number: int
    season_number: int
    name: str
    overview: str
    still: str | None
    rating: float
    air_date: str | None


class SeriesEpisodes(BaseModel):
    series: Series
    episodes: list[Episode]


# --- Helper regex: nomor episode ---------------------------------------------


class EpisodeNumber(NamedTuple):
    season: int | None
    episode: int | None


_SEASON_EPISODE = re.compile(  # s01e19, S2E7, "Season 8, episode 7"
    r"(?<![a-z0-9])s(?:eason)?\s*(\d{1,2})\W{0,3}e(?:p(?:isode)?)?\.?\s*(\d{1,3})(?!\d)", re.I
)
_SEASON_X_EPISODE = re.compile(r"(?<!\d)(\d{1,2})x(\d{1,3})(?!\d)", re.I)  # 1x05, bukan 1920x1080
_KEYWORD_NUMBER = re.compile(  # Episode 3, Ep40, ch01, Part 2, No. 4, #18
    r"(?<![a-z])(?:episode|episodio|eps?|chapter|chap|ch|part|pt|bagian|no|#)\.?\s*#?\s*(\d{1,4})(?!\d)",
    re.I,
)
_WORDS = {w: i for i, w in enumerate("one two three four five six seven eight nine ten eleven twelve".split(), 1)}
_KEYWORD_WORD = re.compile(r"(?<![a-z])(?:episode|chapter|part)\s+(" + "|".join(_WORDS) + r")(?![a-z])", re.I)
_DATE = re.compile(r"\d{4}[._/-]\d{1,2}[._/-]\d{1,2}")
_TRAILING_NUMBER = re.compile(r"(?<!\d)(\d{1,3})(?!.*\d)")  # angka terakhir 1-3 digit, jadi bukan tahun
_EXTENSION = re.compile(r"\.[A-Za-z0-9]{2,4}$")


def extract_episode_number(text: str) -> EpisodeNumber:
    """(musim, episode) dari judul. Tahun ('PriceIsRight1957') dan tanggal tidak dihitung."""
    if m := _SEASON_EPISODE.search(text) or _SEASON_X_EPISODE.search(text):
        return EpisodeNumber(int(m.group(1)), int(m.group(2)))
    if m := _KEYWORD_NUMBER.search(text):
        return EpisodeNumber(None, int(m.group(1)))
    if m := _KEYWORD_WORD.search(text):
        return EpisodeNumber(None, _WORDS[m.group(1).lower()])
    if m := _TRAILING_NUMBER.search(_DATE.sub(" ", text)):
        return EpisodeNumber(None, int(m.group(1)))
    return EpisodeNumber(None, None)


# --- Helper base64 & HTML ----------------------------------------------------


def b64decode_padded(value: str) -> bytes:
    """Decode base64 standar atau URL-safe; '=' yang hilang ditambahkan otomatis."""
    data = re.sub(r"\s+", "", value)
    data += "=" * (-len(data) % 4)
    altchars = b"-_" if re.search(r"[-_]", data) else None
    return base64.b64decode(data, altchars=altchars, validate=True)


def decode_hidden_attr(raw: str) -> Any:
    """Isi atribut data tersembunyi: JSON, atau JSON yang di-encode base64.

    Archive saat ini memakai JSON biasa (entity HTML-nya sudah dibuka BeautifulSoup);
    jalur base64 menangani atribut yang di-encode.
    """
    text = raw.strip()
    if not text.startswith(("[", "{")):
        text = b64decode_padded(text).decode("utf-8")
    return json.loads(text)


def parse_playlist(html: str) -> list[dict[str, Any]]:
    """Data episode dari atribut `playlist` pada <play-av> di halaman detail item.

    Semua kegagalan dilaporkan sebagai ValueError (termasuk JSON/base64 yang rusak).
    """
    soup = BeautifulSoup(html, "html.parser", parse_only=SoupStrainer("play-av"))
    player = soup.find("play-av", attrs={"playlist": True})
    if player is None:
        raise ValueError("atribut playlist pada <play-av> tidak ditemukan")
    data = decode_hidden_attr(str(player["playlist"]))
    if not isinstance(data, list):
        raise ValueError("playlist bukan daftar")
    return [item for item in data if isinstance(item, dict)]


def clean_html(value: Any) -> str:
    """Deskripsi Archive sering berisi HTML; ambil teksnya dengan baris yang rapi."""
    if isinstance(value, list):
        value = "\n\n".join(str(v) for v in value)
    if not value:
        return ""
    soup = BeautifulSoup(str(value), "html.parser")
    for br in soup.find_all("br"):
        br.replace_with("\n")
    for block in soup.find_all(["p", "div", "li", "tr", "h1", "h2", "h3", "h4"]):
        block.append("\n")
    lines = (" ".join(line.split()) for line in soup.get_text().splitlines())
    return re.sub(r"\n{3,}", "\n\n", "\n".join(lines)).strip()


def absolute_url(path: Any) -> str | None:
    """Path dari Archive kadang sudah di-encode ('%20'), kadang belum (spasi)."""
    if not path:
        return None
    return urljoin(ARCHIVE + "/", quote(str(path), safe="/%:?=&#+"))


# --- Konversi data Archive ---------------------------------------------------


def _text(value: Any) -> str:
    if isinstance(value, list):
        return ", ".join(_text(v) for v in value if v)
    return "" if value is None else str(value).strip()


def _int(value: Any) -> int | None:
    if isinstance(value, list):
        value = value[0] if value else None
    try:
        return int(float(value))
    except (TypeError, ValueError, OverflowError):
        return None


def _year(value: Any) -> int | None:
    if isinstance(value, list):
        value = value[0] if value else None
    if isinstance(value, (int, float)):
        return int(value)
    m = re.search(r"\b(1[89]\d\d|20\d\d)\b", str(value or ""))
    return int(m.group(1)) if m else None


def _duration(value: Any) -> int | None:
    try:
        return round(float(value))
    except (TypeError, ValueError, OverflowError):
        return None


def to_series(doc: dict[str, Any]) -> Series:
    slug = _text(doc["identifier"])
    return Series(
        slug=slug,
        title=_text(doc.get("title")) or slug,
        year=_year(doc.get("year")),
        description=clean_html(doc.get("description")),
        poster=f"{ARCHIVE}/services/img/{slug}",
        downloads=_int(doc.get("downloads")) or 0,
    )


def pick_stream(sources: Any) -> str | None:
    """mp4 teringan yang masih >= 240p: cukup jelas di HP, hemat data."""
    files = [s for s in sources or [] if isinstance(s, dict) and s.get("file")]
    mp4 = [s for s in files if s.get("type") == "mp4"]
    if not mp4:
        return absolute_url(files[0]["file"]) if files else None

    def height(source: dict[str, Any]) -> int:
        return _int(source.get("height")) or 0

    sharp_enough = [s for s in mp4 if height(s) >= 240]
    return absolute_url(min(sharp_enough or mp4, key=height)["file"])


def is_subtitle_file(name: str) -> bool:
    """Nama file .vtt/.srt relatif di dalam item: tanpa '..', path absolut, atau karakter aneh."""
    return (
        0 < len(name) <= 300
        and name.lower().endswith((".vtt", ".srt"))
        and all(part not in ("", ".", "..") for part in name.split("/"))
        and not re.search(r"[\\?#\x00-\x1f]", name)
    )


def subtitle_file(tracks: Any, slug: str) -> str | None:
    """Nama file subtitle pertama milik item ini, relatif terhadap /download/{slug}/."""
    prefix = f"/download/{slug}/"
    for track in tracks or []:
        if isinstance(track, dict) and track.get("kind") in ("subtitles", "captions") and track.get("file"):
            path = unquote(urlsplit(str(track["file"])).path)
            name = path[len(prefix) :] if path.startswith(prefix) else ""
            if is_subtitle_file(name):
                return name
    return None


def looks_like_subtitle(data: bytes) -> bool:
    """Ada minimal satu cue (`mulai --> selesai`).

    Untuk file yang tidak ada, /download/ Archive membalas 200 dengan body kosong, bukan 404.
    """
    return b"-->" in data


def to_episode(item: dict[str, Any], slug: str, subtitle_link: Callable[[str], str]) -> Episode:
    """`subtitle_link` mengubah nama file subtitle menjadi URL (proxy di backend ini)."""
    orig = _text(item.get("orig"))
    title = _text(item.get("title")) or orig
    number = extract_episode_number(title)
    if number.episode is None and orig:
        # Judul kadang tanpa nomor, tapi nama filenya punya ("Bonanza s01e21.mp4").
        number = extract_episode_number(_EXTENSION.sub("", orig))
    subtitle = subtitle_file(item.get("tracks"), slug)
    return Episode(
        season=number.season,
        episode=number.episode,
        title=title,
        duration=_duration(item.get("duration")),
        thumbnail=absolute_url(item.get("image")),
        stream_url=pick_stream(item.get("sources")),
        subtitle_url=subtitle_link(subtitle) if subtitle else None,
    )


def sort_episodes(episodes: list[Episode]) -> list[Episode]:
    """Urut per (musim, episode); yang tanpa nomor di akhir dengan urutan aslinya."""
    return sorted(episodes, key=lambda e: (e.episode is None, e.season or 0, e.episode or 0))


def _sanitize(term: str | None) -> str:
    # Buang karakter yang punya arti khusus di sintaks query Lucene milik Archive.
    return " ".join(re.sub(r'[()":\[\]{}^~*?\\/!+\-&|]', " ", term or "").split())


def to_tmdb_movie(doc: dict[str, Any], genre_names: dict[int, str]) -> TmdbMovie:
    poster, backdrop = doc.get("poster_path"), doc.get("backdrop_path")
    genres = [g["name"] for g in doc.get("genres") or [] if isinstance(g, dict) and g.get("name")]
    genres = genres or [genre_names[i] for i in doc.get("genre_ids") or [] if i in genre_names]
    return TmdbMovie(
        id=int(doc["id"]),
        title=_text(doc.get("title")) or _text(doc.get("name")) or "Tanpa judul",
        year=_year(doc.get("release_date") or doc.get("first_air_date")),
        overview=_text(doc.get("overview")),
        poster=f"{TMDB_IMAGE}/w500{poster}" if poster else None,
        backdrop=f"{TMDB_IMAGE}/w780{backdrop}" if backdrop else None,
        rating=round(float(doc.get("vote_average") or 0), 1),
        genres=genres,
        media_type="movie",
    )


def to_tmdb_tv(doc: dict[str, Any], genre_names: dict[int, str]) -> TmdbMovie:
    poster, backdrop = doc.get("poster_path"), doc.get("backdrop_path")
    genres = [g["name"] for g in doc.get("genres") or [] if isinstance(g, dict) and g.get("name")]
    genres = genres or [genre_names[i] for i in doc.get("genre_ids") or [] if i in genre_names]
    return TmdbMovie(
        id=int(doc["id"]),
        title=_text(doc.get("name")) or _text(doc.get("title")) or "Tanpa judul",
        year=_year(doc.get("first_air_date") or doc.get("release_date")),
        overview=_text(doc.get("overview")),
        poster=f"{TMDB_IMAGE}/w500{poster}" if poster else None,
        backdrop=f"{TMDB_IMAGE}/w780{backdrop}" if backdrop else None,
        rating=round(float(doc.get("vote_average") or 0), 1),
        genres=genres,
        media_type="tv",
    )


def pick_trailer(videos: Any) -> TmdbTrailer | None:
    """Video YouTube terbaik dari `videos.results` TMDB, atau None.

    Urutan prioritas: tipe Trailer (Teaser hanya cadangan), resmi, bahasa sesuai
    TRAILER_LANGUAGES, berjudul "Official Trailer", lalu yang terbit paling awal.
    Trailer yang terbit belakangan biasanya promo, misalnya pengumuman rilis digital.
    """
    candidates = [
        v
        for v in videos or []
        if isinstance(v, dict)
        and v.get("site") == "YouTube"
        and v.get("type") in ("Trailer", "Teaser")
        and isinstance(v.get("key"), str)
        and v["key"]
    ]
    if not candidates:
        return None

    def rank(video: dict[str, Any]) -> tuple[bool, bool, int, bool, str]:
        name = _text(video.get("name")).lower()
        language = video.get("iso_639_1")
        return (
            video["type"] != "Trailer",
            not video.get("official"),
            TRAILER_LANGUAGES.index(language) if language in TRAILER_LANGUAGES else len(TRAILER_LANGUAGES),
            not any(label in name for label in ("official trailer", "trailer resmi")),
            _text(video.get("published_at")) or "9999",
        )

    best = min(candidates, key=rank)
    key = quote(best["key"], safe="")
    return TmdbTrailer(
        name=_text(best.get("name")) or "Trailer",
        url=f"https://www.youtube.com/watch?v={key}",
        thumbnail=f"https://i.ytimg.com/vi/{key}/hqdefault.jpg",
    )


def to_cast(credits: Any) -> list[TmdbCast]:
    """Pemeran utama dari `credits` TMDB, urut sesuai `order`, paling banyak MAX_CAST."""
    cast = credits.get("cast") if isinstance(credits, dict) else None
    people = [p for p in cast or [] if isinstance(p, dict) and _text(p.get("name"))]
    people.sort(key=lambda p: p["order"] if isinstance(p.get("order"), int) else 10**6)
    return [
        TmdbCast(
            name=_text(p["name"]),
            character=_text(p.get("character")),
            photo=f"{TMDB_IMAGE}/w185{p['profile_path']}" if p.get("profile_path") else None,
        )
        for p in people[:MAX_CAST]
    ]


def to_providers(watch: Any) -> tuple[list[TmdbProvider], str | None]:
    """Layanan streaming resmi di WATCH_REGION dan tautan halaman tontonnya di TMDB."""
    results = watch.get("results") if isinstance(watch, dict) else None
    entry = results.get(WATCH_REGION) if isinstance(results, dict) else None
    if not isinstance(entry, dict):
        return [], None
    providers: list[TmdbProvider] = []
    for kind in WATCH_KINDS:
        offers = [p for p in entry.get(kind) or [] if isinstance(p, dict) and _text(p.get("provider_name"))]
        offers.sort(key=lambda p: p["display_priority"] if isinstance(p.get("display_priority"), int) else 10**6)
        providers += [
            TmdbProvider(
                name=_text(p["provider_name"]),
                logo=f"{TMDB_IMAGE}/w92{p['logo_path']}" if p.get("logo_path") else None,
                kind=kind,
            )
            for p in offers
        ]
    link = entry.get("link")
    return providers, link if isinstance(link, str) and link.startswith("https://") else None


def to_tmdb_detail(doc: dict[str, Any]) -> TmdbMovieDetail:
    """Detail film dari respons /movie/{id} dengan append_to_response=credits,videos,watch/providers."""
    videos = doc.get("videos")
    providers, watch_link = to_providers(doc.get("watch/providers"))
    return TmdbMovieDetail(
        **to_tmdb_movie(doc, {}).model_dump(),
        cast=to_cast(doc.get("credits")),
        trailer=pick_trailer(videos.get("results") if isinstance(videos, dict) else None),
        providers=providers,
        watch_link=watch_link,
    )


# --- Aplikasi ----------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Satu AsyncClient untuk seluruh aplikasi agar koneksi ke archive.org dipakai ulang,
    # dan semaphore agar paling banyak 5 request berjalan bersamaan ke Archive.
    async with httpx.AsyncClient(
        base_url=ARCHIVE,
        headers={"User-Agent": "filmku-backend/1.0"},
        timeout=httpx.Timeout(20.0, connect=10.0),
        follow_redirects=True,
    ) as client:
        async with httpx.AsyncClient(
            base_url=TMDB,
            headers={"User-Agent": "filmku-backend/1.0"},
            timeout=httpx.Timeout(20.0, connect=10.0),
        ) as tmdb:
            yield {
                "http": client,
                "tmdb": tmdb,
                "limiter": asyncio.Semaphore(MAX_CONCURRENT_REQUESTS),
                # slug -> Series yang sudah terbukti ada di katalog domain publik.
                "catalog": {},
                "tmdb_genres": {},
            }


app = FastAPI(title="filmku backend", version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class PathRewriteMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope.get("type") == "http":
            query_string = scope.get("query_string", b"").decode("utf-8", errors="ignore")
            from urllib.parse import parse_qs, urlencode
            params = parse_qs(query_string, keep_blank_values=True)
            if "__path__" in params:
                raw_path = params.pop("__path__")[0]
                scope["path"] = raw_path if raw_path.startswith("/") else f"/{raw_path}"
                scope["raw_path"] = scope["path"].encode("utf-8")
                scope["query_string"] = urlencode(params, doseq=True).encode("utf-8")
            elif scope.get("path") in ("/api/index.py", "/api/index"):
                scope["path"] = "/"
                scope["raw_path"] = b"/"
        await self.app(scope, receive, send)


app.add_middleware(PathRewriteMiddleware)

_global_limiter: asyncio.Semaphore | None = None
_global_http: httpx.AsyncClient | None = None
_global_tmdb: httpx.AsyncClient | None = None
_global_catalog: dict[str, Any] = {}
_global_tmdb_genres: dict[int, str] = {}


def _get_global_limiter() -> asyncio.Semaphore:
    global _global_limiter
    if _global_limiter is None:
        _global_limiter = asyncio.Semaphore(MAX_CONCURRENT_REQUESTS)
    return _global_limiter


def _get_global_http() -> httpx.AsyncClient:
    global _global_http
    if _global_http is None or _global_http.is_closed:
        _global_http = httpx.AsyncClient(
            base_url=ARCHIVE,
            headers={"User-Agent": "filmku-backend/1.0"},
            timeout=httpx.Timeout(20.0, connect=10.0),
            follow_redirects=True,
        )
    return _global_http


def _get_global_tmdb() -> httpx.AsyncClient:
    global _global_tmdb
    if _global_tmdb is None or _global_tmdb.is_closed:
        _global_tmdb = httpx.AsyncClient(
            base_url=TMDB,
            headers={"User-Agent": "filmku-backend/1.0"},
            timeout=httpx.Timeout(20.0, connect=10.0),
        )
    return _global_tmdb


@app.middleware("http")
async def ensure_state_middleware(request: Request, call_next):
    if not hasattr(request.state, "limiter") or request.state.limiter is None:
        request.state.limiter = _get_global_limiter()
    if not hasattr(request.state, "http") or request.state.http is None:
        request.state.http = _get_global_http()
    if not hasattr(request.state, "tmdb") or request.state.tmdb is None:
        request.state.tmdb = _get_global_tmdb()
    if not hasattr(request.state, "catalog") or request.state.catalog is None:
        request.state.catalog = _global_catalog
    if not hasattr(request.state, "tmdb_genres") or request.state.tmdb_genres is None:
        request.state.tmdb_genres = _global_tmdb_genres
    return await call_next(request)


@app.get("/")
@app.get("/api")
def home():
    return {
        "status": "ok",
        "service": "filmku backend online",
        "timestamp": time.time(),
    }



async def fetch(request: Request, path: str, params: dict[str, Any] | None = None) -> httpx.Response:
    async with request.state.limiter:
        try:
            response = await request.state.http.get(path, params=params)
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"Internet Archive tidak bisa dihubungi ({type(exc).__name__})") from exc
    if response.status_code == 404:
        raise HTTPException(404, "Tidak ditemukan di Internet Archive")
    if response.status_code != 200:
        raise HTTPException(502, f"Internet Archive membalas HTTP {response.status_code}")
    return response


async def search_series(request: Request, query: str, page: int, rows: int) -> tuple[int, list[Series]]:
    response = await fetch(
        request,
        "/advancedsearch.php",
        {"q": query, "fl[]": SEARCH_FIELDS, "sort[]": "downloads desc", "rows": rows, "page": page, "output": "json"},
    )
    try:
        result = response.json()["response"]
        total, docs = int(result["numFound"]), result["docs"]
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(502, "Respons pencarian Internet Archive tidak dikenal") from exc
    return total, [to_series(d) for d in docs if isinstance(d, dict) and d.get("identifier")]


async def catalog_series(request: Request, slug: str) -> Series:
    """Serial di katalog domain publik, atau 404. Hasilnya diingat selama server berjalan."""
    known: dict[str, Series] = request.state.catalog
    if slug not in known:
        _, found = await search_series(request, f'{CATALOG_QUERY} AND identifier:"{slug}"', page=1, rows=1)
        if not found:
            raise HTTPException(404, "Serial tidak ada di katalog domain publik")
        known[slug] = found[0]
    return known[slug]


async def tmdb_get(request: Request, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    """GET ke TMDB dengan API key dari environment; key tidak pernah dikirim ke klien."""
    key = os.environ.get("TMDB_API_KEY", "").strip() or DEFAULT_TMDB_API_KEY
    if not key:
        raise HTTPException(503, "TMDB_API_KEY belum diatur di backend/.env")
    # Token v4 (JWT, diawali 'eyJ') dikirim lewat header; key v3 lewat query.
    headers = {"Authorization": f"Bearer {key}"} if key.startswith("eyJ") else {}
    query = {"language": "en-US", **(params or {})}
    if not headers:
        query["api_key"] = key
    async with request.state.limiter:
        try:
            response = await request.state.tmdb.get(path, params=query, headers=headers)
        except httpx.HTTPError as exc:
            raise HTTPException(502, f"TMDB tidak bisa dihubungi ({type(exc).__name__})") from exc
    if response.status_code == 401:
        raise HTTPException(503, "TMDB menolak API key; periksa TMDB_API_KEY")
    if response.status_code == 404:
        raise HTTPException(404, "Tidak ditemukan di TMDB")
    if response.status_code != 200:
        raise HTTPException(502, f"TMDB membalas HTTP {response.status_code}")
    return response.json()


async def tmdb_genre_names(request: Request) -> dict[int, str]:
    names: dict[int, str] = request.state.tmdb_genres
    if not names:
        movie_genres, tv_genres = await asyncio.gather(
            tmdb_get(request, "/genre/movie/list"),
            tmdb_get(request, "/genre/tv/list"),
            return_exceptions=True,
        )
        if isinstance(movie_genres, dict):
            names.update({g["id"]: g["name"] for g in movie_genres.get("genres", []) if isinstance(g, dict)})
        if isinstance(tv_genres, dict):
            names.update({g["id"]: g["name"] for g in tv_genres.get("genres", []) if isinstance(g, dict)})
    return names


async def tmdb_page(request: Request, path: str, page: int, params: dict[str, Any] | None = None) -> TmdbPage:
    data, genres = await asyncio.gather(
        tmdb_get(request, path, {"page": page, **(params or {})}), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_movie(d, genres) for d in docs])


@app.get("/api/tmdb/popular", response_model=TmdbPage)
async def tmdb_popular(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    return await tmdb_page(request, "/movie/popular", page)


@app.get("/api/tmdb/top_rated", response_model=TmdbPage)
async def tmdb_top_rated(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    return await tmdb_page(request, "/movie/top_rated", page)


@app.get("/api/tmdb/trending", response_model=TmdbPage)
async def tmdb_trending(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    return await tmdb_page(request, "/trending/movie/week", page)


@app.get("/api/tmdb/discover", response_model=TmdbPage)
async def tmdb_discover(
    request: Request,
    with_genres: str | None = Query(None, description="ID Genre TMDB (misal 28 untuk Aksi)"),
    page: int = Query(1, ge=1, le=100),
) -> TmdbPage:
    params: dict[str, Any] = {}
    if with_genres:
        params["with_genres"] = with_genres
    return await tmdb_page(request, "/discover/movie", page, params)


# Pengecualian genre non-drakor untuk serial TV TMDB:
# 16: Animasi (Super Wings, Pororo, Tayo, dll)
# 10762: Anak-anak (Kids)
# 10763: Berita (News)
# 10764: Reality Show (Reality)
# 10767: Talk Show / Radio (Talk / Idol Radio)
# 99: Dokumenter (Documentary)
KDRAMA_EXCLUDED_GENRES = "16,10762,10763,10764,10767,99"


@app.get("/api/tmdb/kdrama", response_model=TmdbPage)
async def tmdb_kdrama(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    params = {
        "with_origin_country": "KR",
        "with_original_language": "ko",
        "with_genres": "18",
        "without_genres": KDRAMA_EXCLUDED_GENRES,
        "sort_by": "popularity.desc",
        "page": page,
        "language": "en-US",
    }
    data, genres = await asyncio.gather(
        tmdb_get(request, "/discover/tv", params), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_tv(d, genres) for d in docs])


@app.get("/api/tmdb/kdrama/airing", response_model=TmdbPage)
async def tmdb_kdrama_airing(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    params = {
        "with_origin_country": "KR",
        "with_original_language": "ko",
        "with_genres": "18",
        "without_genres": KDRAMA_EXCLUDED_GENRES,
        "air_date.lte": time.strftime("%Y-%m-%d"),
        "air_date.gte": time.strftime("%Y-%m-%d", time.localtime(time.time() - 45 * 86400)),
        "sort_by": "popularity.desc",
        "page": page,
        "language": "en-US",
    }
    data, genres = await asyncio.gather(
        tmdb_get(request, "/discover/tv", params), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_tv(d, genres) for d in docs])


@app.get("/api/tmdb/kdrama/top_rated", response_model=TmdbPage)
async def tmdb_kdrama_top_rated(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    params = {
        "with_origin_country": "KR",
        "with_original_language": "ko",
        "with_genres": "18",
        "without_genres": KDRAMA_EXCLUDED_GENRES,
        "sort_by": "vote_average.desc",
        "vote_count.gte": 150,
        "page": page,
        "language": "en-US",
    }
    data, genres = await asyncio.gather(
        tmdb_get(request, "/discover/tv", params), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_tv(d, genres) for d in docs])


@app.get("/api/tmdb/kdrama/romance", response_model=TmdbPage)
async def tmdb_kdrama_romance(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    params = {
        "with_origin_country": "KR",
        "with_original_language": "ko",
        "with_genres": "10749",
        "without_genres": KDRAMA_EXCLUDED_GENRES,
        "sort_by": "popularity.desc",
        "page": page,
        "language": "en-US",
    }
    data, genres = await asyncio.gather(
        tmdb_get(request, "/discover/tv", params), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_tv(d, genres) for d in docs])


@app.get("/api/tmdb/kdrama/thriller", response_model=TmdbPage)
async def tmdb_kdrama_thriller(request: Request, page: int = Query(1, ge=1, le=100)) -> TmdbPage:
    params = {
        "with_origin_country": "KR",
        "with_original_language": "ko",
        "with_genres": "9648,80",
        "without_genres": KDRAMA_EXCLUDED_GENRES,
        "sort_by": "popularity.desc",
        "page": page,
        "language": "en-US",
    }
    data, genres = await asyncio.gather(
        tmdb_get(request, "/discover/tv", params), tmdb_genre_names(request)
    )
    docs = [d for d in data.get("results", []) if isinstance(d, dict) and d.get("id")]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=[to_tmdb_tv(d, genres) for d in docs])


@app.get("/api/tmdb/tv/{tv_id}", response_model=TvDetail)
async def tmdb_tv_detail(request: Request, tv_id: int) -> TvDetail:
    doc = await tmdb_get(request, f"/tv/{tv_id}", {"append_to_response": "watch/providers", "language": "en-US"})
    poster, backdrop = doc.get("poster_path"), doc.get("backdrop_path")
    genres = [g["name"] for g in doc.get("genres") or [] if isinstance(g, dict) and g.get("name")]
    seasons = [
        TvSeasonInfo(
            season_number=s.get("season_number", 0),
            name=s.get("name") or f"Season {s.get('season_number', 0)}",
            episode_count=s.get("episode_count", 0),
            poster=f"{TMDB_IMAGE}/w500{s['poster_path']}" if s.get("poster_path") else None,
        )
        for s in doc.get("seasons", [])
        if s.get("season_number", 0) > 0
    ]
    raw_status = doc.get("status") or ""
    if raw_status in ("Returning Series", "In Production"):
        status_label = "Sedang Tayang (On-Going)"
    elif raw_status in ("Ended", "Canceled"):
        status_label = "Tamat (Completed)"
    else:
        status_label = raw_status

    networks = [n["name"] for n in doc.get("networks") or [] if isinstance(n, dict) and n.get("name")]
    next_ep = doc.get("next_episode_to_air")
    next_episode_str = (
        f"Ep {next_ep.get('episode_number')} ({next_ep.get('air_date')})"
        if isinstance(next_ep, dict) and next_ep.get("air_date")
        else None
    )
    providers, watch_link = to_providers(doc.get("watch/providers"))

    return TvDetail(
        id=int(doc["id"]),
        title=_text(doc.get("name")) or "Tanpa judul",
        year=_year(doc.get("first_air_date")),
        overview=_text(doc.get("overview")),
        poster=f"{TMDB_IMAGE}/w500{poster}" if poster else None,
        backdrop=f"{TMDB_IMAGE}/w780{backdrop}" if backdrop else None,
        rating=round(float(doc.get("vote_average") or 0), 1),
        genres=genres,
        number_of_seasons=int(doc.get("number_of_seasons") or len(seasons)),
        number_of_episodes=int(doc.get("number_of_episodes") or 0),
        seasons=seasons,
        status=status_label,
        networks=networks,
        next_episode=next_episode_str,
        providers=providers,
        watch_link=watch_link,
    )


@app.get("/api/tmdb/tv/{tv_id}/season/{season_number}", response_model=list[TvEpisode])
async def tmdb_tv_season(request: Request, tv_id: int, season_number: int = 1) -> list[TvEpisode]:
    doc = await tmdb_get(request, f"/tv/{tv_id}/season/{season_number}", {"language": "en-US"})
    episodes = doc.get("episodes", [])
    return [
        TvEpisode(
            id=int(e.get("id") or 0),
            episode_number=int(e.get("episode_number") or 1),
            season_number=season_number,
            name=_text(e.get("name")) or f"Episode {e.get('episode_number', 1)}",
            overview=_text(e.get("overview")),
            still=f"{TMDB_IMAGE}/w500{e['still_path']}" if e.get("still_path") else None,
            rating=round(float(e.get("vote_average") or 0), 1),
            air_date=e.get("air_date"),
        )
        for e in episodes
    ]


@app.get("/api/tmdb/search", response_model=TmdbPage)
async def tmdb_search(
    request: Request, q: str = Query(..., min_length=1, max_length=100), page: int = Query(1, ge=1, le=100)
) -> TmdbPage:
    data, genres = await asyncio.gather(
        tmdb_get(request, "/search/multi", {"query": q, "page": page, "language": "en-US"}), tmdb_genre_names(request)
    )
    docs = [
        d
        for d in data.get("results", [])
        if isinstance(d, dict) and d.get("id") and d.get("media_type") in ("movie", "tv")
    ]
    results = [
        to_tmdb_tv(d, genres) if d.get("media_type") == "tv" else to_tmdb_movie(d, genres)
        for d in docs
    ]
    return TmdbPage(page=page, total=int(data.get("total_results", 0)), results=results)


@app.get("/api/tmdb/movie/{movie_id}", response_model=TmdbMovieDetail)
async def tmdb_movie(request: Request, movie_id: int) -> TmdbMovieDetail:
    # Detail, pemain, video, dan penyedia streaming diambil dalam satu request ke TMDB.
    # Tanpa include_video_language, `language=id-ID` hanya menyisakan video berbahasa Indonesia.
    params = {
        "append_to_response": "credits,videos,watch/providers",
        "include_video_language": ",".join((*TRAILER_LANGUAGES, "null")),
    }
    return to_tmdb_detail(await tmdb_get(request, f"/movie/{movie_id}", params))


@app.get("/api/supabase/movies", response_model=TmdbPage)
async def supabase_movies(
    page: int = Query(1, ge=1, le=100),
    page_size: int = Query(20, ge=1, le=50),
    q: str | None = Query(None, max_length=100),
) -> TmdbPage:
    """Ambil film dari database Supabase (tabel tmdb_movies)."""
    db_url = os.environ.get("DATABASE_URL", "").strip() or DEFAULT_DATABASE_URL
    if not db_url:
        raise HTTPException(503, "DATABASE_URL belum diatur di backend/.env")
    if psycopg2 is None:
        raise HTTPException(503, "psycopg2 belum terpasang di environment")

    conn = psycopg2.connect(normalize_db_url(db_url))
    offset = (page - 1) * page_size
    try:
        with conn.cursor() as cur:
            if q:
                cur.execute(
                    """
                    SELECT id, original_title, year, overview, poster_path, backdrop_path, vote_average
                    FROM tmdb_movies
                    WHERE original_title ILIKE %s AND adult = false
                    ORDER BY popularity DESC
                    LIMIT %s OFFSET %s;
                    """,
                    (f"%{q}%", page_size, offset),
                )
            else:
                cur.execute(
                    """
                    SELECT id, original_title, year, overview, poster_path, backdrop_path, vote_average
                    FROM tmdb_movies
                    WHERE status = 'synced' AND poster_path IS NOT NULL AND adult = false
                    ORDER BY popularity DESC
                    LIMIT %s OFFSET %s;
                    """,
                    (page_size, offset),
                )
            rows = cur.fetchall()

            cur.execute("SELECT count(*) FROM tmdb_movies WHERE status = 'synced';")
            total = cur.fetchone()[0]

            results = [
                TmdbMovie(
                    id=r[0],
                    title=r[1],
                    year=r[2],
                    overview=r[3] or "",
                    poster=f"{TMDB_IMAGE}/w500{r[4]}" if r[4] else None,
                    backdrop=f"{TMDB_IMAGE}/w780{r[5]}" if r[5] else None,
                    rating=float(r[6] or 0.0),
                    genres=[],
                )
                for r in rows
            ]
            return TmdbPage(page=page, total=total, results=results)
    finally:
        conn.close()


class WatchPartyState(BaseModel):
    room_id: str
    action: str = "pause"  # "play", "pause", "seek"
    time: float = 0.0
    updated_at: float = 0.0


WATCH_PARTY_ROOMS: dict[str, WatchPartyState] = {}


@app.post("/api/watchparty/create", response_model=WatchPartyState)
async def create_watch_party_room() -> WatchPartyState:
    room_id = secrets.token_hex(3).upper()  # 6 character room code, e.g. A1B2C3
    state = WatchPartyState(room_id=room_id, action="pause", time=0.0, updated_at=time.time())
    WATCH_PARTY_ROOMS[room_id] = state
    return state


@app.get("/api/watchparty/{room_id}", response_model=WatchPartyState)
async def get_watch_party_room(room_id: str) -> WatchPartyState:
    room = WATCH_PARTY_ROOMS.get(room_id.upper())
    if not room:
        raise HTTPException(404, "Room tidak ditemukan atau sudah ditutup")
    return room


class WatchPartySyncRequest(BaseModel):
    action: str
    time: float


@app.post("/api/watchparty/{room_id}/sync", response_model=WatchPartyState)
async def sync_watch_party_room(room_id: str, payload: WatchPartySyncRequest) -> WatchPartyState:
    room_id = room_id.upper()
    state = WatchPartyState(
        room_id=room_id,
        action=payload.action,
        time=payload.time,
        updated_at=time.time(),
    )
    WATCH_PARTY_ROOMS[room_id] = state
    return state


@app.get("/")
async def index() -> dict[str, Any]:
    return {
        "endpoints": [
            "/api/catalog?page=1&q=",
            "/api/episodes?slug={slug}",
            "/api/subtitle?slug={slug}&file={file}",
            "/api/tmdb/popular",
            "/api/tmdb/search?q=",
            "/api/tmdb/movie/{id}",
        ],
        "docs": "/docs",
    }


@app.get("/api/catalog", response_model=CatalogPage)
async def catalog(
    request: Request,
    page: int = Query(1, ge=1, le=100),
    q: str | None = Query(None, max_length=100, description="Cari di judul serial"),
) -> CatalogPage:
    query = CATALOG_QUERY
    if term := _sanitize(q):
        query += f" AND title:({term})"
    total, series = await search_series(request, query, page=page, rows=PAGE_SIZE)
    request.state.catalog.update({s.slug: s for s in series})
    return CatalogPage(page=page, total=total, results=series)


@app.get("/api/episodes", response_model=SeriesEpisodes)
async def episodes(request: Request, slug: str = Query(..., pattern=SLUG_PATTERN)) -> SeriesEpisodes:
    # Cek keanggotaan katalog dan ambil halaman detail bersamaan; keduanya lewat semaphore.
    series, page = await asyncio.gather(catalog_series(request, slug), fetch(request, f"/details/{slug}"))
    try:
        playlist = parse_playlist(page.text)
    except ValueError as exc:
        raise HTTPException(502, f"Format halaman Internet Archive berubah: {exc}") from exc

    def subtitle_link(file: str) -> str:
        return str(request.url_for("subtitle").include_query_params(slug=slug, file=file))

    items = sort_episodes([to_episode(item, slug, subtitle_link) for item in playlist])
    return SeriesEpisodes(series=series, episodes=items)


@app.get("/api/subtitle")
async def subtitle(
    request: Request,
    slug: str = Query(..., pattern=SLUG_PATTERN),
    file: str = Query(..., max_length=300, description="Nama file .vtt/.srt di dalam item"),
) -> Response:
    """Teruskan subtitle dari Archive dengan header CORS.

    File di /download/ Archive tidak mengirim Access-Control-Allow-Origin, jadi app versi
    web tidak bisa mengambilnya langsung. Hanya file subtitle milik serial di katalog
    yang dilayani, supaya endpoint ini tidak menjadi proxy bebas.
    """
    if not is_subtitle_file(file):
        raise HTTPException(422, "file harus berupa .vtt atau .srt di dalam item")
    await catalog_series(request, slug)
    response = await fetch(request, f"/download/{slug}/{quote(file)}")
    if len(response.content) > SUBTITLE_MAX_BYTES:
        raise HTTPException(502, "File subtitle terlalu besar")
    if not looks_like_subtitle(response.content):
        raise HTTPException(404, "Subtitle tidak ditemukan di item ini")
    media_type = "text/vtt" if file.lower().endswith(".vtt") else "application/x-subrip"
    return Response(
        response.content,
        media_type=f"{media_type}; charset=utf-8",
        headers={"Cache-Control": "public, max-age=86400"},
    )


class AppVersionInfo(BaseModel):
    latest_version: str
    version_code: int
    changelog: list[str]
    download_url: str
    released_at: str
    force_update: bool = False


@app.get("/api/app/version", response_model=AppVersionInfo)
async def get_app_version(request: Request) -> AppVersionInfo:
    return AppVersionInfo(
        latest_version="1.2.0",
        version_code=3,
        changelog=[
            "Layar Penuh Sejati (True Immersive Sticky Fullscreen)",
            "Fitur Baru: Isi Layar Penuh (Zoom to Fill) menghilangkan bar hitam samping",
            "Server VidLink (No Ads) dengan Subtitle Multi-Bahasa yang Otomatis Pas & Sinkron",
            "Fitur Pilih Episode langsung di dalam Player Layar Penuh",
            "Dok Kontrol Layar Penuh (Pilih Episode, Ganti Server, Bantuan Subtitle)",
            "Perbaikan bug riwayat tontonan Godzilla & Anime",
            "Domain VidSrc diperbarui ke vidsrc.xyz aktif",
        ],
        download_url="https://github.com/Gio-Mty/filmku/releases/latest/download/filmku.apk",
        released_at="2026-11-22",
        force_update=False,
    )


@app.api_route("/download/filmku.apk", methods=["GET", "HEAD"])
async def download_apk() -> Response:
    possible_paths = [
        Path(__file__).parent / "downloads" / "filmku.apk",
        Path(__file__).parent.parent / "build" / "app" / "outputs" / "flutter-apk" / "app-arm64-v8a-release.apk",
        Path(__file__).parent.parent / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk",
    ]
    for p in possible_paths:
        if p.is_file():
            return FileResponse(
                str(p),
                media_type="application/vnd.android.package-archive",
                filename="filmku-latest.apk",
            )
    from fastapi.responses import RedirectResponse
    return RedirectResponse(
        url="https://github.com/Gio-Mty/filmku/releases/latest/download/filmku.apk",
        status_code=302,
    )


try:
    from mangum import Mangum
    handler = Mangum(app)
except Exception:
    handler = app
