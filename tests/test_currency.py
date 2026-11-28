"""Entrega 5: moneda de los precios (la elegida o la de la región del sistema), formato y tipo de cambio."""
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from omnia import currency, security
from omnia.api import Api, ApiError
from omnia.store import Store

ROOT = Path(__file__).resolve().parents[1]


class Detection(unittest.TestCase):
    def test_currency_from_the_system_region(self):
        self.assertEqual(currency.from_locale({"LANG": "es_CO.UTF-8"}), "COP")
        self.assertEqual(currency.from_locale({"LANG": "es_MX.UTF-8"}), "MXN")
        self.assertEqual(currency.from_locale({"LANG": "en_US.UTF-8"}), "USD")
        self.assertEqual(currency.from_locale({"LANG": "de_DE.UTF-8"}), "EUR")
        self.assertEqual(currency.from_locale({"LC_MONETARY": "es_AR.UTF-8", "LANG": "en_US.UTF-8"}), "ARS")
        self.assertEqual(currency.from_locale({"LANG": "C.UTF-8"}), "USD")

    def test_main_currencies_first(self):
        codes = [o["code"] for o in currency.options("es", extra=["ISK", "cop"])]
        self.assertEqual(codes[:3], ["COP", "MXN", "USD"])
        self.assertIn("ISK", codes)                       # cualquier moneda que traiga el tipo de cambio
        self.assertEqual(len(codes), len(set(codes)))


class Formatting(unittest.TestCase):
    def test_format(self):
        f = currency.format_money
        self.assertEqual(f(59700, "COP"), "$ 59.700")
        self.assertEqual(f(4.99, "USD"), "US$ 4,99")
        self.assertEqual(f(4.99, "USD", "en"), "US$ 4.99")
        self.assertEqual(f(399.5, "MXN"), "MX$ 399,50")
        self.assertEqual(f(3960.2, "COP", approx=True), "≈ $ 3.960")
        self.assertEqual(f(1234.56, "MXN", approx=True), "≈ MX$ 1.235")
        self.assertEqual(f(1199.0, "MXN"), "MX$ 1.199")                 # sin «,00» si el importe es entero
        self.assertEqual(f(0, "USD"), "")


class RatesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def test_downloads_once_a_day_and_falls_back_to_the_mirror(self):
        calls = []
        rates = {c: 1.0 for c in currency.CURRENCIES} | {"USD": 1, "COP": 4000.0, "MXN": 20.0}

        def fetch(url):
            calls.append(url)
            if "er-api" in url:
                raise OSError("caído")
            return json.dumps({"usd": {k.lower(): v for k, v in rates.items()}}).encode()
        r = currency.Rates(cache_path=self.tmp / "r.json", fetch=fetch)
        r.refresh(wait=True)
        self.assertAlmostEqual(r.convert(1, "USD", "COP"), 4000)
        self.assertAlmostEqual(r.convert(40, "MXN", "USD"), 2)
        self.assertEqual(len(calls), 2)
        r.refresh(wait=True)
        self.assertEqual(len(calls), 2)                      # dentro del día no vuelve a la red
        again = currency.Rates(cache_path=self.tmp / "r.json", fetch=fetch)
        self.assertAlmostEqual(again.convert(1, "USD", "COP"), 4000)     # queda en la caché

    def test_without_rates_there_is_no_conversion(self):
        r = currency.Rates(cache_path=self.tmp / "r.json", fetch=lambda url: (_ for _ in ()).throw(OSError("sin red")))
        r.refresh(wait=True)
        self.assertIsNone(r.convert(1, "USD", "COP"))
        self.assertEqual(r.convert(5, "USD", "USD"), 5)


class Setting(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.api = Api(Store(self.tmp / "cfg"), security.new_token(self.tmp / "run"), [], scan_fn=lambda: [])
        self.api.store_deals.rates.refresh = lambda wait=False: None          # sin red

    def test_automatic_by_default_then_chosen(self):
        with mock.patch.dict("os.environ", {"LANG": "es_MX.UTF-8", "LC_MONETARY": "", "LC_ALL": ""}):
            out = self.api.settings({})
            self.assertEqual((out["currency"], out["currency_auto"]), ("MXN", True))
            out = self.api.settings_currency({"_body": {"code": "USD"}})
            self.assertEqual((out["currency"], out["currency_auto"]), ("USD", False))
            self.assertEqual(self.api.settings({})["currency"], "USD")
            out = self.api.settings_currency({"_body": {"code": ""}})
            self.assertEqual((out["currency"], out["currency_auto"]), ("MXN", True))

    def test_rejects_bad_codes(self):
        for code in ("usd", "XYZ", 5, None, "DOLLAR"):
            with self.assertRaises(ApiError):
                self.api.settings_currency({"_body": {"code": code}})

    def test_deals_use_the_chosen_currency(self):
        self.api.settings_currency({"_body": {"code": "COP"}})
        with mock.patch.object(self.api.store_deals, "snapshot", return_value={"items": []}) as snap:
            self.api.stores_deals({"lang": "es"})
        self.assertEqual(snap.call_args.kwargs["money"], "COP")


class UiTests(unittest.TestCase):
    def test_both_apps_have_the_currency_setting(self):
        for name in ("ManagerSettings.qml", "OmniaBigSettings.qml"):
            self.assertIn("setCurrency(", (ROOT / "ui/qml" / name).read_text(), name)
        self.assertIn('"/settings/currency"', (ROOT / "ui/qml/Api.qml").read_text())


if __name__ == "__main__":
    unittest.main()
