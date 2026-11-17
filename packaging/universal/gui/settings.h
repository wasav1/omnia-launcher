#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include "library_widgets.h"

class SettingsWindow : public QDialog {
    QString backend;
    QJsonObject initial;
    RouteList *folders;
    QComboBox *disks;
    KeyPanel *keyPanel;
    QCheckBox *clearKey;
    QLabel *status;
    QPushButton *save;
    bool saving=false;
public:
    SettingsWindow(const QString &path,bool autoCheck=true) : backend(path) {
        setWindowTitle("Omnia Desktop Suite — Ajustes generales"); resize(760,590);
        auto layout=new QVBoxLayout(this);
        QProcess inspect;inspect.start("python3",{backend,"--inspect"});
        if(!inspect.waitForFinished(15000)||inspect.exitCode()!=0){layout->addWidget(new QLabel("No se pudo consultar la configuración. Cierra y vuelve a intentar."));return;}
        initial=QJsonDocument::fromJson(inspect.readAllStandardOutput()).object();
        auto brand=new QLabel;QPixmap logo(initial["logo"].toString());
        if(!logo.isNull()){setWindowIcon(QIcon(logo));brand->setPixmap(logo.scaled(150,105,Qt::KeepAspectRatio,Qt::SmoothTransformation));}
        else brand->setText("OMNIA");
        layout->addWidget(brand);
        auto tabs=new QTabWidget;layout->addWidget(tabs);
        auto libraries=new QWidget;auto routes=new QVBoxLayout(libraries);
        auto help=new QLabel("Añade ubicaciones de ports y emuladores. Quitar una ruta excluye sus juegos del catálogo sin borrar sus archivos, partidas ni historial. Volver a añadirla recupera sus entradas.");help->setWordWrap(true);routes->addWidget(help);
        folders=new RouteList(backend);
        for(auto p:initial["linked_roots"].toArray())folders->addPath(p.toString());
        routes->addWidget(folders);auto selectionCounter=new QLabel;selectionCounter->setObjectName("CardTitle");folders->setCounterLabel(selectionCounter);routes->addWidget(selectionCounter);auto buttons=new QHBoxLayout;auto add=new QPushButton("Añadir carpeta…"),remove=new QPushButton("Quitar ruta");buttons->addWidget(add);buttons->addWidget(remove);auto review=new QPushButton("Revisar candidatos…");buttons->addWidget(review);connect(review,&QPushButton::clicked,this,[this]{folders->reviewCandidates();});routes->addLayout(buttons);
        auto steam=new QLabel(QString("Steam: %1 juegos detectados automáticamente. Las rutas externas no modifican sus bibliotecas.").arg(initial["steam_count"].toInt()));steam->setWordWrap(true);routes->addWidget(steam);tabs->addTab(libraries,"Bibliotecas");
        connect(add,&QPushButton::clicked,this,[this]{auto path=QFileDialog::getExistingDirectory(this,"Carpeta de juegos",QDir::homePath());if(!path.isEmpty())folders->addPath(path);});
        connect(remove,&QPushButton::clicked,this,[this]{if(folders->currentRow()<0)return;delete folders->takeItem(folders->currentRow());});
        auto monitor=new QWidget;auto diskLayout=new QVBoxLayout(monitor);diskLayout->addWidget(new QLabel("Volumen que muestra el monitor de Omnia:"));disks=new QComboBox;
        auto saved=initial["config"].toObject()["monitor_disk"].toObject();bool found=false;
        for(auto value:initial["volumes"].toArray()) {auto d=value.toObject();disks->addItem(d["label"].toString()+" — "+d["path"].toString(),d);if(d["uuid"]==saved["uuid"]&&d["path"]==saved["path"]){disks->setCurrentIndex(disks->count()-1);found=true;}}
        if(!saved.isEmpty()&&!found){disks->addItem(saved["label"].toString()+" (no conectado)",saved);disks->setCurrentIndex(disks->count()-1);}
        diskLayout->addWidget(disks);auto note=new QLabel("Se usa la etiqueta real del volumen. Si no tiene etiqueta, se muestra el modelo y la partición. Puedes conservar un disco desconectado.");note->setWordWrap(true);diskLayout->addWidget(note);diskLayout->addStretch();tabs->addTab(monitor,"Monitor");
        auto art=new QWidget;auto artLayout=new QVBoxLayout(art);
        keyPanel=new KeyPanel(backend,initial["key_exists"].toBool(),autoCheck);artLayout->addWidget(keyPanel);
        clearKey=new QCheckBox("Eliminar la clave guardada al aplicar");artLayout->addWidget(clearKey);artLayout->addStretch();tabs->addTab(art,"SteamGridDB");
        connect(clearKey,&QCheckBox::toggled,this,[this](bool on){keyPanel->setEnabled(!on);});
        auto about=new QLabel("Omnia Desktop Suite\nTu escritorio de juegos para KDE Plasma\n\nBiblioteca, wallpaper animado y monitor del sistema.\nLos ajustes se guardan en tu usuario.\nAplicar reinicia solo el núcleo de Omnia; no requiere contraseña ni reinstalar.");about->setWordWrap(true);about->setMargin(20);tabs->addTab(about,"Acerca de");
        auto uninstall=new QPushButton("Desinstalar Omnia…");layout->addWidget(uninstall);
        connect(uninstall,&QPushButton::clicked,this,[this,path]{if(!saving)QProcess::startDetached(QCoreApplication::applicationFilePath(),{path,"--uninstall"});});
        status=new QLabel;status->setWordWrap(true);layout->addWidget(status);auto footer=new QHBoxLayout;footer->addStretch();auto close=new QPushButton("Cerrar");save=new QPushButton("Aplicar cambios");footer->addWidget(close);footer->addWidget(save);layout->addLayout(footer);connect(close,&QPushButton::clicked,this,&QDialog::reject);
        connect(save,&QPushButton::clicked,this,[this]{
            if(!clearKey->isChecked()&&!keyPanel->ready()){status->setText("Valida SteamGridDB o marca configurar después antes de aplicar.");return;}
            QJsonArray roots;for(int i=0;i<folders->count();++i)roots.append(folders->item(i)->data(Qt::UserRole).toString());
            QJsonObject data{{"external_roots",roots},{"selected_candidates",folders->selectedCandidates()},{"monitor_disk",disks->currentData().toJsonObject()},{"steamgriddb_key",keyPanel->keyForSave()},{"clear_key",clearKey->isChecked()}};
            auto p=new QProcess(this);p->setProcessChannelMode(QProcess::MergedChannels);saving=true;save->setEnabled(false);status->setText("Guardando…");
            connect(p,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[this,p](int code,QProcess::ExitStatus){saving=false;save->setEnabled(true);status->setText(QString::fromUtf8(p->readAllStandardOutput()));if(code==0||code==2){keyPanel->clearInput();clearKey->setChecked(false);folders->clearSelections();}p->deleteLater();});
            p->start("python3",{backend,"--save-settings"});if(p->waitForStarted()){p->write(QJsonDocument(data).toJson(QJsonDocument::Compact));p->closeWriteChannel();}else{saving=false;save->setEnabled(true);status->setText("No se pudo guardar la configuración.");p->deleteLater();}
        });
    }
    void reject() override {if(!saving)QDialog::reject();}
    void closeEvent(QCloseEvent *e) override {if(saving)e->ignore();else QDialog::closeEvent(e);}
};
