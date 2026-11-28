"""Fase 4 del rediseño D: ofertas, gratis y lanzamientos de las tiendas (sin red: respuestas de ejemplo)."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import security, store_deals
from omnia.api import Api, ApiError
from omnia.store import Store

STEAM = {
    "specials": {"items": [
        {"id": 1091500, "type": 0, "name": "Cyberpunk 2077", "discounted": True, "discount_percent": 70,
         "original_price": 19900000, "final_price": 5970000, "currency": "COP", "linux_available": False,
         "discount_expiration": 1796950800,
         "large_capsule_image": "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1091500/c.jpg"},
        {"id": 42, "type": 0, "name": "Juego regalado", "discounted": True, "discount_percent": 100,
         "original_price": 990000, "final_price": 0, "currency": "COP",
         "large_capsule_image": "https://evil.example.com/x.jpg"},
        {"id": 7, "type": 2, "name": "Paquete", "discounted": True, "discount_percent": 10, "final_price": 1, "currency": "COP"},
    ]},
    "new_releases": {"items": [
        {"id": 1091500, "type": 0, "name": "Cyberpunk 2077 (repetido)", "final_price": 0, "currency": "COP"},
        {"id": 5545050, "type": 0, "name": "CLT Supermarket", "discounted": False, "discount_percent": 0,
         "original_price": None, "final_price": 1252000, "currency": "COP",
         "header_image": "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/5545050/h.jpg"},
    ]},
}
EPIC = {"data": {"Catalog": {"searchStore": {"elements": [
    {"title": "Bread and Fred", "productSlug": None,
     "catalogNs": {"mappings": [{"pageSlug": "bread-and-fred-1db362", "pageType": "productHome"}]},
     "keyImages": [{"type": "OfferImageWide", "url": "https://cdn1.epicgames.com/spt-assets/b/bread.jpg"}],
     "price": {"totalPrice": {"originalPrice": 3109900, "currencyCode": "COP", "currencyInfo": {"decimals": 2}}},
     "promotions": {"promotionalOffers": [{"promotionalOffers": [{"startDate": "2026-11-26T16:00:00.000Z",
        "endDate": "2026-12-03T16:00:00.000Z", "discountSetting": {"discountPercentage": 0}}]}], "upcomingPromotionalOffers": []}},
    {"title": "Strange Antiquities", "productSlug": "strange-antiquities/home",
     "keyImages": [{"type": "Thumbnail", "url": "https://cdn1.epicgames.com/spt-assets/s/strange.jpg"}],
     "promotions": {"promotionalOffers": [], "upcomingPromotionalOffers": [{"promotionalOffers": [
        {"startDate": "2026-12-03T16:00:00.000Z", "endDate": "2026-12-10T16:00:00.000Z", "discountSetting": {"discountPercentage": 0}}]}]}},
    {"title": "Solo descuento", "productSlug": "solo-descuento",
     "promotions": {"promotionalOffers": [{"promotionalOffers": [{"discountSetting": {"discountPercentage": 70}}]}]}},
    {"title": "Sin promoción", "productSlug": "nada", "promotions": None},
]}}}}
GOG = {"products": [
    {"title": "Heroes of Might and Magic 3", "storeLink": "https://www.gog.com/en/game/heroes_3",
     "coverHorizontal": "https://images.gog-statics.com/h3.png",
     "price": {"discount": "-76%", "finalMoney": {"amount": "0.99", "currency": "USD"}, "baseMoney": {"amount": "4.09"}}},
    {"title": "Regalo de GOG", "storeLink": "https://www.gog.com/en/game/gift",
     "price": {"discount": "-100%", "finalMoney": {"amount": "0.00"}, "baseMoney": {"amount": "9.99"}}},
    {"title": "Enlace raro", "storeLink": "http://phishing.example.com/x", "price": {"discount": "-50%"}},
]}


def fake_fetch(url):
    if "steampowered" in url:
        return json.dumps(STEAM).encode()
    if "epicgames" in url:
        return json.dumps(EPIC).encode()
    if "gog.com" in url:
        return json.dumps(GOG).encode()
    raise OSError("sin red en las pruebas")


class Readers(unittest.TestCase):
    def setUp(self):
        patcher = mock.patch.object(store_deals, "_fetch", side_effect=fake_fetch)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_steam_deals_free_and_releases(self):
        items = store_deals._steam("es")
        by_title = {i["title"]: i for i in items}
        deal = by_title["Cyberpunk 2077"]
        self.assertEqual((deal["kind"], deal["discount"], deal["priceValue"], deal["originalValue"], deal["currency"]),
                         ("deal", 70, 59700, 199000, "COP"))
        self.assertEqual(deal["url"], "https://store.steampowered.com/app/1091500/")
        self.assertTrue(deal["artwork"].startswith("https://shared.akamai.steamstatic.com/"))
        self.assertEqual(by_title["Juego regalado"]["kind"], "free")
        self.assertEqual(by_title["Juego regalado"]["artwork"], "")          # dominio de imagen no permitido
        self.assertNotIn("Paquete", by_title)                               # solo juegos (type 0)
        self.assertNotIn("Cyberpunk 2077 (repetido)", by_title)             # sin repetir entre secciones
        self.assertEqual(by_title["CLT Supermarket"]["kind"], "release")

    def test_epic_only_free_promotions(self):
        items = store_deals._epic("es")
        self.assertEqual([(i["title"], i["kind"]) for i in items],
                         [("Bread and Fred", "free"), ("Strange Antiquities", "upcoming")])
        self.assertEqual(items[0]["url"], "https://store.epicgames.com/es-ES/p/bread-and-fred-1db362")
        self.assertEqual(items[1]["url"], "https://store.epicgames.com/es-ES/p/strange-antiquities")
        self.assertGreater(items[0]["endsAt"], items[0]["startsAt"])
        self.assertEqual((items[0]["originalValue"], items[0]["currency"]), (31099, "COP"))

    def test_gog_deals_and_untrusted_links(self):
        items = store_deals._gog("es")
        self.assertEqual([(i["title"], i["kind"], i["discount"]) for i in items],
                         [("Heroes of Might and Magic 3", "deal", 76), ("Regalo de GOG", "free", 100)])
        self.assertEqual((items[0]["priceValue"], items[0]["originalValue"], items[0]["currency"]), (0.99, 4.09, "USD"))

    def test_each_store_is_asked_for_the_region_of_the_currency(self):
        urls = []
        with mock.patch.object(store_deals, "_fetch", side_effect=lambda url: urls.append(url) or fake_fetch(url)):
            store_deals._steam("es", "MXN")
            store_deals._epic("es", "MXN")
            store_deals._gog("es", "EUR")
            store_deals._gog("es", "COP")
        self.assertIn("cc=mx", urls[0])
        self.assertIn("country=MX", urls[1])
        self.assertIn("currencyCode=EUR", urls[2])
        self.assertIn("currencyCode=USD", urls[3])                 # GOG no vende en COP: se pide en USD y se convierte


class FakeRates:
    """Tipo de cambio fijo y sin red: 1 USD = 4000 COP = 20 MXN."""
    RATES = {"USD": 1, "COP": 4000, "MXN": 20}

    def __init__(self, empty=False):
        self.empty = empty

    def refresh(self, wait=False):
        pass

    def convert(self, value, source, target):
        if source == target:
            return value
        if self.empty or source not in self.RATES or target not in self.RATES:
            return None
        return value / self.RATES[source] * self.RATES[target]


class Cache(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def deals(self, readers, **kw):
        return store_deals.StoreDeals(readers=readers, cache_path=self.tmp / "d.json", rates=kw.get("rates") or FakeRates())

    def test_prices_in_the_chosen_currency_or_converted_with_a_mark(self):
        rows = {"steam": [{"source": "steam", "kind": "deal", "title": "a", "url": "", "priceValue": 59700, "originalValue": 199000, "currency": "COP"}],
                "gog": [{"source": "gog", "kind": "deal", "title": "b", "url": "", "priceValue": 0.99, "originalValue": 4.09, "currency": "USD"}],
                "epic": []}
        readers = {s: (lambda lang, money, s=s: [dict(r) for r in rows[s]]) for s in store_deals.SOURCES}
        out = self.deals(readers).snapshot("es", wait=True, money="COP")
        by = {i["title"]: i for i in out["items"]}
        self.assertEqual((by["a"]["price"], by["a"]["originalPrice"], by["a"]["approx"]), ("$ 59.700", "$ 199.000", False))
        self.assertEqual((by["b"]["price"], by["b"]["originalPrice"], by["b"]["approx"]), ("≈ $ 3.960", "≈ $ 16.360", True))
        self.assertEqual(out["currency"], "COP")
        self.assertNotIn("priceValue", by["a"])
        raw = self.deals(readers, rates=FakeRates(empty=True)).snapshot("en", wait=True, money="COP")
        self.assertEqual({i["title"]: i["price"] for i in raw["items"]}["b"], "US$ 0.99")   # sin tipo de cambio: el de la tienda

    def test_changing_currency_asks_the_stores_for_the_new_region(self):
        asked = []
        readers = {s: (lambda lang, money, s=s: asked.append((s, money)) or [{"source": s, "kind": "deal", "title": s, "url": ""}])
                   for s in store_deals.SOURCES}
        deals = self.deals(readers)
        deals.snapshot("es", stores={"steam"}, wait=True, money="COP")
        deals.snapshot("es", stores={"steam"}, wait=True, money="COP")
        deals.snapshot("es", stores={"steam"}, wait=True, money="MXN")
        self.assertEqual(asked, [("steam", "COP"), ("steam", "MXN")])

    def test_while_the_new_region_loads_the_previous_prices_are_shown_converted(self):
        gate = []
        readers = {s: (lambda lang, money, s=s: [] if gate else [{"source": s, "kind": "deal", "title": s, "url": "", "priceValue": 40000,
                                                                     "originalValue": 0, "currency": "COP"}]) for s in store_deals.SOURCES}
        deals = self.deals(readers)
        deals.snapshot("es", stores={"steam"}, wait=True, money="COP")
        gate.append(1)                                                    # la nueva región aún no trae nada
        out = deals.snapshot("es", stores={"steam"}, wait=True, money="MXN")
        self.assertEqual([i["price"] for i in out["items"]], ["≈ MX$ 200"])

    def test_snapshot_filters_stores_and_keeps_cache(self):
        calls = []
        readers = {s: (lambda lang, money, s=s: calls.append(s) or [{"source": s, "kind": "deal", "title": s, "url": "", "artwork": ""}])
                   for s in store_deals.SOURCES}
        deals = self.deals(readers)
        out = deals.snapshot("es", stores={"steam", "gog"}, wait=True)
        self.assertEqual(sorted(calls), ["gog", "steam"])
        self.assertEqual(sorted(i["source"] for i in out["items"]), ["gog", "steam"])
        self.assertGreater(out["updated"], 0)
        self.assertTrue((self.tmp / "d.json").exists())
        again = deals.snapshot("es", stores={"steam", "gog"}, wait=True)            # dentro de la caché: no vuelve a la red
        self.assertEqual(sorted(calls), ["gog", "steam"])
        self.assertEqual(len(again["items"]), 2)

    def test_a_failing_source_does_not_break_the_others(self):
        def broken(lang, money):
            raise OSError("caída")
        readers = {"steam": broken, "epic": lambda lang, money: [{"source": "epic", "kind": "free", "title": "x", "url": ""}], "gog": broken}
        out = self.deals(readers).snapshot("es", wait=True)
        self.assertEqual([i["source"] for i in out["items"]], ["epic"])


class NewsSetting(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=lambda: [])

    def test_all_stores_by_default_and_saved_in_order(self):
        self.assertEqual(self.api.settings({})["news_stores"], ["omnia", "steam", "epic", "gog", "amazon"])
        out = self.api.settings_news({"_body": {"stores": ["gog", "steam"]}})
        self.assertEqual(out["news_stores"], ["steam", "gog"])
        self.assertEqual(self.api.settings({})["news_stores"], ["steam", "gog"])

    def test_rejects_unknown_stores(self):
        for body in ({}, {"stores": "steam"}, {"stores": ["steam", "origin"]}, {"stores": [1]}):
            with self.assertRaises(ApiError):
                self.api.settings_news({"_body": body})

    def test_routes(self):
        self.assertIn("/stores/deals", self.api.routes)
        self.assertIn("/settings/news", self.api.routes)


if __name__ == "__main__":
    unittest.main()
