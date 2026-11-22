"""Sinkronisasi seluruh ID film TMDB ke PostgreSQL menggunakan Daily ID Export.

Mendukung bulk insert jutaan ID dalam hitungan detik menggunakan COPY command
ke temporary staging table dan UPSERT (ON CONFLICT DO UPDATE).

Cara pakai:
    1. Pastikan DATABASE_URL sudah diatur di backend/.env:
       DATABASE_URL=postgresql://postgres:password@localhost:5432/filmku
       (atau dari Supabase / Neon / Cloud Postgres)

    2. Jalankan:
       python backend/import_tmdb_to_postgres.py
       python backend/import_tmdb_to_postgres.py --exclude-adult
       python backend/import_tmdb_to_postgres.py --min-pop 1.0 --limit 50000
"""

import argparse
import csv
from datetime import datetime, timezone, timedelta
import gzip
import io
import json
import os
from pathlib import Path
import sys
import time
import urllib.request

try:
    import psycopg2
    from psycopg2 import sql
except ImportError:
    print("[!] Modul psycopg2 belum terpasang di Python ini.")
    print("[!] Jalankan menggunakan Python virtualenv:")
    print("    backend\\.venv\\Scripts\\python.exe backend/import_tmdb_to_postgres.py")
    sys.exit(1)


BASE_EXPORT_URL = "https://files.tmdb.org/p/exports"


def load_env() -> None:
    """Muat variabel dari backend/.env jika ada."""
    env_path = Path(__file__).with_name(".env")
    if env_path.is_file():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def find_latest_export_url() -> tuple[str, str]:
    """Cari URL ekspor TMDB terbaru."""
    now = datetime.now(timezone.utc)
    for day_offset in range(4):
        target_date = now - timedelta(days=day_offset)
        date_str = target_date.strftime("%m_%d_%Y")
        url = f"{BASE_EXPORT_URL}/movie_ids_{date_str}.json.gz"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "filmku/1.0"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    return url, date_str
        except Exception:
            continue
    raise RuntimeError("Tidak dapat menemukan file ekspor TMDB terbaru dalam 4 hari terakhir.")


def normalize_db_url(url: str) -> str:
    """Normalisasi format URL PostgreSQL untuk Supabase / cloud database."""
    url = url.strip().strip("\"'")
    if url.startswith("postgres://"):
        url = "postgresql://" + url[len("postgres://") :]
    # Jika password mengandung '#' unencoded sebelum '@', ubah jadi '%23'
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


def init_database(conn: psycopg2.extensions.connection) -> None:
    """Inisialisasi tabel, index, dan policy di PostgreSQL / Supabase jika belum ada."""
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS tmdb_movies (
                id INTEGER PRIMARY KEY,
                original_title TEXT NOT NULL,
                popularity DOUBLE PRECISION NOT NULL DEFAULT 0.0,
                adult BOOLEAN NOT NULL DEFAULT FALSE,
                video BOOLEAN NOT NULL DEFAULT FALSE,
                status VARCHAR(20) NOT NULL DEFAULT 'id_only',
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE INDEX IF NOT EXISTS idx_tmdb_movies_popularity ON tmdb_movies (popularity DESC);
            CREATE INDEX IF NOT EXISTS idx_tmdb_movies_adult ON tmdb_movies (adult);
            CREATE INDEX IF NOT EXISTS idx_tmdb_movies_status ON tmdb_movies (status);

            -- Supabase Row Level Security: Izinkan read publik agar bisa diakses langsung via Supabase API
            ALTER TABLE tmdb_movies ENABLE ROW LEVEL SECURITY;
            DO $$
            BEGIN
                IF NOT EXISTS (
                    SELECT 1 FROM pg_policies WHERE tablename = 'tmdb_movies' AND policyname = 'Allow public read'
                ) THEN
                    CREATE POLICY "Allow public read" ON tmdb_movies FOR SELECT USING (true);
                END IF;
            END
            $$;
        """)
    conn.commit()


def import_to_postgres(
    db_url: str,
    exclude_adult: bool = False,
    min_popularity: float = 0.0,
    limit: int | None = None,
    chunk_size: int = 100_000,
) -> None:
    """Stream dump TMDB dan lakukan bulk UPSERT ke PostgreSQL."""
    db_url = normalize_db_url(db_url)
    print(f"[*] Menghubungkan ke database (Supabase / PostgreSQL)...")
    conn = psycopg2.connect(db_url)

    init_database(conn)
    print(f"[+] Tabel dan index tmdb_movies siap.")

    url, date_str = find_latest_export_url()
    print(f"[*] Mengunduh & memproses ekspor tanggal: {date_str}")
    print(f"[*] Filter: exclude_adult={exclude_adult}, min_popularity={min_popularity}")

    req = urllib.request.Request(url, headers={"User-Agent": "filmku/1.0"})
    
    start_time = time.time()
    total_scanned = 0
    total_imported = 0

    with urllib.request.urlopen(req) as response:
        with gzip.GzipFile(fileobj=response) as gz_stream:
            text_stream = io.TextIOWrapper(gz_stream, encoding="utf-8")

            # Buffer TSV string untuk COPY command
            tsv_buffer = io.StringIO()
            current_chunk_count = 0

            def flush_chunk():
                nonlocal current_chunk_count, total_imported
                if current_chunk_count == 0:
                    return

                tsv_buffer.seek(0)
                with conn.cursor() as cur:
                    # Buat temp staging table
                    cur.execute("""
                        CREATE TEMP TABLE staging_movies (
                            id INTEGER,
                            original_title TEXT,
                            popularity DOUBLE PRECISION,
                            adult BOOLEAN,
                            video BOOLEAN
                        ) ON COMMIT DROP;
                    """)

                    # COPY super cepat dari buffer TSV
                    cur.copy_expert(
                        "COPY staging_movies (id, original_title, popularity, adult, video) FROM STDIN WITH (FORMAT CSV, DELIMITER E'\\t', QUOTE E'\\b')",
                        tsv_buffer,
                    )

                    # UPSERT ke tabel utama
                    cur.execute("""
                        INSERT INTO tmdb_movies (id, original_title, popularity, adult, video, updated_at)
                        SELECT id, original_title, popularity, adult, video, CURRENT_TIMESTAMP
                        FROM staging_movies
                        ON CONFLICT (id) DO UPDATE SET
                            original_title = EXCLUDED.original_title,
                            popularity = EXCLUDED.popularity,
                            adult = EXCLUDED.adult,
                            video = EXCLUDED.video,
                            updated_at = CURRENT_TIMESTAMP;
                    """)
                conn.commit()
                total_imported += current_chunk_count
                current_chunk_count = 0
                tsv_buffer.seek(0)
                tsv_buffer.truncate(0)

            for line in text_stream:
                line = line.strip()
                if not line:
                    continue

                total_scanned += 1
                try:
                    item = json.loads(line)
                except json.JSONDecodeError:
                    continue

                if exclude_adult and item.get("adult", False):
                    continue

                pop = float(item.get("popularity", 0.0) or 0.0)
                if pop < min_popularity:
                    continue

                m_id = item.get("id")
                # Bersihkan newline dan tab dari title untuk format TSV aman
                title = str(item.get("original_title", "")).replace("\t", " ").replace("\n", " ").replace("\r", "")
                adult_val = "1" if item.get("adult", False) else "0"
                video_val = "1" if item.get("video", False) else "0"

                tsv_buffer.write(f"{m_id}\t{title}\t{pop}\t{adult_val}\t{video_val}\n")
                current_chunk_count += 1

                if current_chunk_count >= chunk_size:
                    flush_chunk()
                    elapsed = time.time() - start_time
                    print(f"    ... Dipindai: {total_scanned:,} | Diimpor ke Postgres: {total_imported:,} ({elapsed:.1f}s)")

                if limit and (total_imported + current_chunk_count) >= limit:
                    break

            # Flush sisa buffer terakhir
            if current_chunk_count > 0:
                flush_chunk()

    conn.close()
    elapsed = time.time() - start_time
    print(f"\n[+] Selesai dalam {elapsed:.2f} detik!")
    print(f"[+] Total record dipindai: {total_scanned:,}")
    print(f"[+] Total film tersimpan di PostgreSQL: {total_imported:,}")


def main() -> None:
    load_env()
    default_db = os.environ.get("DATABASE_URL", "postgresql://postgres:password@localhost:5432/filmku")

    parser = argparse.ArgumentParser(description="Impor seluruh ID film TMDB ke database PostgreSQL.")
    parser.add_argument(
        "--db-url",
        type=str,
        default=default_db,
        help="PostgreSQL connection string (default: dari DATABASE_URL di .env)",
    )
    parser.add_argument(
        "--exclude-adult",
        action="store_true",
        default=False,
        help="Lewati film dewasa (default: False)",
    )
    parser.add_argument(
        "--min-pop",
        type=float,
        default=0.0,
        help="Minimal nilai popularitas (default: 0.0)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Batas jumlah record yang diimpor (untuk testing)",
    )

    args = parser.parse_args()

    try:
        import_to_postgres(
            db_url=args.db_url,
            exclude_adult=args.exclude_adult,
            min_popularity=args.min_pop,
            limit=args.limit,
        )
    except psycopg2.OperationalError as e:
        print(f"\n[!] Gagal terhubung ke PostgreSQL: {e}")
        print("[!] Pastikan server PostgreSQL sedang aktif dan DATABASE_URL sudah benar.")
        sys.exit(1)


if __name__ == "__main__":
    main()
