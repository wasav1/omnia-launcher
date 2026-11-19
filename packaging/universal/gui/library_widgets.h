#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonObject>
#include "candidate_review.h"

class VolumePicker : public QListWidget {
public:
    explicit VolumePicker(QWidget *parent=nullptr):QListWidget(parent){setSelectionMode(QAbstractItemView::NoSelection);setMaximumHeight(150);}
    void populate(const QJsonArray &available,const QJsonArray &saved){
        clear();QSet<QString> found;
        auto selected=[&](const QJsonObject &d){for(auto value:saved){auto old=value.toObject();if(old["uuid"]==d["uuid"]&&old["path"]==d["path"])return true;}return false;};
        for(auto value:available){auto d=value.toObject();if(d["path"].toString().isEmpty())continue;auto row=new QListWidgetItem(QString("%1 — %2").arg(d["label"].toString(),d["path"].toString()),this);row->setFlags(row->flags()|Qt::ItemIsUserCheckable);row->setCheckState(selected(d)?Qt::Checked:Qt::Unchecked);row->setData(Qt::UserRole,d);found.insert(d["uuid"].toString()+"|"+d["path"].toString());}
        for(auto value:saved){auto d=value.toObject();auto key=d["uuid"].toString()+"|"+d["path"].toString();if(found.contains(key)||d["path"].toString().isEmpty())continue;auto row=new QListWidgetItem(QString("%1 (no conectado) — %2").arg(d["label"].toString(),d["path"].toString()),this);row->setFlags(row->flags()|Qt::ItemIsUserCheckable);row->setCheckState(Qt::Checked);row->setData(Qt::UserRole,d);}
    }
    QJsonArray checkedVolumes()const{QJsonArray out;for(int i=0;i<count();++i)if(item(i)->checkState()==Qt::Checked)out.append(item(i)->data(Qt::UserRole).toJsonObject());return out;}
};

class RouteList : public QListWidget {
    QString backend;
    QStringList queue;
    bool busy=false;
    QPointer<QLabel> counterLabel;
    void refreshCounters() {
        const auto selected = selectedCandidates();
        for(int i=0;i<count();++i){
            auto entry=item(i);auto root=entry->data(Qt::UserRole).toString();QSet<QString> games;
            for(auto value:selected){auto choice=value.toObject();auto file=choice["file"].toString();if(!choice["unlink"].toBool()&&(file==root||file.startsWith(root+"/"))){
                auto key=choice["game_key"].toString();games.insert(key.isEmpty()?file:key);
            }}
            auto info=entry->data(Qt::UserRole+2).toString();
            int unlinkCount=0;for(auto value:selected){auto choice=value.toObject();auto file=choice["file"].toString();if(choice["unlink"].toBool()&&(file==root||file.startsWith(root+"/")))++unlinkCount;}
            entry->setText(root+"\n"+info+QString("\n%1 para vincular · %2 para desvincular").arg(games.size()).arg(unlinkCount));
            entry->setToolTip(entry->text());
        }
        if(counterLabel)counterLabel->setText(QString("%1 juegos para vincular · %2 para desvincular · %3 ports / archivos · %4 carpetas").arg(selectedGameCount()).arg(selectedUnlinkCount()).arg(selected.size()).arg(count()));
    }
    QMap<QString,QJsonObject> choices;
    void scanNext() {
        if(busy)return;
        if(queue.isEmpty()){if(scanFinished)QTimer::singleShot(0,this,scanFinished);return;}
        QString path=queue.takeFirst();busy=true;
        auto p=new QProcess(this);
        auto done=[this,p,path](bool success){
            auto data=QJsonDocument::fromJson(p->readAllStandardOutput()).object();
            QString info;
            if(!success||data.isEmpty())info="No se pudo analizar. Quita y vuelve a añadir la ruta para reintentar.";
            else if(!data["available"].toBool())info=QString("%1 vinculados · No disponible o sin permiso").arg(data["linked"].toInt());
            else info=QString("%1 juegos vinculados · %2 candidatos encontrados%3").arg(data["linked"].toInt()).arg(data["candidates"].toInt()).arg(data["partial"].toBool()?" · Análisis parcial":"");
            for(int i=0;i<count();++i)if(item(i)->data(Qt::UserRole).toString()==path){item(i)->setData(Qt::UserRole+1,data);item(i)->setData(Qt::UserRole+2,info);}
            busy=false;refreshCounters();p->deleteLater();scanNext();
        };
        connect(p,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[done](int code,QProcess::ExitStatus status){done(code==0&&status==QProcess::NormalExit);});
        p->start("python3",{backend,"--inspect-route"});
        if(p->waitForStarted()){p->write(QJsonDocument(QJsonObject{{"path",path}}).toJson());p->closeWriteChannel();}else done(false);
    }
public:
    std::function<void()> scanFinished;
    RouteList(const QString &path):backend(path){setWordWrap(true);connect(model(),&QAbstractItemModel::rowsRemoved,this,[this]{refreshCounters();});}
    void setCounterLabel(QLabel *label){counterLabel=label;refreshCounters();}
    int selectedGameCount()const{
        QSet<QString> games;for(auto value:selectedCandidates()){auto choice=value.toObject();if(choice["unlink"].toBool())continue;auto key=choice["game_key"].toString();games.insert(key.isEmpty()?choice["file"].toString():key);}return games.size();
    }
    int selectedUnlinkCount()const{int count=0;for(auto value:selectedCandidates())if(value.toObject()["unlink"].toBool())++count;return count;}
    ~RouteList() override {
        disconnect(model(),nullptr,this,nullptr);
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
        CandidateReview dialog(scan,choices,backend,this);
        if(dialog.exec()==QDialog::Accepted){
            for(auto record:scan["items"].toArray())choices.remove(record.toObject()["path"].toString());
            for(auto it=dialog.choices.begin();it!=dialog.choices.end();++it)choices[it.key()]=it.value();
            refreshCounters();
        }
    }
    QJsonArray selectedCandidates()const{
        QJsonArray result;QSet<QString> files;
        for(auto choice:choices){
            bool active=false;for(int i=0;i<count();++i){auto root=item(i)->data(Qt::UserRole).toString();auto file=choice["file"].toString();if(file==root||file.startsWith(root+"/")){active=true;break;}}
            if(active&&!files.contains(choice["file"].toString())){result.append(choice);files.insert(choice["file"].toString());}
        }
        return result;
    }
    void clearSelections(){
        choices.clear();
        for(int i=0;i<count();++i){
            auto path=item(i)->data(Qt::UserRole).toString();
            item(i)->setData(Qt::UserRole+1,QJsonObject());item(i)->setData(Qt::UserRole+2,"Actualizando juegos vinculados…");
            if(!queue.contains(path))queue.append(path);
        }
        refreshCounters();scanNext();
    }
    void addPath(QString path){
        path=QDir::cleanPath(path);
        auto canonical=QFileInfo(path).canonicalFilePath();if(!canonical.isEmpty())path=canonical;
        for(int i=0;i<count();++i)if(item(i)->data(Qt::UserRole).toString()==path)return;
        auto entry=new QListWidgetItem(path+"\nAnalizando juegos…",this);entry->setData(Qt::UserRole,path);entry->setToolTip(path);entry->setData(Qt::UserRole+2,"Analizando juegos…");entry->setSizeHint(QSize(0,84));
        queue.append(path);refreshCounters();scanNext();
    }
    void scanPaths(const QStringList &paths){
        for(QString path:paths){
            path=QDir::cleanPath(path);auto canonical=QFileInfo(path).canonicalFilePath();if(!canonical.isEmpty())path=canonical;
            int row=-1;for(int i=0;i<count();++i)if(item(i)->data(Qt::UserRole).toString()==path){row=i;break;}
            if(row<0){addPath(path);continue;}
            auto entry=item(row);entry->setData(Qt::UserRole+1,QJsonObject());entry->setData(Qt::UserRole+2,"Analizando juegos…");
            if(!queue.contains(path))queue.append(path);
        }
        refreshCounters();scanNext();
    }
    QString knownGamesSummary()const{
        QMap<QString,QString> found;
        for(int i=0;i<count();++i){auto data=item(i)->data(Qt::UserRole+1).toJsonObject();for(auto value:data["items"].toArray()){
            auto candidate=value.toObject();if(candidate["kind"]!="port"&&candidate["kind"]!="rom")continue;
            QString name=candidate["name"].toString().trimmed();if(name.isEmpty())continue;
            QString platform=candidate["platform"].toString();QString label=name;
            if(!candidate["port_name"].toString().isEmpty())label+=" · "+candidate["port_name"].toString();
            if(platform=="sw1")label+=" · Switch";else if(platform=="sw2")label+=" · Switch 2";else if(platform=="n64")label+=" · N64";
            found.insert(label.toCaseFolded(),label);
        }}
        if(found.isEmpty())return "No encontramos ports del catálogo Omnia ni ROM de N64 en los discos escaneados. Puedes agregar carpetas y revisar otros archivos en el siguiente paso.";
        QStringList labels=found.values();constexpr int limit=40;int extra=qMax(0,labels.size()-limit);if(extra)labels=labels.mid(0,limit);
        return QString("Juegos reconocidos: %1\n\n%2%3").arg(found.size()).arg(labels.join("\n")).arg(extra?QString("\n… y %1 más").arg(extra):QString());
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
        validate=new QPushButton(lucideIcon("key-round"),saved?"Comprobar conexión / validar nueva clave":"Validar clave");layout->addWidget(validate);
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
