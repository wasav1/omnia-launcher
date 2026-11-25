import gzip
import io
import unittest
from unittest.mock import patch

from omnia import store_news


class StoreNewsTests(unittest.TestCase):
    def test_gog_gzip_and_localized_release_keep_the_article_art(self):
        rss = gzip.compress(b"""<rss><channel><item><title>Coming soon: Example</title>
            <link>https://www.gog.com/en/news/example</link></item></channel></rss>""")
        opener = unittest.mock.Mock()
        opener.open.return_value = io.BytesIO(rss)
        with patch.object(store_news, "build_opener", return_value=opener):
            decoded = store_news._fetch("https://www.gog.com/en/frontpage/rss")
        page = b'<html lang="en"><meta property="og:image" content="https://images.gog-statics.com/article.jpg">'
        with patch.object(store_news, "_fetch", side_effect=[decoded, page]):
            item, = store_news._public_news("gog", "es")
        self.assertEqual(item["title"], "Próximamente: Example")
        self.assertEqual(item["originalLanguage"], "es")
        self.assertEqual(item["artwork"], "https://images.gog-statics.com/article.jpg")

    def test_steam_localized_chrome_does_not_replace_article_title(self):
        entry = {"url": "https://steamcommunity.com/games/1/announcements/detail/2",
                 "title": "Update 1.2", "originalLanguage": "en"}
        page = b'<html lang="es"><meta property="og:title" content="Steam :: Example :: Eventos">'
        with patch.object(store_news, "_fetch", return_value=page):
            store_news._enrich(entry, "es")
        self.assertEqual(entry["title"], "Update 1.2")
        self.assertEqual(entry["originalLanguage"], "en")
