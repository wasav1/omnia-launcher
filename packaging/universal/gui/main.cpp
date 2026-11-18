#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include "appearance.h"
#include "uninstall.h"
#include "settings.h"
#include "library_widgets.h"

class ConsentPage : public QWizardPage { public: using QWizardPage::registerField; };

class Installer : public QWizard {
    QString backend;
    QJsonObject initial;
    QPixmap brandIcon;
    RouteList *folders;
    RouteList *scanRoutes;
    VolumePicker *scanDisks;
    QLabel *scanSummary;
    KeyPanel *keyPanel;
    QCheckBox *consent;
    QCheckBox *logoutOnComplete, *keepOmnia;
    bool updateOnly = false;
    QPlainTextEdit *log;
    QLabel *summary, *result, *monitorDisksSummary;
    QProgressBar *progress;
    QPushButton *details;
    void updateSteps() {
        const int w = qMax(900, width());
        const qreal ratio = devicePixelRatioF();
        QPixmap banner(QSize(w, 88) * ratio); banner.setDevicePixelRatio(ratio); banner.fill(QColor("#191d25"));
        QPainter painter(&banner); painter.setRenderHint(QPainter::Antialiasing);
        QFont brand = font(); brand.setPixelSize(22); brand.setBold(true); brand.setLetterSpacing(QFont::AbsoluteSpacing, 2);
        painter.setRenderHint(QPainter::SmoothPixmapTransform);
        if(!brandIcon.isNull())painter.drawPixmap(QRect(25,20,48,48),brandIcon);
        painter.setFont(brand); painter.setPen(QColor("#f1f4fc")); painter.drawText(QRect(80, 20, 125, 30), "OMNIA");
        QFont caption = font(); caption.setPixelSize(10); caption.setLetterSpacing(QFont::AbsoluteSpacing, 1.4);
        painter.setFont(caption); painter.setPen(QColor("#92a0bc")); painter.drawText(QRect(81, 51, 125, 20), "DESKTOP SUITE");
        const QStringList steps = updateOnly
            ? QStringList{"Actualizar", "Confirmar"}
            : QStringList{"Inicio", "Escanear", "Vincular", "Sistema", "Imágenes", "Instalar"};
        const int stepWidth = (w - 225) / steps.size();
        for (int i = 0; i < steps.size(); ++i) {
            int x = 210 + i * stepWidth;
            const int pageId = updateOnly ? i + 4 : i;
            bool active = currentId() == pageId, done = currentId() > pageId || completed;
            if (active) { painter.setPen(Qt::NoPen); painter.setBrush(QColor("#29375d")); painter.drawRoundedRect(QRectF(x - 7, 23, stepWidth - 3, 40), 20, 20); }
            painter.setPen(Qt::NoPen); painter.setBrush(QColor(done ? "#285b50" : active ? "#5478f5" : "#303745"));
            painter.drawEllipse(QRectF(x, 31, 24, 24));
            QFont number = font(); number.setPixelSize(12); number.setBold(true); painter.setFont(number);
            painter.setPen(QColor(done ? "#9ee3c4" : "#ffffff")); painter.drawText(QRect(x,31,24,24), Qt::AlignCenter, done ? QString::fromUtf8("✓") : QString::number(i+1));
            QFont label = font(); label.setPixelSize(12); label.setBold(active); painter.setFont(label);
            painter.setPen(QColor(active || done ? "#eef2fc" : "#97a3bb")); painter.drawText(QRect(x+32, 29, stepWidth-35, 28), Qt::AlignVCenter, steps[i]);
        }
        setPixmap(QWizard::BannerPixmap, banner);
        for (auto which : {QWizard::NextButton, QWizard::FinishButton}) {
            auto action = button(which); action->setProperty("primary", true);
            action->style()->unpolish(action); action->style()->polish(action);
        }
    }
    QProcess *job = nullptr;
    bool running = false, completed = false;
    ConsentPage *page(const QString &title, const QString &subtitle) {
        auto p = new ConsentPage; p->setTitle(" "); p->setSubTitle(" ");
        auto layout = new QVBoxLayout(p); layout->setContentsMargins(24, 14, 24, 12); layout->setSpacing(13);
        auto heading = new QLabel(title); heading->setObjectName("PageTitle"); heading->setWordWrap(true); layout->addWidget(heading);
        auto description = new QLabel(subtitle); description->setObjectName("Subtitle"); description->setWordWrap(true); layout->addWidget(description);
        addPage(p); return p;
    }
    void add(QWizardPage *p, QWidget *w) { p->layout()->addWidget(w); }
    QJsonObject settings() {
        if (updateOnly)
            return {{"accepted", true}, {"update_only", true}, {"steamgriddb_key", keyPanel->keyForSave()}};
        QJsonArray roots; for(int i=0;i<folders->count();++i) roots.append(folders->item(i)->data(Qt::UserRole).toString());
        return {{"accepted",consent->isChecked()},{"external_roots",roots},{"selected_candidates",folders->selectedCandidates()},
                {"monitor_disks",scanDisks->checkedVolumes()}, {"keep_omnia_session",keepOmnia->isChecked()}, {"steamgriddb_key",keyPanel->keyForSave()}};
    }
public:
    bool isUpdateOnly() const { return updateOnly; }
    Installer(QString path, bool autoCheck=true): backend(path) {
        setWindowTitle("Omnia Desktop Suite — Instalador"); resize(1020,790); setMinimumSize(960,740);
        setWizardStyle(QWizard::ModernStyle);
        setOption(QWizard::NoBackButtonOnStartPage);
        setOption(QWizard::NoDefaultButton);
        button(NextButton)->setProperty("primary", true);
        button(FinishButton)->setProperty("primary", true);
        setButtonText(NextButton,"Continuar"); setButtonText(BackButton,"Atrás");
        setButtonText(CancelButton,"Cancelar"); setButtonText(FinishButton,"Instalar");
        QProcess inspect; inspect.start("python3",{backend,"--inspect"});
        if(!inspect.waitForFinished(15000) || inspect.exitCode()!=0) {
            QMessageBox::critical(this,"Omnia","No se pudieron consultar los discos y la configuración.");
            QTimer::singleShot(0,this,&QWidget::close); return;
        }
        initial=QJsonDocument::fromJson(inspect.readAllStandardOutput()).object();
        updateOnly=initial["installed"].toBool();
        QPixmap logo(initial["logo"].toString());brandIcon=logo;
        if(!logo.isNull()) {setWindowIcon(QIcon(logo));}
        auto welcome=page(initial["installed"].toBool()?"Actualizar Omnia Desktop Suite":"Bienvenido a Omnia Desktop Suite",initial["installed"].toBool()?"Instalación detectada: revisa las rutas vinculadas y la conexión existente.":"Tu escritorio de juegos para KDE Plasma 6");
        auto notice=new QTextBrowser;
        notice->setPlainText("Lee antes de continuar\n\n"
          "Este instalador instala o actualiza Omnia en tu usuario (~/.local), su wallpaper animado, el widget de biblioteca y sus servicios. Requiere KDE Plasma 6 con systemd de usuario.\n\n"
          "Compila un pequeño módulo de Qt para que Plasma acceda al token de sesión de Omnia. Si faltan herramientas o dependencias, el sistema pedirá autorización mediante el diálogo de KDE/Polkit y las instalará con el gestor de paquetes de tu distribución. Omnia no recibe ni guarda tu contraseña. La descarga de paquetes requiere conexión.\n\n"
          "Guardará las carpetas externas que selecciones, el volumen del monitor y, si la introduces, tu clave de SteamGridDB con permisos privados. Steam se detecta desde sus bibliotecas registradas. Los ports y emuladores se añaden después eligiendo su ejecutable o emulador; seleccionar una carpeta no determina cómo iniciar cada juego.\n\n"
          "El arte que falte se consulta en SteamGridDB usando nombres de juegos si has configurado la clave. Tus juegos y partidas permanecen en sus carpetas. La instalación conserva tu biblioteca y modifica solo su configuración de Omnia.\n\n"
          "Se activan los scripts de integración y Meta+D para mostrar Omnia, se guarda una copia de los ajustes anteriores y se retira el antiguo Big Menu devolviendo Meta al menú de Plasma. La integración de atajos puede revertirse con omnia-setup --undo.\n\n"
          "Al finalizar se reinicia plasmashell: escritorio y paneles desaparecerán unos segundos. Se aplica el wallpaper y el widget de biblioteca de Omnia en los escritorios disponibles; otros widgets y paneles permanecen. Omnia no cambia el tema, la paleta ni la decoración de ventanas de Plasma.\n\n"
          "Una instalación fallida puede dejar dependencias o archivos ya actualizados. Revisa el resultado y los detalles antes de reintentar.");
        auto cards = new QWidget; auto cardsLayout = new QHBoxLayout(cards); cardsLayout->setContentsMargins(0,0,0,0); cardsLayout->setSpacing(12);
        cardsLayout->addWidget(omniaCard("Tu biblioteca, reunida", "Steam, ports y emuladores en un mismo escritorio."));
        cardsLayout->addWidget(omniaCard("Un fondo para cada juego", "Arte de SteamGridDB y un fondo con movimiento."));
        add(welcome,cards);
        add(welcome,omniaCard("Antes de empezar", "Omnia se instala en tu usuario. Configura el fondo, el widget y los atajos de escritorio; al aplicar, Plasma se reiniciará unos segundos. Tus juegos y partidas permanecen en sus carpetas."));
        auto noticeToggle = new QPushButton("Ver todos los cambios de instalación"); noticeToggle->setCheckable(true);
        notice->setVisible(false); notice->setMaximumHeight(155);
        connect(noticeToggle, &QPushButton::toggled, notice, &QWidget::setVisible);
        add(welcome,noticeToggle); add(welcome,notice);
        static_cast<QVBoxLayout*>(welcome->layout())->addStretch();
        consent=new QCheckBox("He leído y acepto estos cambios en mi sesión de KDE Plasma.");
        welcome->registerField("consent*",consent); add(welcome,consent);
        auto scanPage=page("Escanear discos","Primero elige los discos que guardan tus juegos. Omnia mostrará los ports y juegos que puede reconocer; después podrás revisar qué vincular.");
        scanDisks=new VolumePicker;scanDisks->populate(initial["volumes"].toArray(),{});add(scanPage,omniaCard("Discos disponibles","Selecciona uno o varios discos o particiones. El escaneo solo lee archivos; todavía no agrega ni quita juegos."));add(scanPage,scanDisks);
        auto scanButton=new QPushButton("Escanear discos seleccionados");add(scanPage,scanButton);
        scanRoutes=new RouteList(backend);scanRoutes->setMaximumHeight(150);add(scanPage,scanRoutes);
        scanSummary=new QLabel("Selecciona discos y pulsa «Escanear» para ver los juegos reconocidos.");scanSummary->setObjectName("Muted");scanSummary->setWordWrap(true);add(scanPage,scanSummary);
        scanRoutes->scanFinished=[this]{scanSummary->setText(scanRoutes->knownGamesSummary());};
        connect(scanButton,&QPushButton::clicked,this,[this]{QStringList paths;for(auto value:scanDisks->checkedVolumes())paths<<value.toObject()["path"].toString();if(paths.isEmpty()){QMessageBox::information(this,"Escanear discos","Marca al menos un disco o partición.");return;}scanSummary->setText("Analizando los discos seleccionados…");scanRoutes->scanPaths(paths);});

        auto libraries=page("Carpetas y vinculación","Ahora agrega carpetas adicionales si hace falta y elige qué juegos deseas vincular o desvincular.");
        QStringList libs; for(auto v:initial["steam_libraries"].toArray()) libs<<v.toString();
        auto steam=new QLabel(QString("Steam: %1 juegos detectados\n%2").arg(initial["steam_count"].toInt()).arg(libs.isEmpty()?"No se encontraron bibliotecas registradas. Abre Steam y configura su biblioteca.":libs.join("\n")));
        steam->setWordWrap(true); steam->setObjectName("Muted");
        auto steamCard = omniaCard("Steam · detección automática", steam->text()); add(libraries,steamCard); delete steam;
        folders=new RouteList(backend); for(auto v:initial["linked_roots"].toArray()) folders->addPath(v.toString()); add(libraries,folders); folders->setMinimumHeight(160);
        auto selectionCounter=new QLabel;selectionCounter->setObjectName("CardTitle");folders->setCounterLabel(selectionCounter);add(libraries,selectionCounter);
        auto row=new QWidget; auto buttons=new QHBoxLayout(row);
        auto plus=new QPushButton("Añadir carpeta…"), minus=new QPushButton("Quitar seleccionada"); buttons->addWidget(plus); buttons->addWidget(minus); auto review=new QPushButton("Revisar candidatos…");buttons->addWidget(review);connect(review,&QPushButton::clicked,this,[this]{folders->reviewCandidates();}); add(libraries,row);
        connect(plus,&QPushButton::clicked,this,[this]{auto path=QFileDialog::getExistingDirectory(this,"Carpeta de ports o juegos externos",QDir::homePath()); if(!path.isEmpty()) folders->addPath(path);});
        connect(minus,&QPushButton::clicked,this,[this]{delete folders->takeItem(folders->currentRow());});
        connect(this,&QWizard::currentIdChanged,this,[this](int id){if(id==2)for(auto value:scanDisks->checkedVolumes())folders->addPath(value.toObject()["path"].toString());});
        auto note=new QLabel("Las ubicaciones estarán disponibles en el explorador de Omnia. Quitar una ruta excluye sus juegos del catálogo sin borrar archivos; añadirla de nuevo los recupera. Steam se administra por separado.");note->setWordWrap(true);add(libraries,note);
        auto monitor=page("Escritorio","Omnia usará en el monitor los discos que marcaste en el escáner. Decide si también debe restaurar el escritorio al iniciar sesión.");
        auto savedCfg=initial["config"].toObject();
        auto diskCard = omniaCard("Discos del monitor", "La selección se toma del paso Biblioteca → Escanear discos; vuelve atrás para cambiarla.");
        monitorDisksSummary=new QLabel;monitorDisksSummary->setObjectName("Muted");monitorDisksSummary->setWordWrap(true);diskCard->layout()->addWidget(monitorDisksSummary);add(monitor,diskCard);
        auto updateMonitorDisks=[this]{QStringList labels;for(auto value:scanDisks->checkedVolumes()){auto d=value.toObject();labels<<QString("%1 — %2").arg(d["label"].toString(),d["path"].toString());}monitorDisksSummary->setText(labels.isEmpty()?"No hay discos marcados en el escáner.":labels.join("\n"));};
        connect(scanDisks,&QListWidget::itemChanged,this,[updateMonitorDisks](QListWidgetItem*){updateMonitorDisks();});updateMonitorDisks();
        keepOmnia=new QCheckBox("Volver a aplicar el escritorio Omnia al iniciar sesión");keepOmnia->setChecked(savedCfg.value("keep_omnia_session").toBool(true));add(monitor,keepOmnia);
        auto keepNote=new QLabel("Omnia restaura su fondo animado y widget, conserva Caelestia y los demás widgets existentes.");keepNote->setObjectName("Muted");keepNote->setWordWrap(true);add(monitor,keepNote);
        static_cast<QVBoxLayout*>(monitor->layout())->addStretch();
        auto art=page(updateOnly?"Validar SteamGridDB":"Dale imagen a tu biblioteca",
                      updateOnly?"Confirma la clave de SteamGridDB para conservar las imágenes automáticas.":"Conecta SteamGridDB para descargar portadas, fondos y logos de tus juegos.");
        add(art,omniaCard(updateOnly?"Actualización rápida":"Tu clave permanece privada",
                          updateOnly?"Omnia ya está instalado. Se actualizarán sus archivos y se conservarán tus juegos y ajustes.":"Se guarda únicamente en tu usuario, con acceso restringido. Puedes conservar la clave existente o configurar las imágenes más adelante."));
        keyPanel=new KeyPanel(backend,initial["key_exists"].toBool(),autoCheck);add(art,keyPanel);
        static_cast<QVBoxLayout*>(art->layout())->addStretch();
        auto final=page(updateOnly?"Actualizar Omnia":"Revisar e instalar",updateOnly?"No se volverán a configurar las bibliotecas ni el disco del monitor.":"La contraseña, si hace falta, la pedirá KDE. No la escribas en esta ventana.");
        auto summaryCard = omniaCard(updateOnly?"Se conservarán tus datos":"Tu configuración", updateOnly?"La biblioteca, los juegos y los ajustes personales quedarán intactos.":"Revisa estas opciones antes de aplicar Omnia a tu escritorio.");
        summary=new QLabel;summary->setMinimumHeight(155);summary->setWordWrap(true); summary->setTextFormat(Qt::RichText); summaryCard->layout()->addWidget(summary); add(final,summaryCard);
        result=new QLabel(updateOnly?"Todo listo. Pulsa Actualizar para comenzar.":"Todo listo. Pulsa Instalar para comenzar.");result->setObjectName("Result");result->setWordWrap(true);add(final,result);
        logoutOnComplete=new QCheckBox("Cerrar sesión automáticamente al terminar");
        logoutOnComplete->setToolTip("Omnia quedará completamente cargado al iniciar sesión de nuevo. Guarda tu trabajo antes de continuar.");
        add(final,logoutOnComplete);
        progress=new QProgressBar; progress->setTextVisible(false); progress->setRange(0,1); progress->setValue(0); add(final,progress);
        details=new QPushButton("Mostrar detalles de instalación"); details->setCheckable(true); add(final,details);
        log=new QPlainTextEdit;log->setReadOnly(true);log->setMaximumBlockCount(1800);log->setVisible(false); log->setMinimumHeight(110); add(final,log);
        connect(details,&QPushButton::toggled,this,[this](bool open){log->setVisible(open);details->setText(open?"Ocultar detalles de instalación":"Mostrar detalles de instalación");});
        static_cast<QVBoxLayout*>(final->layout())->addStretch();
        connect(this,&QWizard::currentIdChanged,this,[this](int id){
            updateSteps();
            if(id==5) {QStringList labels;for(auto value:scanDisks->checkedVolumes())labels<<value.toObject()["label"].toString();QString monitorSummary=labels.isEmpty()?"No se seleccionaron discos":labels.join(", ");summary->setText(updateOnly
                ? QString("<table cellspacing='9'><tr><td><b>Omnia</b></td><td>Archivos de la aplicación</td></tr><tr><td><b>Biblioteca</b></td><td>Se conserva</td></tr><tr><td><b>Ajustes</b></td><td>Se conservan</td></tr><tr><td><b>SteamGridDB</b></td><td>%1</td></tr></table>").arg(keyPanel->summary().toHtmlEscaped())
                : QString("<table cellspacing='9'><tr><td><b>Bibliotecas</b></td><td>Steam + %1 carpetas externas</td></tr><tr><td><b>Selección</b></td><td>%2 juegos para agregar</td></tr><tr><td><b>Monitor</b></td><td>%3</td></tr><tr><td><b>Imágenes</b></td><td>%4</td></tr></table>")
                .arg(folders->count()).arg(folders->selectedGameCount()).arg(monitorSummary.toHtmlEscaped()).arg(keyPanel->summary().toHtmlEscaped()));}
            if(updateOnly && id==4) button(BackButton)->setEnabled(false);
        });
        if(updateOnly) { setStartId(4); setButtonText(FinishButton,"Actualizar"); }
        updateSteps();
    }
    bool validateCurrentPage() override {
        if(currentId()==4 && !keyPanel->ready()) {
            QMessageBox::information(this,"SteamGridDB","Valida la conexión o marca «Configurar SteamGridDB después» para continuar.");
            return false;
        }
        return QWizard::validateCurrentPage();
    }
    void accept() override {
        if(completed){QWizard::accept();return;} if(running)return;
        if(!updateOnly && !consent->isChecked())return;

        logoutOnComplete->setEnabled(false);
        running=true;button(FinishButton)->setEnabled(false);button(BackButton)->setEnabled(false);button(CancelButton)->setEnabled(false);
        progress->setRange(0,0); result->setText("Preparando Omnia… Puedes consultar los detalles de instalación.");job=new QProcess(this);job->setProcessChannelMode(QProcess::MergedChannels);
        connect(job,&QProcess::readyReadStandardOutput,this,[this]{log->appendPlainText(QString::fromUtf8(job->readAllStandardOutput()));});
        connect(job,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus status){
            running=false;completed=code==0 && status==QProcess::NormalExit;
            // Un fallo anterior a configure() no guardó la clave. Consérvala
            // en memoria para que Reintentar envíe la misma configuración.
            if(completed) keyPanel->clearInput();
            progress->setRange(0,1); progress->setValue(completed?1:0);
            if(!completed) details->setChecked(true);
            if(!completed) logoutOnComplete->setEnabled(true);
            updateSteps();
            result->setText(completed?(updateOnly?"✓ Omnia se actualizó. Cierra sesión y vuelve a entrar para cargar los cambios.":"✓ Omnia se instaló. Para que el fondo y las integraciones se carguen correctamente, cierra sesión y vuelve a entrar. Revisa abajo si alguna integración requiere atención."):"La instalación no se completó. Revisa los detalles; puedes volver atrás y reintentar.");
            button(FinishButton)->setEnabled(true);button(CancelButton)->setEnabled(true);button(BackButton)->setEnabled(!completed && !updateOnly);setButtonText(FinishButton,completed?"Cerrar":"Reintentar");
            if(completed && logoutOnComplete->isChecked()) {
                result->setText(updateOnly?"✓ Omnia se actualizó. La sesión se cerrará en unos segundos; guarda tu trabajo.":"✓ Omnia se instaló. La sesión se cerrará en unos segundos; guarda tu trabajo.");
                button(CancelButton)->setEnabled(false);button(FinishButton)->setEnabled(false);
                QTimer::singleShot(2500,this,[this]{
                    // qdbus6 no existe en Fedora/Bazzite: allí el binario se llama qdbus-qt6.
                    bool launched=false;
                    for(const QString &tool:{"qdbus6","qdbus-qt6","qdbus"}) {
                        if(QProcess::startDetached(tool,{"org.kde.Shutdown","/Shutdown","org.kde.Shutdown.logout"})) { launched=true; break; }
                    }
                    if(!launched) {
                        result->setText("Omnia se instaló, pero no se pudo cerrar la sesión automáticamente. Ciérrala desde el menú de KDE para completar los cambios.");
                        button(FinishButton)->setEnabled(true);
                    }
                });
            }
        });
        connect(job,&QProcess::errorOccurred,this,[this](QProcess::ProcessError e){if(e==QProcess::FailedToStart){running=false;progress->setRange(0,1);progress->setValue(0);result->setText("No se pudo iniciar el instalador.");button(FinishButton)->setEnabled(true);button(CancelButton)->setEnabled(true);button(BackButton)->setEnabled(true);}});
        job->start("python3",{backend,"--install"}); if(job->waitForStarted()){job->write(QJsonDocument(settings()).toJson(QJsonDocument::Compact));job->closeWriteChannel();}
    }
    void resizeEvent(QResizeEvent *event) override { QWizard::resizeEvent(event); updateSteps(); }
    void reject() override {if(!running)QWizard::reject();}
    void closeEvent(QCloseEvent *event) override {if(running)event->ignore();else QWizard::closeEvent(event);}
};
// Qt ya está cargado al crear QApplication. Los procesos hijos deben usar las
// bibliotecas del sistema, no las del AppImage (Python, CMake, Polkit y el servicio).
inline void restoreHostEnvironment() {
    if(qgetenv("OMNIA_APPIMAGE_BUNDLE")!="1")return;
    for(const auto &name:{"LD_LIBRARY_PATH","LD_PRELOAD","QT_PLUGIN_PATH","QT_QPA_PLATFORM_PLUGIN_PATH","QT_QPA_PLATFORMTHEME","QT_STYLE_OVERRIDE"}){
        QByteArray flag="OMNIA_HOST_SET_"+QByteArray(name),value="OMNIA_HOST_"+QByteArray(name);
        if(qgetenv(flag.constData())=="1")qputenv(name,qgetenv(value.constData()));else qunsetenv(name);
        qunsetenv(flag.constData());qunsetenv(value.constData());
    }
    qunsetenv("OMNIA_APPIMAGE_BUNDLE");
}
int main(int argc,char **argv){QApplication app(argc,argv);restoreHostEnvironment();applyOmniaAppearance(app);app.setApplicationName("Omnia Desktop Suite");if(argc<2)return 2;
if(argc>2 && QString::fromLocal8Bit(argv[2]).startsWith("--uninstall")) {
    UninstallWindow window(QString::fromLocal8Bit(argv[1]));window.show();
    if(QString::fromLocal8Bit(argv[2])=="--uninstall-smoke")QTimer::singleShot(200,&window,[&]{window.grab().save("/tmp/omnia-uninstall.png");app.exit(0);});
    return app.exec();
}
if(argc>2 && QString::fromLocal8Bit(argv[2])=="--candidates-smoke") {
    QJsonArray items;
    for (auto port : {"Longshot", "NX2navi"}) items.append(QJsonObject{
        {"path",QString("/juegos/Ocarina/Ports/")+port},{"root","/juegos"},
        {"name","The Legend of Zelda: Ocarina of Time"},{"kind","port"},
        {"game_key","sw2:ocarina"},{"port_name",port},{"platform","sw2"},
        {"files",QJsonArray{QString("/juegos/Ocarina/Ports/")+port+(QString(port)=="Longshot"?"/longshot":"/play.sh")}}, {"linked",false}});
    items.append(QJsonObject{{"path","/juegos/Mario.z64"},{"root","/juegos"},{"name","Super Mario 64"},{"kind","rom"},{"files",QJsonArray{"/juegos/Mario.z64"}},{"linked",true}});
    CandidateReview dialog(QJsonObject{{"items",items}},{});dialog.show();
    QTimer::singleShot(200,&dialog,[&]{
        auto table=dialog.findChild<QTableWidget*>();
        if(table->item(0,0)->checkState()!=Qt::Unchecked){app.exit(21);return;}
        table->item(0,0)->setCheckState(Qt::Checked);table->item(1,0)->setCheckState(Qt::Checked);
        static_cast<QComboBox*>(table->cellWidget(0,3))->setCurrentIndex(0);
        dialog.grab().save("/tmp/omnia-candidates.png");dialog.accept();
        app.exit(dialog.choices.size()==2?0:22);
    });return app.exec();
}
if(argc>2 && QString::fromLocal8Bit(argv[2]).startsWith("--settings")) {
SettingsWindow window(QString::fromLocal8Bit(argv[1]),QString::fromLocal8Bit(argv[2])!="--settings-smoke");window.show();
if(QString::fromLocal8Bit(argv[2])=="--settings-smoke") QTimer::singleShot(300,&window,[&]{
    auto tabs=window.findChild<QTabWidget*>();
    if(!tabs || tabs->count()!=4){app.exit(13);return;}
    window.grab().save("/tmp/omnia-settings.png"); app.exit(0);
});
return app.exec();}
Installer wizard(QString::fromLocal8Bit(argv[1]), !(argc>2 && QString::fromLocal8Bit(argv[2])=="--smoke"));wizard.show();
if(argc>2 && QString::fromLocal8Bit(argv[2])=="--smoke") {
    QTimer::singleShot(200,&wizard,[&]{
        if(wizard.isUpdateOnly()) {
            for(auto box:wizard.findChildren<QCheckBox*>()) if(box->text().startsWith("Configurar SteamGridDB"))box->setChecked(true);
            wizard.grab().save("/tmp/omnia-installer-update-key.png");
            wizard.next(); QApplication::processEvents();
            if(wizard.currentId()!=5){app.exit(12);return;}
            wizard.grab().save("/tmp/omnia-installer-summary.png"); app.exit(0); return;
        }
        if(wizard.button(QWizard::NextButton)->isEnabled()){app.exit(10);return;}
        auto check=wizard.findChild<QCheckBox*>();
        if(!check){app.exit(11);return;}
        wizard.grab().save("/tmp/omnia-installer-welcome.png");
        check->setChecked(true);
        for(auto box:wizard.findChildren<QCheckBox*>()) if(box->text().startsWith("Configurar SteamGridDB"))box->setChecked(true);
        for(int i=0;i<5;++i) {
            wizard.next();
            QApplication::processEvents();
            wizard.grab().save(QString("/tmp/omnia-installer-step-%1.png").arg(i+1));
        }
        if(wizard.currentId()!=5){app.exit(12);return;}
        wizard.grab().save("/tmp/omnia-installer-summary.png");
        app.exit(0);
    });
}
return app.exec();}
