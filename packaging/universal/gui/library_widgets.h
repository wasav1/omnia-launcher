#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonObject>
#include "candidate_review.h"

class RouteList : public QListWidget {
    QString backend;
    QStringList queue;
    bool busy=false;
    QMap<QString,QJsonObject> choices;
    void scanNext() {
        if(busy || queue.isEmpty())return;
        QString path=queue.takeFirst();busy=true;
        auto p=new QProcess(this);
        auto done=[this,p,path](bool success){
            auto data=QJsonDocument::fromJson(p->readAllStandardOutput()).object();
            QString info;
            if(!success||data.isEmpty())info="No se pudo analizar. Quita y vuelve a añadir la ruta para reintentar.";
            else if(!data["available"].toBool())info=QString("%1 vinculados · No disponible o sin permiso").arg(data["linked"].toInt());
            else info=QString("%1 juegos vinculados · %2 candidatos encontrados%3").arg(data["linked"].toInt()).arg(data["candidates"].toInt()).arg(data["partial"].toBool()?" · Análisis parcial":"");
            for(int i=0;i<count();++i)if(item(i)->data(Qt::UserRole).toString()==path){item(i)->setData(Qt::UserRole+1,data);item(i)->setText(path+"\n"+info);item(i)->setToolTip(path+"\n"+info);}
            busy=false;p->deleteLater();scanNext();
        };
        connect(p,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[done](int code,QProcess::ExitStatus status){done(code==0&&status==QProcess::NormalExit);});
        p->start("python3",{backend,"--inspect-route"});
        if(p->waitForStarted()){p->write(QJsonDocument(QJsonObject{{"path",path}}).toJson());p->closeWriteChannel();}else done(false);
    }
public:
    RouteList(const QString &path):backend(path){setWordWrap(true);}
    ~RouteList() override {
        for(auto process:findChildren<QProcess*>()) {
            process->disconnect(this);
            if(process->state()!=QProcess::NotRunning){process->kill();process->waitForFinished(1000);}
        }
    }
    void reviewCandidates(){
        auto entry=currentItem();
        if(!entry){QMessageBox::information(this,"Omnia","Selecciona una ruta para revisar sus candidatos.");return;}
        auto scan=entry->data(Qt::UserRole+1).toJsonObject();
        if(scan.isEmpty()){QMessageBox::information(this,"Omnia","Espera a que termine el análisis de esta ruta.");return;}
        CandidateReview dialog(scan,choices,this);
        if(dialog.exec()==QDialog::Accepted){
            for(auto record:scan["items"].toArray())choices.remove(record.toObject()["path"].toString());
            for(auto it=dialog.choices.begin();it!=dialog.choices.end();++it)choices[it.key()]=it.value();
            entry->setToolTip(entry->text()+"\nSelección pendiente: "+QString::number(selectedCandidates().size()));
        }
    }
    QJsonArray selectedCandidates()const{
        QJsonArray result;
        for(auto choice:choices){
            bool active=false;for(int i=0;i<count();++i){auto root=item(i)->data(Qt::UserRole).toString();auto file=choice["file"].toString();if(file==root||file.startsWith(root+"/")){active=true;break;}}
            if(active)result.append(choice);
        }
        return result;
    }
    void clearSelections(){
        choices.clear();
        for(int i=0;i<count();++i){
            auto path=item(i)->data(Qt::UserRole).toString();
            item(i)->setData(Qt::UserRole+1,QJsonObject());item(i)->setText(path+"\nActualizando juegos vinculados…");
            if(!queue.contains(path))queue.append(path);
        }
        scanNext();
    }
    void addPath(QString path){
        path=QDir::cleanPath(path);
        auto canonical=QFileInfo(path).canonicalFilePath();if(!canonical.isEmpty())path=canonical;
        for(int i=0;i<count();++i)if(item(i)->data(Qt::UserRole).toString()==path)return;
        auto entry=new QListWidgetItem(path+"\nAnalizando juegos…",this);entry->setData(Qt::UserRole,path);entry->setToolTip(path);entry->setSizeHint(QSize(0,58));
        queue.append(path);scanNext();
    }
};

class KeyPanel : public QWidget {
    QString backend;
    QLineEdit *input;
    QLabel *status;
    QCheckBox *defer;
    QPushButton *validate;
    bool saved, valid=false, pending=false;
    int revision=0;
    void check(bool savedKey) {
        if(pending)return;
        if(!savedKey&&input->text().trimmed().isEmpty()){status->setText("Introduce la nueva clave para validarla.");return;}
        pending=true;valid=false;validate->setEnabled(false);const int request=revision;
        status->setText(savedKey?"Comprobando la conexión guardada con SteamGridDB…":"Validando nueva clave…");
        auto p=new QProcess(this);
        auto done=[this,p,request](bool ok){
            pending=false;validate->setEnabled(true);
            if(request==revision){valid=ok;status->setText(QString::fromUtf8(p->readAllStandardOutput()).trimmed()+(ok?"":"\nIntroduce otra clave y valídala, o configura SteamGridDB después."));}
            p->deleteLater();
        };
        connect(p,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[done](int code,QProcess::ExitStatus exit){done(code==0&&exit==QProcess::NormalExit);});
        p->start("python3",{backend,savedKey?"--validate-saved-key":"--validate-key"});
        if(p->waitForStarted()){if(!savedKey)p->write(input->text().trimmed().toUtf8());p->closeWriteChannel();}else done(false);
    }
public:
    KeyPanel(const QString &path,bool exists,bool autoCheck=true):backend(path),saved(exists){
        auto layout=new QVBoxLayout(this);layout->setContentsMargins(0,0,0,0);
        auto label=new QLabel(saved?"Se encontró una clave guardada. Se comprobará sin mostrarla. Déjala vacía para conservarla.":"Introduce tu clave API de SteamGridDB (opcional).");label->setWordWrap(true);layout->addWidget(label);
        input=new QLineEdit;input->setEchoMode(QLineEdit::Password);input->setPlaceholderText(saved?"Nueva clave, solo si necesitas reemplazarla":"Clave API");layout->addWidget(input);
        validate=new QPushButton(saved?"Comprobar conexión / validar nueva clave":"Validar clave");layout->addWidget(validate);
        status=new QLabel(saved?"Conexión pendiente de comprobar.":"Puedes configurar el arte más adelante.");status->setWordWrap(true);layout->addWidget(status);
        defer=new QCheckBox("Configurar SteamGridDB después (continuar sin validar)");layout->addWidget(defer);
        connect(validate,&QPushButton::clicked,this,[this]{check(input->text().trimmed().isEmpty()&&saved);});
        connect(input,&QLineEdit::textChanged,this,[this]{++revision;valid=false;status->setText("Clave modificada: valida la conexión antes de continuar.");});
        if(saved&&autoCheck)QTimer::singleShot(0,this,[this]{check(true);});
    }
    ~KeyPanel() override {
        for(auto process:findChildren<QProcess*>()) {
            process->disconnect(this);
            if(process->state()!=QProcess::NotRunning){process->kill();process->waitForFinished(1000);}
        }
    }
    QString key()const{return input->text().trimmed();}
    bool ready()const{return defer->isChecked()||(!saved&&key().isEmpty())||(!pending&&valid);}
    QString keyForSave()const{return defer->isChecked()?QString():key();}
    QString summary()const{return defer->isChecked()?"Validación pospuesta":valid?"Conexión validada":saved?"Conexión guardada sin validar":"Sin clave";}
    void clearInput(){input->clear();}
};
