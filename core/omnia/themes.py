"""Temas de color disponibles para la interfaz de Omnia."""

THEMES = (
    {"id": "blue", "name": "Azul Omnia", "accent": "#336599"},
    {"id": "slate", "name": "Gris azulado", "accent": "#91a9c2"},
    {"id": "teal", "name": "Verde petróleo", "accent": "#3f9f98"},
    {"id": "violet", "name": "Violeta", "accent": "#8872bd"},
    {"id": "amber", "name": "Ámbar", "accent": "#c28f4b"},
)

DEFAULT_THEME = "blue"
THEMES_BY_ID = {theme["id"]: theme for theme in THEMES}


def normalize_theme(value: object) -> str:
    """Devuelve un tema existente y seguro, usando Azul Omnia como valor inicial."""
    theme_id = value if isinstance(value, str) else ""
    return theme_id if theme_id in THEMES_BY_ID else DEFAULT_THEME


def accent_for(value: object) -> str:
    return THEMES_BY_ID[normalize_theme(value)]["accent"]
