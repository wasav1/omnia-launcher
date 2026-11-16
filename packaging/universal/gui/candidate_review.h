#pragma once
#include <QtWidgets>
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>

class CandidateReview : public QDialog {
    QTableWidget *table;
    QJsonArray records;
public:
    QMap<QString,QJsonObject> choices;
    CandidateReview(QJsonObject scan,const QMap<QString,QJsonObject> &previous,QWidget *parent=nullptr):QDialog(parent),records(scan["items"].toArray()) {
        setWindowTitle("Revisar candidatos — Omnia");resize(1020,600);auto layout=new QVBoxLayout(this);
        auto info=new QLabel("Marca únicamente los juegos que quieres agregar. Puedes cambiar su nombre y elegir el archivo de inicio. Las entradas ya vinculadas no se duplican. La selección se agregará al pulsar Instalar o Aplicar cambios. No se ejecutará ningún archivo durante esta revisión.");info->setWordWrap(true);layout->addWidget(info);
        auto hint=new QLabel("ROMs: escribe gopher64 o elige un emulador. Para otro emulador, Omnia enviará la ROM como primer argumento; verifica que admita ese formato. Windows requiere umu-run.");hint->setWordWrap(true);layout->addWidget(hint);
        if(scan["partial"].toBool())layout->addWidget(new QLabel("Análisis parcial: se muestran solo los candidatos encontrados dentro del límite."));
        table=new QTableWidget(records.size(),5);table->setHorizontalHeaderLabels({"Agregar","Nombre","Tipo","Archivo de inicio / ROM","Emulador"});table->horizontalHeader()->setSectionResizeMode(QHeaderView::Interactive);table->horizontalHeader()->setStretchLastSection(true);table->setColumnWidth(0,70);table->setColumnWidth(1,200);table->setColumnWidth(2,100);table->setColumnWidth(3,300);layout->addWidget(table);
        for(int row=0;row<records.size();++row){
            auto candidate=records[row].toObject();auto saved=previous.value(candidate["path"].toString());bool linked=candidate["linked"].toBool();
            auto select=new QTableWidgetItem(linked?"Vinculado":"");select->setFlags(linked?Qt::ItemIsEnabled:Qt::ItemIsEnabled|Qt::ItemIsUserCheckable);if(!linked)select->setCheckState(saved.isEmpty()?Qt::Unchecked:Qt::Checked);table->setItem(row,0,select);
            table->setItem(row,1,new QTableWidgetItem(saved.isEmpty()?candidate["name"].toString():saved["name"].toString()));
            auto type=new QTableWidgetItem(candidate["kind"]=="rom"?"ROM":"Ejecutable");type->setFlags(Qt::ItemIsEnabled);table->setItem(row,2,type);
            auto files=new QComboBox;for(auto file:candidate["files"].toArray())files->addItem(file.toString());
            if(!saved.isEmpty())files->setCurrentText(saved["file"].toString());else if(files->count()>1)files->setCurrentIndex(-1);
            files->setToolTip(candidate["path"].toString());table->setCellWidget(row,3,files);
            auto emulator=new QWidget;auto line=new QHBoxLayout(emulator);line->setContentsMargins(0,0,0,0);auto exe=new QLineEdit(saved["emulator"].toString());exe->setPlaceholderText("gopher64 o /ruta/emulador");auto browse=new QPushButton("…");line->addWidget(exe);line->addWidget(browse);table->setCellWidget(row,4,emulator);
            bool rom=candidate["kind"]=="rom";emulator->setEnabled(rom&&!linked);files->setEnabled(!linked);
            connect(browse,&QPushButton::clicked,this,[this,exe]{auto file=QFileDialog::getOpenFileName(this,"Elige el ejecutable del emulador","/usr/bin");if(!file.isEmpty())exe->setText(file);});
        }
        auto buttons=new QDialogButtonBox(QDialogButtonBox::Ok|QDialogButtonBox::Cancel);buttons->button(QDialogButtonBox::Ok)->setText("Confirmar selección");layout->addWidget(buttons);connect(buttons,&QDialogButtonBox::accepted,this,&CandidateReview::accept);connect(buttons,&QDialogButtonBox::rejected,this,&QDialog::reject);
    }
    void accept() override {
        QMap<QString,QJsonObject> selected;
        for(int row=0;row<records.size();++row){auto candidate=records[row].toObject();if(candidate["linked"].toBool()||table->item(row,0)->checkState()!=Qt::Checked)continue;
            auto file=static_cast<QComboBox*>(table->cellWidget(row,3))->currentText();auto name=table->item(row,1)->text().trimmed();auto emulator=table->cellWidget(row,4)->findChild<QLineEdit*>()->text().trimmed();
            if(file.isEmpty()||name.isEmpty()||name.size()>80||(candidate["kind"]=="rom"&&emulator.isEmpty())){QMessageBox::warning(this,"Omnia","Completa nombre, archivo de inicio y emulador de cada juego marcado.");return;}
            selected[candidate["path"].toString()]=QJsonObject{{"name",name},{"file",file},{"kind",candidate["kind"]},{"emulator",emulator},{"root",candidate["root"]}};
        }
        choices=selected;QDialog::accept();
    }
};
