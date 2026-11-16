#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include "settings.h"
#include "library_widgets.h"

class ConsentPage : public QWizardPage { public: using QWizardPage::registerField; };

class Installer : public QWizard {
    QString backend;
    QJsonObject initial;
    RouteList *folders;
    QComboBox *disks;
    KeyPanel *keyPanel;
    QCheckBox *consent;
    QPlainTextEdit *log;
    QLabel *summary, *result;
    QProcess *job = nullptr;
    bool running = false, completed = false;
    ConsentPage *page(const QString &title, const QString &subtitle) {
        auto p = new ConsentPage; p->setTitle(title); p->setSubTitle(subtitle);
        p->setLayout(new QVBoxLayout); addPage(p); return p;
    }
    void add(QWizardPage *p, QWidget *w) { p->layout()->addWidget(w); }
    QJsonObject settings() {
        QJsonArray roots; for(int i=0;i<folders->count();++i) roots.append(folders->item(i)->data(Qt::UserRole).toString());
        return {{"accepted",consent->isChecked()},{"external_roots",roots},{"selected_candidates",folders->selectedCandidates()},
                {"monitor_disk",disks->currentData().toJsonObject()}, {"steamgriddb_key",keyPanel->keyForSave()}};
    }
public:
    Installer(QString path, bool autoCheck=true): backend(path) {
        setWindowTitle("Omnia Desktop Suite — Instalador"); resize(820,640);
        setWizardStyle(QWizard::ModernStyle);
        setButtonText(NextButton,"Continuar"); setButtonText(BackButton,"Atrás");
        setButtonText(CancelButton,"Cancelar"); setButtonText(FinishButton,"Instalar");
        QProcess inspect; inspect.start("python3",{backend,"--inspect"});
        if(!inspect.waitForFinished(15000) || inspect.exitCode()!=0) {
            QMessageBox::critical(this,"Omnia","No se pudieron consultar los discos y la configuración.");
            QTimer::singleShot(0,this,&QWidget::close); return;
        }
        initial=QJsonDocument::fromJson(inspect.readAllStandardOutput()).object();
        QPixmap logo(initial["logo"].toString());
        if(!logo.isNull()) {setWindowIcon(QIcon(logo));setPixmap(QWizard::LogoPixmap,logo.scaled(115,85,Qt::KeepAspectRatio,Qt::SmoothTransformation));}
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
        add(welcome,notice);
        consent=new QCheckBox("He leído y acepto estos cambios en mi sesión de KDE Plasma.");
        welcome->registerField("consent*",consent); add(welcome,consent);
        auto libraries=page("Bibliotecas de juegos","Steam se detecta automáticamente. Añade todas tus carpetas externas.");
        QStringList libs; for(auto v:initial["steam_libraries"].toArray()) libs<<v.toString();
        auto steam=new QLabel(QString("Steam: %1 juegos detectados\n%2").arg(initial["steam_count"].toInt()).arg(libs.isEmpty()?"No se encontraron bibliotecas registradas. Abre Steam y configura su biblioteca.":libs.join("\n")));
        steam->setWordWrap(true); add(libraries,steam);
        folders=new RouteList(backend); for(auto v:initial["linked_roots"].toArray()) folders->addPath(v.toString()); add(libraries,folders);
        auto row=new QWidget; auto buttons=new QHBoxLayout(row);
        auto plus=new QPushButton("Añadir carpeta…"), minus=new QPushButton("Quitar seleccionada"); buttons->addWidget(plus); buttons->addWidget(minus); auto review=new QPushButton("Revisar candidatos…");buttons->addWidget(review);connect(review,&QPushButton::clicked,this,[this]{folders->reviewCandidates();}); add(libraries,row);
        connect(plus,&QPushButton::clicked,this,[this]{auto path=QFileDialog::getExistingDirectory(this,"Carpeta de ports o juegos externos",QDir::homePath()); if(!path.isEmpty()) folders->addPath(path);});
        connect(minus,&QPushButton::clicked,this,[this]{delete folders->takeItem(folders->currentRow());});
        auto note=new QLabel("Las ubicaciones estarán disponibles en el explorador de Omnia. Quitar una ruta excluye sus juegos del catálogo sin borrar archivos; añadirla de nuevo los recupera. Steam se administra por separado.");note->setWordWrap(true);add(libraries,note);
        auto monitor=page("Disco del monitor","El título usará la etiqueta real del volumen; si no tiene, el modelo y la partición.");
        disks=new QComboBox;
        for(auto v:initial["volumes"].toArray()) {auto d=v.toObject();disks->addItem(d["label"].toString()+" — "+d["path"].toString(),d);}
        auto saved=initial["config"].toObject()["monitor_disk"].toObject();
        for(int i=0;i<disks->count();++i) if(disks->itemData(i).toJsonObject()["uuid"]==saved["uuid"])disks->setCurrentIndex(i);
        add(monitor,disks); if(disks->count()==0) add(monitor,new QLabel("No hay volúmenes compatibles montados. Monta el disco y vuelve a abrir el asistente."));
        auto art=page("Arte de SteamGridDB","Configura la clave ahora o deja el campo vacío para conservar la existente.");
        keyPanel=new KeyPanel(backend,initial["key_exists"].toBool(),autoCheck);add(art,keyPanel);
        auto final=page("Revisar e instalar","La contraseña, si hace falta, la pedirá KDE. No la escribas en esta ventana.");
        summary=new QLabel;summary->setWordWrap(true);add(final,summary);
        result=new QLabel;result->setWordWrap(true);add(final,result);
        log=new QPlainTextEdit;log->setReadOnly(true);log->setMaximumBlockCount(1800);add(final,log);
        connect(this,&QWizard::currentIdChanged,this,[this](int id){if(id==4) summary->setText(QString("Steam: detección automática\nCarpetas externas: %1\nJuegos seleccionados para agregar: %4\nMonitor: %2\nSteamGridDB: %3\nSe reiniciará Plasma y se aplicará el layout.").arg(folders->count()).arg(disks->currentText()).arg(keyPanel->summary()).arg(folders->selectedCandidates().size()));});
    }
    bool validateCurrentPage() override {
        if(currentId()==3 && !keyPanel->ready()) {
            QMessageBox::information(this,"SteamGridDB","Valida la conexión o marca «Configurar SteamGridDB después» para continuar.");
            return false;
        }
        return QWizard::validateCurrentPage();
    }
    void accept() override {
        if(completed){QWizard::accept();return;} if(running)return;
        if(!consent->isChecked() || disks->currentIndex()<0)return;

        running=true;button(FinishButton)->setEnabled(false);button(BackButton)->setEnabled(false);button(CancelButton)->setEnabled(false);
        result->setText("Instalando… Puedes consultar los detalles abajo.");job=new QProcess(this);job->setProcessChannelMode(QProcess::MergedChannels);
        connect(job,&QProcess::readyReadStandardOutput,this,[this]{log->appendPlainText(QString::fromUtf8(job->readAllStandardOutput()));});
        connect(job,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this](int code,QProcess::ExitStatus status){
            running=false;completed=code==0 && status==QProcess::NormalExit;keyPanel->clearInput();
            result->setText(completed?"✓ Omnia se instaló. Revisa abajo si alguna integración requiere atención.":"La instalación no se completó. Revisa los detalles; puedes volver atrás y reintentar.");
            button(FinishButton)->setEnabled(true);button(CancelButton)->setEnabled(true);button(BackButton)->setEnabled(!completed);setButtonText(FinishButton,completed?"Cerrar":"Reintentar");
        });
        connect(job,&QProcess::errorOccurred,this,[this](QProcess::ProcessError e){if(e==QProcess::FailedToStart){running=false;result->setText("No se pudo iniciar el instalador.");button(FinishButton)->setEnabled(true);button(CancelButton)->setEnabled(true);button(BackButton)->setEnabled(true);}});
        job->start("python3",{backend,"--install"}); if(job->waitForStarted()){job->write(QJsonDocument(settings()).toJson(QJsonDocument::Compact));job->closeWriteChannel();}
    }
    void reject() override {if(!running)QWizard::reject();}
    void closeEvent(QCloseEvent *event) override {if(running)event->ignore();else QWizard::closeEvent(event);}
};
int main(int argc,char **argv){QApplication app(argc,argv);app.setApplicationName("Omnia Desktop Suite");if(argc<2)return 2;
if(argc>2 && QString::fromLocal8Bit(argv[2])=="--candidates-smoke") {
    QJsonArray items{QJsonObject{{"path","/juegos/port"},{"root","/juegos"},{"name","Port de ejemplo"},{"kind","executable"},{"files",QJsonArray{"/juegos/port/game.sh","/juegos/port/launcher"}},{"linked",false}},QJsonObject{{"path","/juegos/Mario.z64"},{"root","/juegos"},{"name","Mario"},{"kind","rom"},{"files",QJsonArray{"/juegos/Mario.z64"}},{"linked",true}}};
    CandidateReview dialog(QJsonObject{{"items",items}},{});dialog.show();
    QTimer::singleShot(200,&dialog,[&]{
        auto table=dialog.findChild<QTableWidget*>();
        if(table->item(0,0)->checkState()!=Qt::Unchecked){app.exit(21);return;}
        table->item(0,0)->setCheckState(Qt::Checked);
        static_cast<QComboBox*>(table->cellWidget(0,3))->setCurrentIndex(0);
        dialog.grab().save("/tmp/omnia-candidates.png");dialog.accept();
        app.exit(dialog.choices.size()==1?0:22);
    });return app.exec();
}
if(argc>2 && QString::fromLocal8Bit(argv[2]).startsWith("--settings")) {
SettingsWindow window(QString::fromLocal8Bit(argv[1]),QString::fromLocal8Bit(argv[2])!="--settings-smoke");window.show();
if(QString::fromLocal8Bit(argv[2])=="--settings-smoke") QTimer::singleShot(300,&window,[&]{
    auto tabs=window.findChild<QTabWidget*>();
    if(!tabs || tabs->count()!=5){app.exit(13);return;}
    window.grab().save("/tmp/omnia-settings.png"); app.exit(0);
});
return app.exec();}
Installer wizard(QString::fromLocal8Bit(argv[1]), !(argc>2 && QString::fromLocal8Bit(argv[2])=="--smoke"));wizard.show();
if(argc>2 && QString::fromLocal8Bit(argv[2])=="--smoke") {
    QTimer::singleShot(200,&wizard,[&]{
        if(wizard.button(QWizard::NextButton)->isEnabled()){app.exit(10);return;}
        auto check=wizard.findChild<QCheckBox*>();
        if(!check){app.exit(11);return;}
        wizard.grab().save("/tmp/omnia-installer-welcome.png");
        check->setChecked(true);
        for(auto box:wizard.findChildren<QCheckBox*>()) if(box->text().startsWith("Configurar SteamGridDB"))box->setChecked(true);
        for(int i=0;i<4;++i) wizard.next();
        if(wizard.currentId()!=4){app.exit(12);return;}
        wizard.grab().save("/tmp/omnia-installer-summary.png");
        app.exit(0);
    });
}
return app.exec();}
