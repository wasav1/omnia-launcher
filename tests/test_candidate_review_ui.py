"""La GUI conserva la selección si falta un complemento y cuenta ports del mismo juego una vez."""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO=Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('cmake') and shutil.which('c++'), 'Requiere Qt Widgets')
class CandidateReviewUI(unittest.TestCase):
    def test_missing_component_does_not_accept_or_lose_selection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            (root/'backend.py').write_text('''import json, pathlib, sys
json.load(sys.stdin)
ready=(pathlib.Path(__file__).parent/'ready').exists()
print(json.dumps({'ready':ready,'missing':[] if ready else [{'message':'Instala Gopher64 para continuar.'}]}))
''')
            (root/'test.cpp').write_text('''#include "''' + (REPO/'packaging/universal/gui/candidate_review.h').as_posix() + '''"
int main(int argc,char **argv){
    QApplication app(argc,argv);
    QJsonArray items;
    for(auto port:{"Longshot","NX2navi"}) items.append(QJsonObject{{"path",QString("/test/")+port},{"name","Ocarina of Time"},{"kind","port"},{"game_key","ocarina"},{"port_name",port},{"platform","sw2"},{"files",QJsonArray{QString("/test/")+port+"/game"}}});
    CandidateReview dialog(QJsonObject{{"items",items}},{},QString::fromLocal8Bit(argv[1]));dialog.show();
    auto table=dialog.findChild<QTableWidget*>();
    for(int i=0;i<2;++i)table->item(i,0)->setCheckState(Qt::Checked);
    bool correctCount=false;
    for(auto label:dialog.findChildren<QLabel*>())if(label->text().contains("Selección: 1 juego"))correctCount=true;
    if(!correctCount)return 11;
    bool missingSeen=false;
    QObject::connect(&dialog,&QDialog::accepted,&app,[&]{app.exit(missingSeen&&dialog.choices.size()==2?0:12);});
    QTimer poll;
    QObject::connect(&poll,&QTimer::timeout,[&]{
        auto box=qobject_cast<QMessageBox*>(QApplication::activeModalWidget());
        if(!box)return;
        if(!box->text().contains("Instala Gopher64")){app.exit(13);return;}
        missingSeen=true;box->accept();poll.stop();
        QTimer::singleShot(0,&dialog,[&]{
            if(dialog.result()==QDialog::Accepted||table->item(0,0)->checkState()!=Qt::Checked||table->item(1,0)->checkState()!=Qt::Checked){app.exit(14);return;}
            QFile ready(QString::fromLocal8Bit(argv[2]));ready.open(QIODevice::WriteOnly);ready.close();dialog.accept();
        });
    });
    poll.start(20);QTimer::singleShot(10000,&app,[&]{app.exit(15);});dialog.accept();return app.exec();
}
''')
            (root/'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.21)
project(candidate-ui-test LANGUAGES CXX)
find_package(Qt6 REQUIRED COMPONENTS Widgets)
add_executable(candidate-test test.cpp)
target_compile_features(candidate-test PRIVATE cxx_std_17)
target_link_libraries(candidate-test PRIVATE Qt6::Widgets)
''')
            for command in (['cmake','-S',str(root),'-B',str(root/'build')],['cmake','--build',str(root/'build'),'--parallel','2']):
                result=subprocess.run(command, check=False,capture_output=True,text=True,timeout=120)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(root/'build/candidate-test'),str(root/'backend.py'),str(root/'ready')], check=False,env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_FORCE_STDERR_LOGGING='1'),capture_output=True,text=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
