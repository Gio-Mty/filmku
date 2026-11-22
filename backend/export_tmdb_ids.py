"""Unduh semua ID film dari TMDB menggunakan Daily ID Export resmi.

TMDB menyediakan dump ID harian di:
https://files.tmdb.org/p/exports/movie_ids_MM_DD_YYYY.json.gz

Cara pakai:
    python export_tmdb_ids.py
    python export_tmdb_ids.py --format txt --output tmdb_ids.txt
    python export_tmdb_ids.py --format csv --exclude-adult --min-pop 1.0
"""

import argparse
import csv
from datetime import datetime, timezone, timedelta
import gzip
import io
import json
import sys
import time
import urllib.request
from pathlib import Path


BASE_URL = "https://files.tmdb.org/p/exports"


def find_latest_export_url(media_type: str = "movie") -> tuple[str, str]:
    """Cari URL ekspor terbaru (hari ini, kemarin, atau 2 hari lalu)."""
    now = datetime.now(timezone.utc)
    for day_offset in range(4):
        target_date = now - timedelta(days=day_offset)
        date_str = target_date.strftime("%m_%d_%Y")
        url = f"{BASE_URL}/{media_type}_ids_{date_str}.json.gz"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "filmku/1.0"})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    return url, date_str
        except Exception:
            continue
    raise RuntimeError("Tidak dapat menemukan file ekspor TMDB dalam 4 hari terakhir.")


def export_ids(
    output_path: Path,
    file_format: str = "csv",
    exclude_adult: bool = True,
    min_popularity: float = 0.0,
    limit: int | None = None,
) -> int:
    """Stream dan simpan ID film ke file tujuan."""
    url, date_str = find_latest_export_url("movie")
    print(f"[*] Mengambil data ekspor tanggal: {date_str}")
    print(f"[*] URL: {url}")
    print(f"[*] Filter: exclude_adult={exclude_adult}, min_popularity={min_popularity}")

    req = urllib.request.Request(url, headers={"User-Agent": "filmku/1.0"})
    
    start_time = time.time()
    total_scanned = 0
    total_saved = 0

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with urllib.request.urlopen(req) as response:
        with gzip.GzipFile(fileobj=response) as gz_stream:
            # Gunakan buffer text stream
            text_stream = io.TextIOWrapper(gz_stream, encoding="utf-8")
            
            with open(output_path, "w", encoding="utf-8", newline="") as out_file:
                csv_writer = None
                if file_format == "csv":
                    csv_writer = csv.writer(out_file)
                    csv_writer.writerow(["id", "original_title", "popularity", "adult", "video"])

                for line in text_stream:
                    line = line.strip()
                    if not line:
                        continue
                    
                    total_scanned += 1
                    try:
                        item = json.loads(line)
                    except json.JSONDecodeError:
                        continue

                    # Filter
                    if exclude_adult and item.get("adult", False):
                        continue
                    
                    pop = float(item.get("popularity", 0.0) or 0.0)
                    if pop < min_popularity:
                        continue

                    # Tulis ke file sesuai format
                    if file_format == "csv":
                        csv_writer.writerow([
                            item.get("id"),
                            item.get("original_title", ""),
                            pop,
                            item.get("adult", False),
                            item.get("video", False),
                        ])
                    elif file_format == "txt":
                        out_file.write(f"{item.get('id')}\n")
                    elif file_format == "jsonl":
                        out_file.write(f"{line}\n")

                    total_saved += 1

                    if total_scanned % 100_000 == 0:
                        elapsed = time.time() - start_time
                        print(f"    ... Dipindai: {total_scanned:,} | Disimpan: {total_saved:,} ({elapsed:.1f}s)")

                    if limit and total_saved >= limit:
                        print(f"[*] Mencapai batas limit: {limit}")
                        break

    elapsed = time.time() - start_time
    print(f"\n[+] Selesai dalam {elapsed:.2f} detik!")
    print(f"[+] Total film dipindai: {total_scanned:,}")
    print(f"[+] Total ID disimpan:   {total_saved:,}")
    print(f"[+] Disimpan di:          {output_path.resolve()}")
    return total_saved


def main() -> None:
    parser = argparse.ArgumentParser(description="Unduh seluruh ID film dari TMDB Daily ID Export.")
    parser.add_argument(
        "--format",
        choices=["csv", "txt", "jsonl"],
        default="csv",
        help="Format output file (default: csv)",
    )
    parser.add_argument(
        "--output",
        "-o",
        type=str,
        default=None,
        help="Path file output (default: tmdb_movie_ids.<format> di folder saat ini)",
    )
    parser.add_argument(
        "--include-adult",
        action="store_true",
        default=False,
        help="Sertakan film dewasa (default: False/hanya non-adult)",
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
        help="Batas maksimal ID yang diambil (untuk testing)",
    )

    args = parser.parse_args()

    output = args.output
    if not output:
        output = f"tmdb_movie_ids.{args.format}"

    export_ids(
        output_path=Path(output),
        file_format=args.format,
        exclude_adult=not args.include_adult,
        min_popularity=args.min_pop,
        limit=args.limit,
    )


if __name__ == "__main__":
    main()
