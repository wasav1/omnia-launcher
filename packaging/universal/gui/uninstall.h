#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonObject>
#include "appearance.h"

class UninstallWindow : public QDialog {
    bool running=false;
public:
    UninstallWindow(const QString &backend):QDialog(nullptr){
        setWindowTitle("Omnia — Desinstalar");resize(930,650);
        auto layout=new QVBoxLayout(this);layout->setContentsMargins(28,24,28,24);layout->setSpacing(14);
        layout->addWidget(omniaHeader("Desinstalación", "trash-2", QColor("#f08b84")));
        auto title=new QLabel("Desinstalar Omnia");title->setObjectName("PageTitle");layout->addWidget(title);
        auto subtitle=new QLabel("Retira el escritorio de Omnia y sus datos de este usuario.");subtitle->setObjectName("Muted");layout->addWidget(subtitle);
        auto impact = new QHBoxLayout;
        impact->addWidget(omniaCard("Se eliminará", "Configuración, biblioteca de Omnia, historial, favoritos, clave de SteamGridDB, imágenes descargadas y componentes de escritorio de Omnia.", nullptr, "trash-2", "danger"));
        impact->addWidget(omniaCard("Se conservará", "Los archivos de tus juegos, ROMs, emuladores, partidas y respaldos. Las aplicaciones y dependencias compartidas permanecen instaladas.", nullptr, "shield-check", "success"));
        layout->addLayout(impact);
        auto note=omniaCard("Cambios en tu sesión", "Se retirarán los widgets y atajos de Omnia. Se recuperará el fondo anterior cuando exista su respaldo; en otro caso se usará el fondo nativo de Plasma. Al finalizar se reiniciará Plasma unos segundos.", nullptr, "triangle-alert", "danger");layout->addWidget(note);
        auto removePackage=new QCheckBox("Retirar también el asistente del sistema (requiere autorización)");
        QProcess inspect;inspect.start("python3",{backend,"--uninstall-plan"});
        bool inspected=inspect.waitForFinished(15000)&&inspect.exitCode()==0;
        bool packaged=inspected&&QJsonDocument::fromJson(inspect.readAllStandardOutput()).object()["package_installed"].toBool();
        removePackage->setVisible(packaged);removePackage->setChecked(packaged);layout->addWidget(removePackage);
        auto confirm=new QCheckBox("Confirmo que quiero eliminar los datos y componentes de Omnia.");layout->addWidget(confirm);
        auto status=new QLabel(inspected?"":"No se pudo comprobar la instalación. Cierra y vuelve a intentar.");status->setWordWrap(true);layout->addWidget(status);
        auto progress=new QProgressBar;progress->setTextVisible(false);progress->hide();layout->addWidget(progress);
        layout->addStretch();auto footer=new QHBoxLayout;footer->addStretch();auto close=new QPushButton(lucideIcon("x"), "Cancelar");auto remove=new QPushButton(lucideIcon("trash-2"), "Desinstalar Omnia");remove->setEnabled(false);remove->setProperty("danger",true);footer->addWidget(close);footer->addWidget(remove);layout->addLayout(footer);
        connect(confirm,&QCheckBox::toggled,this,[remove,inspected](bool on){remove->setEnabled(on&&inspected);});
        connect(close,&QPushButton::clicked,this,&UninstallWindow::reject);
        connect(remove,&QPushButton::clicked,this,[=,this]{
            if(running||!confirm->isChecked())return;
            QMessageBox warning(QMessageBox::Warning, "Desinstalar Omnia",
                                "Se eliminarán los datos de Omnia de este usuario.",
                                QMessageBox::Cancel, this);
            auto proceed = warning.addButton("Desinstalar", QMessageBox::DestructiveRole);
            proceed->setProperty("danger", true);
            proceed->setIcon(lucideIcon("trash-2"));
            warning.exec();
            if (warning.clickedButton() != proceed) return;
            running=true;remove->setEnabled(false);confirm->setEnabled(false);removePackage->setEnabled(false);close->setEnabled(false);
            progress->setRange(0,0);progress->show();status->setText("Retirando Omnia…");
            auto process=new QProcess(this);process->setProcessChannelMode(QProcess::MergedChannels);
            auto finished=[=,this](bool ok){running=false;progress->setRange(0,1);progress->setValue(ok?1:0);auto text=QString::fromUtf8(process->readAllStandardOutput()).trimmed();status->setText(text.isEmpty()?"No se pudo completar la desinstalación. Tus juegos no se han eliminado.":text);close->setText("Cerrar");close->setEnabled(true);process->deleteLater();};
            connect(process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[finished](int code,QProcess::ExitStatus exit){finished(code==0&&exit==QProcess::NormalExit);});
            process->start("python3",{backend,"--uninstall"});
            if(process->waitForStarted()){process->write(QJsonDocument(QJsonObject{{"accepted",true},{"remove_package",removePackage->isChecked()}}).toJson());process->closeWriteChannel();}else finished(false);
        });
    }
    void reject() override {if(!running)QDialog::reject();}
    void closeEvent(QCloseEvent *event) override {if(running)event->ignore();else QDialog::closeEvent(event);}
};
