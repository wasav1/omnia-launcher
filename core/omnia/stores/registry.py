from .epic import Epic


def build(data_dir, runner=None):
    """Tiendas disponibles, por id. Cada una guarda su sesión bajo `data_dir`/stores."""
    return {s.id: s for s in (Epic(data_dir, runner=runner),)}
