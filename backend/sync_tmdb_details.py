"""Sinkronisasi detail film (poster, sinopsis, rating, tahun) dari TMDB API ke Supabase.

Mengambil data detail untuk film-film di tabel `tmdb_movies` yang berstatus 'id_only'
dan memperbarui kolom poster_path, overview, vote_average, year, serta mengubah
statusnya menjadi 'synced'.

Cara pakai:
    python backend/sync_tmdb_details.py
    python backend/sync_tmdb_details.py --limit 50
    python backend/sync_tmdb_details.py --limit 100 --concurrency 5
"""

import argparse
import asyncio
import json
import os
from pathlib import Path
import sys
import time
import urllib.parse
import httpx
import psycopg2

try:
    from import_tmdb_to_postgres import load_env, normalize_db_url
except ImportError:
    from backend.import_tmdb_to_postgres import load_env, normalize_db_url


TMDB_BASE = "https://api.themoviedb.org/3"
TMDB_IMAGE = "https://image.tmdb.org/t/p"


async def sync_movie_details(
    db_url: str,
    api_key: str,
    limit: int = 50,
    concurrency: int = 5,
) -> None:
    db_url = normalize_db_url(db_url)
    conn = psycopg2.connect(db_url)

    # Ambil film dengan popularitas tertinggi yang belum di-sync
    with conn.cursor() as cur:
        cur.execute("""
            SELECT id, original_title FROM tmdb_movies
            WHERE status = 'id_only' AND adult = false
            ORDER BY popularity DESC
            LIMIT %s;
        """, (limit,))
        movies = cur.fetchall()

    if not movies:
        print("[*] Semua film sudah tersinkronisasi atau belum ada data di database.")
        conn.close()
        return

    print(f"[*] Menemukan {len(movies)} film untuk disinkronkan ke TMDB API...")
    semaphore = asyncio.Semaphore(concurrency)
    start_time = time.time()
    synced_count = 0

    headers = {"Authorization": f"Bearer {api_key}"} if api_key.startswith("eyJ") else {}

    async with httpx.AsyncClient(timeout=15.0) as client:
        async def fetch_and_save(m_id: int, original_title: str):
            nonlocal synced_count
            params = {"language": "id-ID"}
            if not headers:
                params["api_key"] = api_key

            url = f"{TMDB_BASE}/movie/{m_id}"
            async with semaphore:
                try:
                    res = await client.get(url, params=params, headers=headers)
                    if res.status_code == 404:
                        # Film tidak ditemukan di TMDB lagi
                        with conn.cursor() as cur:
                            cur.execute("UPDATE tmdb_movies SET status = 'failed' WHERE id = %s", (m_id,))
                        conn.commit()
                        return

                    if res.status_code != 200:
                        return

                    data = res.json()
                    poster = data.get("poster_path")
                    backdrop = data.get("backdrop_path")
                    overview = data.get("overview") or ""
                    rating = round(float(data.get("vote_average") or 0.0), 1)
                    rel_date = data.get("release_date") or ""
                    year = int(rel_date[:4]) if len(rel_date) >= 4 and rel_date[:4].isdigit() else None
                    title = data.get("title") or original_title

                    with conn.cursor() as cur:
                        cur.execute("""
                            UPDATE tmdb_movies
                            SET original_title = %s,
                                poster_path = %s,
                                backdrop_path = %s,
                                overview = %s,
                                vote_average = %s,
                                year = %s,
                                status = 'synced',
                                updated_at = CURRENT_TIMESTAMP
                            WHERE id = %s;
                        """, (title, poster, backdrop, overview, rating, year, m_id))
                    conn.commit()
                    synced_count += 1
                    print(f"  [✓] Synced ({synced_count}/{len(movies)}): {title} ({year or 'TBA'})")
                except Exception as e:
                    print(f"  [!] Error film {m_id}: {e}")

        tasks = [fetch_and_save(m_id, title) for m_id, title in movies]
        await asyncio.gather(*tasks)

    conn.close()
    elapsed = time.time() - start_time
    print(f"\n[+] Selesai! Berhasil menyinkronkan {synced_count} film dalam {elapsed:.2f} detik.")


def main() -> None:
    load_env()
    api_key = os.environ.get("TMDB_API_KEY", "").strip()
    db_url = os.environ.get("DATABASE_URL", "").strip()

    if not api_key:
        print("[!] TMDB_API_KEY belum diatur di backend/.env")
        sys.exit(1)
    if not db_url:
        print("[!] DATABASE_URL belum diatur di backend/.env")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Sinkronkan poster dan info film dari TMDB ke Supabase.")
    parser.add_argument("--limit", type=int, default=30, help="Jumlah film yang disinkronkan (default: 30)")
    parser.add_argument("--concurrency", type=int, default=5, help="Jumlah request bersamaan (default: 5)")

    args = parser.parse_args()

    asyncio.run(sync_movie_details(
        db_url=db_url,
        api_key=api_key,
        limit=args.limit,
        concurrency=args.concurrency,
    ))


if __name__ == "__main__":
    main()
