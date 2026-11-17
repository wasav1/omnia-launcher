#pragma once
#include <QtWidgets>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>

// Conserva el estado accesible del modelo y dibuja solo el control centrado.
class CandidateCheckDelegate : public QStyledItemDelegate {
public:
    using QStyledItemDelegate::QStyledItemDelegate;
    void paint(QPainter *painter,const QStyleOptionViewItem &option,const QModelIndex &index) const override {
        painter->save();painter->setRenderHint(QPainter::Antialiasing);
        painter->fillRect(option.rect,index.row()%2?option.palette.alternateBase():option.palette.base());
        if(!(index.flags() & Qt::ItemIsUserCheckable)) {
            QRectF badge=QRectF(option.rect).adjusted(5,12,-5,-12);
            painter->setPen(Qt::NoPen);painter->setBrush(QColor("#24453f"));painter->drawRoundedRect(badge,7,7);
            painter->setPen(QColor("#a2dbc4"));painter->drawText(option.rect,Qt::AlignCenter,index.data().toString());
        } else {
            const bool checked=index.data(Qt::CheckStateRole).toInt()==Qt::Checked;
            QRectF box(0,0,22,22);box.moveCenter(QRectF(option.rect).center());
            if(option.state & QStyle::State_HasFocus){
                painter->setBrush(Qt::NoBrush);painter->setPen(QPen(QColor("#a6baff"),1.5));painter->drawRoundedRect(box.adjusted(-4,-4,4,4),9,9);
            }
            painter->setPen(QPen(QColor(checked?"#7391ff":"#64718a"),1.4));
            painter->setBrush(QColor(checked?"#476cf0":"#202733"));painter->drawRoundedRect(box,6,6);
            if(checked){
                QPainterPath tick;tick.moveTo(box.left()+5,box.top()+11);tick.lineTo(box.left()+9,box.top()+15);tick.lineTo(box.left()+17,box.top()+7);
                painter->setPen(QPen(Qt::white,2.4,Qt::SolidLine,Qt::RoundCap,Qt::RoundJoin));painter->drawPath(tick);
            }
        }
        painter->restore();
    }
    bool editorEvent(QEvent *event,QAbstractItemModel *model,const QStyleOptionViewItem &option,const QModelIndex &index) override {
        if(!(index.flags() & Qt::ItemIsEnabled)||!(index.flags() & Qt::ItemIsUserCheckable))return false;
        if(event->type()==QEvent::MouseButtonPress||event->type()==QEvent::MouseButtonDblClick)return true;
        bool toggle=false;
        if(event->type()==QEvent::MouseButtonRelease)toggle=static_cast<QMouseEvent*>(event)->button()==Qt::LeftButton;
        if(event->type()==QEvent::KeyPress){auto key=static_cast<QKeyEvent*>(event)->key();toggle=key==Qt::Key_Space||key==Qt::Key_Select;}
        if(!toggle)return false;
        return model->setData(index,index.data(Qt::CheckStateRole).toInt()==Qt::Checked?Qt::Unchecked:Qt::Checked,Qt::CheckStateRole);
    }
};

class CandidateReview : public QDialog {
    QTableWidget *table;
    QLabel *counter;
    QDialogButtonBox *buttons;
    QJsonArray records;
    QString backend;
    bool checking = false;
    void updateCounter() {
        QSet<QString> games; int files = 0, unlink = 0;
        for (int row=0; row<records.size(); ++row) {
            if (table->item(row,0)->checkState()!=Qt::Checked) continue;
            auto c=records[row].toObject(); ++files;
            if(c["linked"].toBool())++unlink;else games.insert(c["game_key"].toString(c["path"].toString()));
        }
        counter->setText(QString("Vincular: %1 juegos · %2 ports / archivos   |   Desvincular: %3").arg(games.size()).arg(files-unlink).arg(unlink));
    }
public:
    QMap<QString,QJsonObject> choices;
    CandidateReview(QJsonObject scan,const QMap<QString,QJsonObject> &previous,const QString &backendPath=QString(),QWidget *parent=nullptr)
        :QDialog(parent),records(scan["items"].toArray()),backend(backendPath) {
        setWindowTitle("Revisar juegos — Omnia");resize(1150,650);auto layout=new QVBoxLayout(this);
        auto title=new QLabel("Elige los juegos de esta carpeta");title->setObjectName("CardTitle");layout->addWidget(title);
        auto info=new QLabel("Los ports conocidos proponen el juego y el ejecutable que lo inicia; se ignoran launchers y herramientas auxiliares. Revisa y marca lo que quieras vincular o desvincular. Nada se ejecuta durante este análisis y desvincular no borra archivos ni partidas.");info->setWordWrap(true);layout->addWidget(info);
        auto hint=new QLabel("N64: se propone Gopher64. Al confirmar se comprobarán el emulador y los complementos necesarios; si falta alguno, verás qué instalar antes de continuar.");hint->setWordWrap(true);hint->setObjectName("Muted");layout->addWidget(hint);
        counter=new QLabel;counter->setObjectName("CardTitle");layout->addWidget(counter);
        auto search=new QLineEdit;search->setClearButtonEnabled(true);search->setPlaceholderText("Buscar por juego, port o archivo…");layout->addWidget(search);
        if(scan["partial"].toBool())layout->addWidget(new QLabel("Análisis parcial: se muestran solo los candidatos encontrados dentro del límite."));
        table=new QTableWidget(records.size(),5);table->setAlternatingRowColors(true);table->verticalHeader()->hide();table->verticalHeader()->setDefaultSectionSize(48);table->setHorizontalScrollMode(QAbstractItemView::ScrollPerPixel);
        table->setHorizontalHeaderLabels({"Vincular / quitar","Juego","Port / plataforma","Archivo de inicio / ROM","Emulador"});
        table->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);table->horizontalHeader()->setStretchLastSection(true);
        table->setItemDelegateForColumn(0,new CandidateCheckDelegate(table));table->setColumnWidth(0,85);table->setColumnWidth(1,260);table->setColumnWidth(2,175);table->setColumnWidth(3,320);layout->addWidget(table);
        for(int row=0;row<records.size();++row){
            auto candidate=records[row].toObject();auto saved=previous.value(candidate["path"].toString());bool linked=candidate["linked"].toBool();
            auto select=new QTableWidgetItem("");select->setFlags(Qt::ItemIsEnabled|Qt::ItemIsSelectable|Qt::ItemIsUserCheckable);select->setCheckState(!linked&&!saved.isEmpty()?Qt::Checked:Qt::Unchecked);select->setToolTip(linked?"Marcar para desvincular de Omnia (no borra archivos ni partidas)":"Marcar para vincular · Espacio para cambiar");table->setItem(row,0,select);
            auto name=new QTableWidgetItem(saved.isEmpty()?candidate["name"].toString():saved["name"].toString());name->setToolTip(name->text());table->setItem(row,1,name);
            QString type=candidate["kind"]=="rom"?"ROM":"Ejecutable";
            if(candidate["kind"]=="port") type=candidate["port_name"].toString()+" · "+(candidate["platform"]=="sw2"?"Switch 2":candidate["platform"]=="pc"?"PC":"Switch");
            auto category=new QTableWidgetItem(type);category->setToolTip(type+(candidate["kind"]=="port"?"\nIdentificado por ejecutable y carpeta. Confirma la edición y versión de tus archivos.":""));category->setFlags(Qt::ItemIsEnabled);table->setItem(row,2,category);
            auto files=new QComboBox;for(auto file:candidate["files"].toArray())files->addItem(file.toString());
            if(!saved.isEmpty())files->setCurrentText(saved["file"].toString());
            else if(!candidate["suggested_file"].toString().isEmpty())files->setCurrentText(candidate["suggested_file"].toString());
            else if(files->count()>1)files->setCurrentIndex(-1);
            files->setToolTip(files->currentText());connect(files,&QComboBox::currentTextChanged,files,&QWidget::setToolTip);table->setCellWidget(row,3,files);
            auto emulator=new QWidget;auto line=new QHBoxLayout(emulator);line->setContentsMargins(0,0,0,0);
            auto exe=new QLineEdit(saved.isEmpty()?candidate["suggested_emulator"].toString():saved["emulator"].toString());exe->setPlaceholderText("gopher64 o /ruta/emulador");
            auto browse=new QPushButton("…");line->addWidget(exe);line->addWidget(browse);table->setCellWidget(row,4,emulator);
            bool rom=candidate["kind"]=="rom";emulator->setEnabled(rom&&!linked);files->setEnabled(!linked);
            connect(browse,&QPushButton::clicked,this,[this,exe]{auto file=QFileDialog::getOpenFileName(this,"Elige el ejecutable del emulador","/usr/bin");if(!file.isEmpty())exe->setText(file);});
            connect(files,&QComboBox::currentTextChanged,this,[this,search](const QString&){const auto query=search->text().trimmed().toCaseFolded();for(int r=0;r<table->rowCount();++r){auto combo=qobject_cast<QComboBox*>(table->cellWidget(r,3));QString text=table->item(r,1)->text()+" "+table->item(r,2)->text()+" "+(combo?combo->currentText():QString());if(combo)for(int i=0;i<combo->count();++i)text+=" "+combo->itemText(i);table->setRowHidden(r,!query.isEmpty()&&!text.toCaseFolded().contains(query));}});
        }
        connect(search,&QLineEdit::textChanged,this,[this](const QString &value){const auto query=value.trimmed().toCaseFolded();for(int r=0;r<table->rowCount();++r){auto combo=qobject_cast<QComboBox*>(table->cellWidget(r,3));QString text=table->item(r,1)->text()+" "+table->item(r,2)->text()+" "+(combo?combo->currentText():QString());if(combo)for(int i=0;i<combo->count();++i)text+=" "+combo->itemText(i);table->setRowHidden(r,!query.isEmpty()&&!text.toCaseFolded().contains(query));}});
        connect(table,&QTableWidget::itemChanged,this,[this](QTableWidgetItem*){updateCounter();});updateCounter();
        buttons=new QDialogButtonBox(QDialogButtonBox::Ok|QDialogButtonBox::Cancel);buttons->button(QDialogButtonBox::Ok)->setText("Confirmar selección");layout->addWidget(buttons);
        connect(buttons,&QDialogButtonBox::accepted,this,&CandidateReview::accept);connect(buttons,&QDialogButtonBox::rejected,this,&CandidateReview::reject);
    }
    void accept() override {
        if(checking)return;
        QMap<QString,QJsonObject> selected; QJsonArray payload;
        for(int row=0;row<records.size();++row){auto candidate=records[row].toObject();if(table->item(row,0)->checkState()!=Qt::Checked)continue;
            auto file=static_cast<QComboBox*>(table->cellWidget(row,3))->currentText();auto name=table->item(row,1)->text().trimmed();auto emulator=table->cellWidget(row,4)->findChild<QLineEdit*>()->text().trimmed();
            if(candidate["linked"].toBool()){if(file.isEmpty())continue;QJsonObject choice{{"name",name},{"file",file},{"kind",candidate["kind"]},{"unlink",true},{"root",candidate["root"]},{"game_key",candidate["game_key"]}};selected[candidate["path"].toString()]=choice;payload.append(choice);continue;}
            if(file.isEmpty()||name.isEmpty()||name.size()>80||(candidate["kind"]=="rom"&&emulator.isEmpty())){QMessageBox::warning(this,"Omnia","Completa nombre, archivo de inicio y emulador de cada juego marcado.");return;}
            QJsonObject choice{{"name",name},{"file",file},{"kind",candidate["kind"]},{"emulator",emulator},{"root",candidate["root"]},{"game_key",candidate["game_key"]}};
            selected[candidate["path"].toString()]=choice;payload.append(choice);
        }
        if(backend.isEmpty()){choices=selected;QDialog::accept();return;}
        auto process=new QProcess(this);checking=true;buttons->setEnabled(false);counter->setText("Comprobando complementos…");
        auto finished=[this,process,selected](bool ok){
            checking=false;buttons->setEnabled(true);updateCounter();
            auto data=QJsonDocument::fromJson(process->readAllStandardOutput()).object();
            if(!ok||data.isEmpty())QMessageBox::warning(this,"Omnia","No se pudieron comprobar los complementos. Intenta confirmar de nuevo.");
            else if(!data["ready"].toBool()){
                QStringList messages;for(auto value:data["missing"].toArray())messages<<value.toObject()["message"].toString();
                QMessageBox::information(this,"Complementos necesarios",messages.join("\n\n")+"\n\nTu selección permanece aquí. Instala el complemento y vuelve a confirmar.");
            }else{choices=selected;QDialog::accept();}
            process->deleteLater();
        };
        connect(process,qOverload<int,QProcess::ExitStatus>(&QProcess::finished),this,[finished](int code,QProcess::ExitStatus status){finished(code==0&&status==QProcess::NormalExit);});
        process->start("python3",{backend,"--check-candidates"});
        if(process->waitForStarted()){process->write(QJsonDocument(QJsonObject{{"selected_candidates",payload}}).toJson());process->closeWriteChannel();}else finished(false);
    }
    void reject() override {if(!checking)QDialog::reject();}
    void closeEvent(QCloseEvent *event) override {if(checking)event->ignore();else QDialog::closeEvent(event);}
};
