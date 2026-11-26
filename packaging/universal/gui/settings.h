#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include "library_widgets.h"
#include "appearance.h"

class SettingsWindow : public QDialog {
    QString backend;
    QJsonObject initial;
    RouteList *folders;
    RouteList *scanRoutes;
    VolumePicker *disks;
    QStackedWidget *librarySteps;
    QLabel *scanSummary;
    QComboBox *notificationPosition;
    QComboBox *themeChoice;
    QCheckBox *mangohud, *keepOmnia;
    QLabel *status;
    QPushButton *save;
    bool saving=false;
public:
    SettingsWindow(const QString &path,bool autoCheck=true) : backend(path) {
        setWindowTitle("Omnia Desktop Suite — Ajustes generales"); resize(1080,700); setMinimumSize(800,580);
        auto layout=new QVBoxLayout(this);
        QProcess inspect;inspect.start("python3",{backend,"--inspect"});
        if(!inspect.waitForFinished(15000)||inspect.exitCode()!=0){layout->addWidget(new QLabel("No se pudo consultar la configuración. Cierra y vuelve a intentar."));return;}
        initial=QJsonDocument::fromJson(inspect.readAllStandardOutput()).object();
        layout->setContentsMargins(22, 18, 22, 18);
        layout->setSpacing(14);
        const QPixmap logo(initial["logo"].toString());
        if (!logo.isNull()) setWindowIcon(QIcon(logo));
        layout->addWidget(omniaHeader("Ajustes", "settings", QColor("#b09cff"), logo));
        auto body = new QHBoxLayout;
        auto sidebar = new QVBoxLayout;
        auto caption = new QLabel("CONFIGURACIÓN");
        caption->setObjectName("RailCaption");
        sidebar->addWidget(caption);
        auto navigation = new QListWidget;
        navigation->setObjectName("SettingsNav");
        navigation->setFixedWidth(205);
        navigation->setAccessibleName("Secciones de ajustes");
        sidebar->addWidget(navigation, 1);
        body->addLayout(sidebar);
        auto tabs = new QTabWidget;
        tabs->tabBar()->hide();
        body->addWidget(tabs, 1);
        layout->addLayout(body, 1);
        auto addSection = [tabs, navigation](QWidget *page, const QString &title, const QString &icon) {
            auto content = new QWidget;
            auto column = new QVBoxLayout(content);
            column->setContentsMargins(16, 12, 16, 12);
            auto heading = new QLabel(title);
            heading->setObjectName("PageTitle");
            column->addWidget(heading);
            column->addWidget(page, 1);
            auto scroll = new QScrollArea;
            scroll->setWidgetResizable(true);
            scroll->setFrameShape(QFrame::NoFrame);
            scroll->setWidget(content);
            const auto glyph = lucideIcon(icon, QColor("#b09cff"));
            tabs->addTab(scroll, title);
            navigation->addItem(new QListWidgetItem(glyph, title));
        };
        connect(navigation, &QListWidget::currentRowChanged, tabs, &QTabWidget::setCurrentIndex);
        auto libraries=new QWidget;auto routes=new QVBoxLayout(libraries);librarySteps=new QStackedWidget;routes->addWidget(librarySteps);
        auto scanPage=new QWidget;auto scanLayout=new QVBoxLayout(scanPage);
        auto scanHelp=new QLabel("Paso 1 de 2 · Selecciona los discos que contienen juegos y escanéalos. Aquí verás los ports del catálogo Omnia y las ROM de N64 reconocidas; todavía no se vincula ni desvincula nada.");scanHelp->setWordWrap(true);scanLayout->addWidget(scanHelp);
        disks=new VolumePicker;auto cfg=initial["config"].toObject();QJsonArray monitorVolumes=cfg["monitor_disks"].toArray();if(monitorVolumes.isEmpty()&&!cfg["monitor_disk"].toObject().isEmpty())monitorVolumes.append(cfg["monitor_disk"].toObject());disks->populate(initial["volumes"].toArray(),monitorVolumes);scanLayout->addWidget(disks);
        auto scanDisks=new QPushButton(lucideIcon("search"), "Escanear discos seleccionados");scanLayout->addWidget(scanDisks);
        scanRoutes=new RouteList(backend);scanRoutes->setMaximumHeight(115);scanLayout->addWidget(scanRoutes);
        scanSummary=new QLabel("Selecciona discos y pulsa «Escanear» para ver los juegos reconocidos.");scanSummary->setWordWrap(true);scanLayout->addWidget(scanSummary);
        scanRoutes->scanFinished=[this]{scanSummary->setText(scanRoutes->knownGamesSummary());};
        auto continueToLinks=new QPushButton(lucideIcon("arrow-right"), "Continuar a carpetas y vínculos");scanLayout->addWidget(continueToLinks);librarySteps->addWidget(scanPage);
        auto linkPage=new QWidget;auto linkLayout=new QVBoxLayout(linkPage);
        auto help=new QLabel("Paso 2 de 2 · Agrega carpetas adicionales y revisa qué juegos vincular o desvincular. Quitar una ruta excluye sus juegos del catálogo sin borrar archivos, partidas ni historial.");help->setWordWrap(true);linkLayout->addWidget(help);
        folders=new RouteList(backend);
        for(auto p:initial["linked_roots"].toArray())folders->addPath(p.toString());
        linkLayout->addWidget(folders);auto selectionCounter=new QLabel;selectionCounter->setObjectName("CardTitle");folders->setCounterLabel(selectionCounter);linkLayout->addWidget(selectionCounter);auto buttons=new QHBoxLayout;auto backToScan=new QPushButton(lucideIcon("arrow-left"), "Volver al escáner"),add=new QPushButton(lucideIcon("folder-plus"), "Añadir carpeta…"),remove=new QPushButton(lucideIcon("minus"), "Quitar ruta");buttons->addWidget(backToScan);buttons->addWidget(add);buttons->addWidget(remove);auto review=new QPushButton(lucideIcon("layout-grid"), "Revisar candidatos…");buttons->addWidget(review);connect(review,&QPushButton::clicked,this,[this]{folders->reviewCandidates();});linkLayout->addLayout(buttons);librarySteps->addWidget(linkPage);
        connect(continueToLinks,&QPushButton::clicked,this,[this]{for(auto value:disks->checkedVolumes())folders->addPath(value.toObject()["path"].toString());librarySteps->setCurrentIndex(1);});connect(backToScan,&QPushButton::clicked,this,[this]{librarySteps->setCurrentIndex(0);});
        auto steam=new QLabel(QString("Steam: %1 juegos detectados automáticamente. Las rutas externas no modifican sus bibliotecas. Para desvincular una carpeta completa, selecciónala y pulsa Quitar ruta; los archivos y partidas se conservan.").arg(initial["steam_count"].toInt()));steam->setWordWrap(true);routes->addWidget(steam);addSection(libraries, "Juegos y discos", "hard-drive");
        connect(scanDisks,&QPushButton::clicked,this,[this]{QStringList paths;for(auto value:disks->checkedVolumes())paths<<value.toObject()["path"].toString();if(paths.isEmpty()){QMessageBox::information(this,"Escanear discos","Marca al menos un disco o partición.");return;}scanSummary->setText("Analizando los discos seleccionados…");scanRoutes->scanPaths(paths);});
        connect(add,&QPushButton::clicked,this,[this]{auto path=QFileDialog::getExistingDirectory(this,"Carpeta de juegos",QDir::homePath());if(!path.isEmpty())folders->addPath(path);});
        connect(remove,&QPushButton::clicked,this,[this]{if(folders->currentRow()<0)return;delete folders->takeItem(folders->currentRow());});
        auto monitor=new QWidget;auto diskLayout=new QVBoxLayout(monitor);
        mangohud=new QCheckBox("Mostrar estadísticas de componentes mientras juegas (MangoHud)");
        mangohud->setChecked(initial["config"].toObject().value("mangohud_enabled").toBool(true));
        mangohud->setEnabled(initial["mangohud_available"].toBool());
        diskLayout->addWidget(mangohud);
        auto note=new QLabel("MangoHud muestra FPS, frametime, temperaturas, RAM y VRAM; las etiquetas usan los nombres de modelo detectados. Los juegos de Steam requieren «MANGOHUD_CONFIGFILE=$HOME/.config/omnia/MangoHud.conf mangohud %command%» en sus Opciones de lanzamiento.");note->setWordWrap(true);diskLayout->addWidget(note);diskLayout->addStretch();addSection(monitor, "Monitor", "activity");
        auto desktop=new QWidget;auto desktopLayout=new QVBoxLayout(desktop);keepOmnia=new QCheckBox("Volver a aplicar el escritorio Omnia al iniciar sesión");keepOmnia->setChecked(cfg.value("keep_omnia_session").toBool(true));desktopLayout->addWidget(keepOmnia);auto desktopNote=new QLabel("Después de iniciar sesión, Omnia restaura su fondo animado y su widget en cada pantalla. Conserva el shell de Caelestia y otros widgets existentes.");desktopNote->setWordWrap(true);desktopLayout->addWidget(desktopNote);
        desktopLayout->addWidget(new QLabel("Tema de Omnia · color principal y tonos derivados:"));
        themeChoice=new QComboBox;
        for(const auto &value:initial["themes"].toArray()) {const auto item=value.toObject();themeChoice->addItem(QString("%1 · %2").arg(item["name"].toString(),item["accent"].toString()),item["id"].toString());}
        auto themeIndex=themeChoice->findData(cfg.value("theme").toString("blue"));themeChoice->setCurrentIndex(themeIndex<0?0:themeIndex);
        desktopLayout->addWidget(themeChoice);desktopLayout->addStretch();addSection(desktop, "Escritorio", "monitor");
        auto notifications=new QWidget;auto notificationLayout=new QVBoxLayout(notifications);
        notificationLayout->addWidget(new QLabel("Posición de los avisos temporales de Omnia:"));
        notificationPosition=new QComboBox;
        for(const auto &item:QList<QPair<QString,QString>>{{"Inferior derecha","bottom-right"},{"Inferior izquierda","bottom-left"},{"Superior derecha","top-right"},{"Superior izquierda","top-left"}})notificationPosition->addItem(item.first,item.second);
        auto currentPosition=initial["config"].toObject().value("notification_position").toString("bottom-right");
        auto positionIndex=notificationPosition->findData(currentPosition);notificationPosition->setCurrentIndex(positionIndex<0?0:positionIndex);
        notificationLayout->addWidget(notificationPosition);
        auto notificationHelp=new QLabel("Los avisos aparecen unos segundos y se desvanecen solos. Esta opción cambia su posición dentro del escritorio de Omnia.");notificationHelp->setWordWrap(true);notificationLayout->addWidget(notificationHelp);notificationLayout->addStretch();addSection(notifications, "Notificaciones", "bell");
        auto art=new QLabel("El catálogo de Omnia proporciona artwork publicado para los juegos compatibles. No se necesita una clave API personal.\n\nLas imágenes locales existentes permanecen en tu equipo.");art->setWordWrap(true);art->setMargin(20);addSection(art, "Imágenes", "image");
        auto about=new QLabel("Omnia Desktop Suite\nTu escritorio de juegos para KDE Plasma\n\nBiblioteca, wallpaper animado y monitor del sistema.\nLos ajustes se guardan en tu usuario.\nAplicar reinicia solo el núcleo de Omnia; no requiere contraseña ni reinstalar.");about->setWordWrap(true);about->setMargin(20);addSection(about, "Acerca de", "info");
        navigation->setCurrentRow(0);
        auto uninstall = new QPushButton(lucideIcon("trash-2", QColor("#f08b84")), "Desinstalar Omnia…");
        sidebar->addWidget(uninstall);
        connect(uninstall,&QPushButton::clicked,this,[this,path]{if(!saving)QProcess::startDetached(QCoreApplication::applicationFilePath(),{path,"--uninstall"});});
        status=new QLabel;status->setWordWrap(true);layout->addWidget(status);auto footer=new QHBoxLayout;footer->addStretch();auto close=new QPushButton(lucideIcon("x"), "Cerrar");save=new QPushButton(lucideIcon("check"), "Aplicar cambios");save->setProperty("primary",true);save->setProperty("mode","settings");footer->addWidget(close);footer->addWidget(save);layout->addLayout(footer);connect(close,&QPushButton::clicked,this,&QDialog::reject);
        connect(save,&QPushButton::clicked,this,[this]{
            QJsonArray roots;for(int i=0;i<folders->count();++i)roots.append(folders->item(i)->data(Qt::UserRole).toString());
            QJsonObject data{{"external_roots",roots},{"selected_candidates",folders->selectedCandidates()},{"monitor_disks",disks->checkedVolumes()},{"notification_position",notificationPosition->currentData().toString()},{"mangohud_enabled",mangohud->isChecked()},{"keep_omnia_session",keepOmnia->isChecked()},{"theme",themeChoice->currentData().toString()}};
            auto p=new QProcess(this);p->setProcessChannelMode(QProcess::MergedChannels);saving=true;save->setEnabled(false);status->setText("Guardando…");
            connect(p,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this,p](int code,QProcess::ExitStatus){saving=false;save->setEnabled(true);status->setText(QString::fromUtf8(p->readAllStandardOutput()));if(code==0||code==2){folders->clearSelections();}p->deleteLater();});
            p->start("python3",{backend,"--save-settings"});if(p->waitForStarted()){p->write(QJsonDocument(data).toJson(QJsonDocument::Compact));p->closeWriteChannel();}else{saving=false;save->setEnabled(true);status->setText("No se pudo guardar la configuración.");p->deleteLater();}
        });
    }
    void reject() override {if(!saving)QDialog::reject();}
    void closeEvent(QCloseEvent *e) override {if(saving)e->ignore();else QDialog::closeEvent(e);}
};
