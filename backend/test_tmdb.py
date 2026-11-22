"""Tes detail film TMDB: pemain, trailer, dan penyedia streaming resmi.

Jalankan dari folder backend: python -m unittest -v
"""

import unittest
from unittest.mock import AsyncMock, patch

import httpx

import main
from main import pick_trailer, to_cast, to_providers, to_tmdb_detail


def _video(key, name, type_="Trailer", lang="en", official=True, site="YouTube", published="2024-01-01T00:00:00.000Z"):
    """Satu entri `videos.results` dengan semua field yang dikirim TMDB."""
    return {
        "iso_639_1": lang,
        "iso_3166_1": "US",
        "name": name,
        "key": key,
        "site": site,
        "size": 1080,
        "type": type_,
        "official": official,
        "published_at": published,
        "id": f"v-{key}",
    }


def _person(id_, name, character, order, profile_path=None):
    """Satu entri `credits.cast` dengan semua field yang dikirim TMDB."""
    return {
        "adult": False,
        "gender": 1,
        "id": id_,
        "known_for_department": "Acting",
        "name": name,
        "original_name": name,
        "popularity": 5.0,
        "profile_path": profile_path,
        "cast_id": id_,
        "character": character,
        "credit_id": f"c-{id_}",
        "order": order,
    }


WATCH = {
    "id": 1022789,
    "results": {
        "US": {
            "link": "https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=US",
            "flatrate": [{"logo_path": "/us.png", "provider_id": 337, "provider_name": "Disney Plus", "display_priority": 1}],
        },
        "ID": {
            "link": "https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=ID",
            "buy": [{"logo_path": "/apple.png", "provider_id": 2, "provider_name": "Apple TV Store", "display_priority": 8}],
            "rent": [
                {"logo_path": "/play.png", "provider_id": 3, "provider_name": "Google Play Movies", "display_priority": 16},
                {"logo_path": "/apple.png", "provider_id": 2, "provider_name": "Apple TV Store", "display_priority": 8},
            ],
            "flatrate": [
                {"logo_path": "/ruMrSFMJBMUpzjUL3dHD647qyEF.png", "provider_id": 122, "provider_name": "Disney+", "display_priority": 4}
            ],
        },
    },
}

# Respons /movie/{id}?append_to_response=credits,videos,watch/providers (dipangkas).
DETAIL_DOC = {
    "adult": False,
    "backdrop_path": "/backdrop.jpg",
    "genres": [{"id": 16, "name": "Animasi"}, {"id": 10751, "name": "Keluarga"}],
    "id": 1022789,
    "original_title": "Inside Out 2",
    "overview": "Riley kini remaja.",
    "poster_path": "/poster.jpg",
    "release_date": "2024-06-11",
    "runtime": 97,
    "title": "Inside Out 2",
    "vote_average": 7.564,
    "credits": {
        "id": 1022789,
        "cast": [
            _person(2, "Maya Hawke", "Anxiety (voice)", 1, "/7oihORN6wlSC9qKULcpVq7Kqv1l.jpg"),
            _person(1, "Amy Poehler", "Joy (voice)", 0, "/rwmvRonpluV6dCPiQissYrchvSD.jpg"),
        ],
        "crew": [],
    },
    "videos": {
        "results": [
            _video("btsKey", "Global Phenomenon", type_="Featurette"),
            _video("officialKey", "Official Trailer", published="2024-03-07T14:00:00.000Z"),
        ]
    },
    "watch/providers": {"results": {"ID": WATCH["results"]["ID"]}},
}


class PickTrailerTest(unittest.TestCase):
    def test_trailer_resmi_utama_dipilih(self):
        # Urutan dan nama meniru daftar video Inside Out 2 di TMDB.
        videos = [
            _video("bts", "Animation Motivation", type_="Behind the Scenes", published="2026-03-24T17:01:30.000Z"),
            _video("teaser", "Teaser Trailer", published="2023-11-09T17:00:00.000Z"),
            _video("final", "Final Trailer", published="2024-06-04T13:00:00.000Z"),
            _video("official", "Official Trailer", published="2024-03-07T14:00:00.000Z"),
            _video("vimeo", "Official Trailer", site="Vimeo", published="2020-01-01T00:00:00.000Z"),
            _video("fan", "Trailer resmi buatan penggemar", lang="id", official=False, published="2020-01-01T00:00:00.000Z"),
        ]
        trailer = pick_trailer(videos)
        self.assertEqual(trailer.name, "Official Trailer")
        self.assertEqual(trailer.url, "https://www.youtube.com/watch?v=official")
        self.assertEqual(trailer.thumbnail, "https://i.ytimg.com/vi/official/hqdefault.jpg")

    def test_trailer_bahasa_indonesia_diutamakan(self):
        # Meniru The Odyssey: trailer resmi berbahasa Inggris dan versi Indonesia.
        videos = [
            _video("en1", "Official Trailer", published="2025-12-22T17:00:00.000Z"),
            _video("id1", "The Odyssey | Official New Trailer", lang="id", published="2026-05-05T03:00:00.000Z"),
        ]
        self.assertEqual(pick_trailer(videos).url, "https://www.youtube.com/watch?v=id1")

    def test_teaser_dipakai_bila_tidak_ada_trailer(self):
        videos = [_video("feat", "Featurette", type_="Featurette"), _video("teaser", "Official Teaser", type_="Teaser")]
        self.assertEqual(pick_trailer(videos).url, "https://www.youtube.com/watch?v=teaser")

    def test_tanpa_video_yang_bisa_dipakai(self):
        self.assertIsNone(pick_trailer(None))
        self.assertIsNone(pick_trailer([]))
        no_key = {"site": "YouTube", "type": "Trailer", "official": True, "name": "Trailer"}
        self.assertIsNone(pick_trailer([_video("clip", "Clip", type_="Clip"), no_key, "bukan dict"]))


class CastTest(unittest.TestCase):
    def test_pemain_urut_sesuai_order_dan_dibatasi(self):
        cast = [
            _person(3, "Pemeran Ketiga", "Teman", 2),
            _person(1, "Amy Poehler", "Joy (voice)", 0, "/rwmvRonpluV6dCPiQissYrchvSD.jpg"),
            _person(2, "Maya Hawke", "Anxiety (voice)", 1, "/7oihORN6wlSC9qKULcpVq7Kqv1l.jpg"),
            _person(9, "", "Tanpa nama", 3),
        ] + [_person(100 + i, f"Figuran {i}", "", 10 + i) for i in range(30)]
        result = to_cast({"id": 1022789, "cast": cast, "crew": []})

        self.assertEqual(len(result), 20)
        self.assertEqual(
            [(c.name, c.character, c.photo) for c in result[:3]],
            [
                ("Amy Poehler", "Joy (voice)", "https://image.tmdb.org/t/p/w185/rwmvRonpluV6dCPiQissYrchvSD.jpg"),
                ("Maya Hawke", "Anxiety (voice)", "https://image.tmdb.org/t/p/w185/7oihORN6wlSC9qKULcpVq7Kqv1l.jpg"),
                ("Pemeran Ketiga", "Teman", None),
            ],
        )
        # Entri tanpa nama dilewati.
        self.assertEqual(result[3].name, "Figuran 0")

    def test_tanpa_data_pemain(self):
        self.assertEqual(to_cast(None), [])
        self.assertEqual(to_cast({"cast": None}), [])


class ProvidersTest(unittest.TestCase):
    def test_penyedia_indonesia_urut_per_jenis(self):
        providers, link = to_providers(WATCH)
        self.assertEqual(
            [(p.kind, p.name) for p in providers],
            [("flatrate", "Disney+"), ("rent", "Apple TV Store"), ("rent", "Google Play Movies"), ("buy", "Apple TV Store")],
        )
        self.assertEqual(providers[0].logo, "https://image.tmdb.org/t/p/w92/ruMrSFMJBMUpzjUL3dHD647qyEF.png")
        self.assertEqual(link, "https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=ID")

    def test_belum_ada_di_indonesia(self):
        # Film yang masih tayang di bioskop belum punya data untuk ID.
        self.assertEqual(to_providers({"id": 1300968, "results": {"US": WATCH["results"]["US"]}}), ([], None))
        self.assertEqual(to_providers(None), ([], None))


class TmdbDetailTest(unittest.TestCase):
    def test_detail_menggabungkan_semua_bagian(self):
        detail = to_tmdb_detail(DETAIL_DOC)
        self.assertEqual(
            (detail.id, detail.title, detail.year, detail.genres, detail.rating),
            (1022789, "Inside Out 2", 2024, ["Animasi", "Keluarga"], 7.6),
        )
        self.assertEqual([c.name for c in detail.cast], ["Amy Poehler", "Maya Hawke"])
        self.assertEqual(detail.trailer.url, "https://www.youtube.com/watch?v=officialKey")
        self.assertEqual([(p.kind, p.name) for p in detail.providers][0], ("flatrate", "Disney+"))
        self.assertEqual(detail.watch_link, "https://www.themoviedb.org/movie/1022789-inside-out-2/watch?locale=ID")

    def test_detail_tanpa_tambahan(self):
        doc = {k: v for k, v in DETAIL_DOC.items() if k not in ("credits", "videos", "watch/providers")}
        detail = to_tmdb_detail(doc)
        self.assertEqual((detail.cast, detail.trailer, detail.providers, detail.watch_link), ([], None, [], None))



class TmdbEndpointTest(unittest.IsolatedAsyncioTestCase):
    async def test_endpoint_meminta_semua_bagian_sekaligus(self):
        fake = AsyncMock(return_value=DETAIL_DOC)
        transport = httpx.ASGITransport(app=main.app)
        with patch.object(main, "tmdb_get", fake):
            async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
                response = await client.get("/api/tmdb/movie/1022789")

        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(
            body["cast"][0],
            {"name": "Amy Poehler", "character": "Joy (voice)", "photo": "https://image.tmdb.org/t/p/w185/rwmvRonpluV6dCPiQissYrchvSD.jpg"},
        )
        self.assertEqual(body["providers"][0]["kind"], "flatrate")
        self.assertEqual(body["trailer"]["url"], "https://www.youtube.com/watch?v=officialKey")

        _, path, params = fake.call_args.args
        self.assertEqual(path, "/movie/1022789")
        self.assertEqual(set(params["append_to_response"].split(",")), {"credits", "videos", "watch/providers"})
        self.assertEqual(params["include_video_language"].split(","), ["id", "en", "null"])


if __name__ == "__main__":
    unittest.main()
