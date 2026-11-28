from .amazon import Amazon
from .ea import Ea
from .epic import Epic
from .gog import Gog
from .steam import Steam
from .ubisoft import Ubisoft


def build(data_dir, runner=None):
    """Tiendas disponibles, por id. Cada una guarda su sesión bajo `data_dir`."""
    return {s.id: s for s in (Epic(data_dir, runner=runner), Gog(data_dir, runner=runner), Amazon(data_dir, runner=runner), Steam(data_dir),
                              Ubisoft(data_dir), Ea(data_dir))}
