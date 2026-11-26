# Omnia Game Suite

<img src="assets/branding/omnia-game-suite.svg" alt="Omnia Game Suite" width="360">

[Español](#español) · [English](#english) · [Releases](https://github.com/wasav1/omnia-launcher/releases)

## Español

**Omnia Game Suite** reúne tus juegos y ports de Linux en una biblioteca local que puedes abrir desde Desktop, Big Mode o el panel rápido de Dux.

La distribución actual está dirigida a **Hyprland en Arch Linux y derivados de 64 bits**, como CachyOS. La compatibilidad con **KDE Plasma** y **GNOME** está prevista para versiones futuras. **Windows** está en evaluación.

### Instalar o actualizar

1. Descarga el instalador único `Omnia-Game-Suite-<versión>-x86_64.run` desde [GitHub Releases](https://github.com/wasav1/omnia-launcher/releases).
2. Dale permiso de ejecución y ábrelo desde tu sesión de Hyprland. El asistente comprueba el entorno y detecta una instalación de Omnia anterior.
3. Elige tus carpetas y, si usas Dux, la integración del panel. Al terminar puedes conectar las cuentas de tiendas compatibles o hacerlo más tarde desde Ajustes.

Cuando haya otra versión disponible, **Actualizar** aparece en Desktop, Big Mode y el panel de Dux. Puedes seguir usando Omnia mientras se prepara. Al elegir **Reiniciar ahora**, el sistema puede pedirte que autorices la instalación. Omnia reinicia su servicio y sus ventanas después de aplicarla.

### Qué puedes hacer

- **Desktop:** explora los ports de Omnia y tus juegos de Steam, Epic, GOG y Amazon. Filtra por origen y sigue las instalaciones compatibles en Descargas.
- **Big Mode:** navega con mando, teclado o ratón. Continúa tu partida, recorre Biblioteca y Tienda, y gestiona tus cuentas. Incluye aviso al conectar un mando, bienvenida y cierre animados.
- **Panel rápido:** abre Omnia desde su icono en la barra de Dux, consulta tu biblioteca, revisa qué mando está conectado y su batería, o entra en Big Mode.
- **Juegos locales:** agrega ejecutables o ROMs que ya tengas. En **Cambiar arte**, busca por título, elige la edición y previsualiza portadas, fondos o logos antes de guardar.

La interfaz está disponible en español e inglés. El inicio de sesión depende de las herramientas de cada tienda. Omnia no solicita contraseñas de tiendas ni claves personales de SteamGridDB y no distribuye ROMs.

![Asistente de Omnia Game Suite detectando una instalación anterior](docs/screenshots/installer-guided.png)

## English

**Omnia Game Suite** brings Linux games and ports into one local library accessible from Desktop, Big Mode, or the Dux quick panel.

The current release targets **Hyprland on 64-bit Arch Linux and Arch-based distributions** such as CachyOS. **KDE Plasma** and **GNOME** support is planned for future versions. **Windows** support is being evaluated.

### Install or update

1. Download the single `Omnia-Game-Suite-<version>-x86_64.run` installer from [GitHub Releases](https://github.com/wasav1/omnia-launcher/releases).
2. Make it executable and open it from your Hyprland session. The installer checks the environment and detects previous Omnia installations.
3. Choose your folders and, if you use Dux, enable the quick panel integration. Connect supported store accounts at the end, or do it later in Settings.

When a new version is available, **Update** appears in Desktop, Big Mode, and the Dux panel. Keep using Omnia while the update is prepared. Choose **Restart now** and authorize installation if prompted. Omnia restarts its service and windows after applying the update.

### What you can do

- **Desktop:** browse Omnia ports and games from Steam, Epic, GOG, and Amazon. Filter by source and track supported installations in Downloads.
- **Big Mode:** browse with a controller, keyboard, or mouse. Continue playing, browse the Library and Store, and manage your accounts. It includes a controller connection prompt and animated opening and closing transitions.
- **Quick panel:** open Omnia from its icon in the Dux bar, browse your library, check the connected controller and its battery, or enter Big Mode.
- **Local games:** add executables or ROMs you already own. In **Change artwork**, search by title, choose an edition, and preview covers, backgrounds, or logos before saving.

The interface is available in English and Spanish. Sign-in depends on each store's tools. Omnia does not ask for store passwords or personal SteamGridDB keys and does not distribute ROMs.

## Desarrollo / Development

El núcleo local usa Python y las interfaces usan Qt Quick (QML). El catálogo y la búsqueda de arte se sirven desde [Omnia Backend](https://github.com/wasav1/omnia-backend).

The local service uses Python and the user interfaces use Qt Quick (QML). [Omnia Backend](https://github.com/wasav1/omnia-backend) provides the public catalog and artwork search.

[Licencia / License · GPL-3.0-or-later](LICENSE).
