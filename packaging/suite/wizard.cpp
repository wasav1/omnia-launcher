#include <QApplication>
#include <QCheckBox>
#include <QCloseEvent>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QLabel>
#include <QIcon>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QLocale>
#include <QRegularExpression>
#include <QTranslator>
#include <QProcess>
#include <QProgressBar>
#include <QPushButton>
#include <QPixmap>
#include <QVBoxLayout>
#include <QWizard>

static QProcessEnvironment hostEnvironment()
{
    auto env = QProcessEnvironment::systemEnvironment();
    for (const auto *key : {"LD_LIBRARY_PATH", "QT_PLUGIN_PATH", "QT_QPA_PLATFORM_PLUGIN_PATH"})
        env.remove(QString::fromLatin1(key));
    return env;
}

class SuiteWizard : public QWizard {
public:
    bool applying = false;
    void reject() override { if (!applying) QWizard::reject(); }
    void closeEvent(QCloseEvent *event) override {
        if (applying) event->ignore(); else QWizard::closeEvent(event);
    }
};

class GatePage : public QWizardPage {
public:
    bool ready = false;
    bool isComplete() const override { return ready; }
    void complete(bool value) { ready = value; emit completeChanged(); }
};

static QVBoxLayout *layoutFor(QWizardPage *page, const QString &title, const QString &hint)
{
    auto *frame = new QVBoxLayout(page);
    frame->setContentsMargins(24, 22, 24, 14);
    auto *content = new QWidget;
    content->setMaximumWidth(660);
    auto *column = new QHBoxLayout;
    column->addStretch(0);
    column->addWidget(content, 1);
    column->addStretch(0);
    frame->addStretch(1);
    frame->addLayout(column);
    frame->addStretch(2);
    auto *layout = new QVBoxLayout(content);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(14);
    auto *heading = new QLabel(title);
    heading->setObjectName("pageHeading");
    heading->setWordWrap(true);
    layout->addWidget(heading);
    auto *description = new QLabel(hint);
    description->setObjectName("pageHint");
    description->setWordWrap(true);
    layout->addWidget(description);
    return layout;
}

static void launch(const QString &mode)
{
    QProcess process;
    process.setProcessEnvironment(hostEnvironment());
    process.setProgram("/usr/bin/omnia-ui");
    process.setArguments({mode});
    process.startDetached();
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (app.arguments().size() < 2) return 2;
    const QDir payload(app.arguments()[1]);
    QFile versionFile(payload.filePath("version"));
    if (!versionFile.open(QIODevice::ReadOnly)) return 2;
    const QString version = QString::fromUtf8(versionFile.readAll()).trimmed();

    QTranslator translation;
    if (QLocale().language() == QLocale::English && translation.load(payload.filePath("wizard_en_US.qm")))
        app.installTranslator(&translation);
    SuiteWizard wizard;
    wizard.setWindowTitle("Omnia Game Suite");
    wizard.setWindowIcon(QIcon(payload.filePath("omnia-game-suite.svg")));
    wizard.setWizardStyle(QWizard::ModernStyle);
    wizard.setButtonText(QWizard::NextButton, QObject::tr("Continuar"));
    wizard.setButtonText(QWizard::BackButton, QObject::tr("Atrás"));
    wizard.setButtonText(QWizard::FinishButton, QObject::tr("Finalizar"));
    wizard.setButtonText(QWizard::CancelButton, QObject::tr("Cancelar"));
    wizard.setButtonLayout({QWizard::Stretch, QWizard::BackButton, QWizard::NextButton,
                            QWizard::FinishButton, QWizard::CancelButton, QWizard::Stretch});
    wizard.resize(760, 535);
    wizard.setStyleSheet(R"(
        QWidget { background:#101b28; color:#eef5ff; font-size:15px; }
        QLabel { background:transparent; }
        QWizardPage { background:#101b28; }
        QLabel#pageHeading { font-size:26px; font-weight:700; }
        QLabel#pageHint { color:#abc2d9; }
        QPushButton#primaryAction { background:#266580; border-color:#4e9fbc; font-weight:600; }
        QPushButton#primaryAction:hover { background:#357b96; }
        QPushButton#primaryAction:disabled { background:#1a2a3b; border-color:#304965; }
        QProgressBar { background:#172839; border:1px solid #3a536e; border-radius:5px; text-align:center; }
        QProgressBar::chunk { background:#4589b5; border-radius:4px; }
        QPushButton { background:#234059; border:1px solid #466989; border-radius:8px; padding:8px 18px; }
        QPushButton:hover { background:#315675; }
        QPushButton:disabled { color:#8196aa; background:#1a2a3b; }
        QLineEdit, QPlainTextEdit { background:#172839; border:1px solid #3a536e; border-radius:7px; padding:7px; }
    )");

    QProcess probe;
    probe.setProcessEnvironment(hostEnvironment());
    probe.start("/usr/bin/pacman", {"-Q", "omnia-app"});
    probe.waitForFinished(2000);
    const QStringList fields = QString::fromUtf8(probe.readAllStandardOutput()).simplified().split(' ');
    QString previous = fields.size() == 2 ? fields[1] : QString();
    if (previous.isEmpty()) {
        QFile legacy(QDir::home().filePath(".local/lib/omnia/omnia/__init__.py"));
        if (legacy.open(QIODevice::ReadOnly)) {
            const QRegularExpression pattern(R"(__version__\s*=\s*["']([0-9.]+)["'])");
            previous = pattern.match(QString::fromUtf8(legacy.readAll())).captured(1);
        }
    }
    const bool updating = !previous.isEmpty();
    bool upgradeAvailable = true;
    if (updating && QFileInfo("/usr/bin/vercmp").isExecutable()) {
        probe.start("/usr/bin/vercmp", {version, previous});
        bool valid = false;
        const int comparison = probe.waitForFinished(2000)
            ? QString::fromUtf8(probe.readAllStandardOutput()).trimmed().toInt(&valid) : 0;
        upgradeAvailable = valid && comparison > 0;
    }
    const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP");
    const bool hyprland = desktop.contains("Hyprland", Qt::CaseInsensitive)
        || !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE");
    const bool compatible = hyprland && QFileInfo::exists("/usr/bin/pacman") && QFileInfo::exists("/usr/bin/pkexec");

    auto *system = new GatePage;
    auto *systemLayout = layoutFor(system, "Omnia Game Suite", updating ? QObject::tr("Compatibilidad") : QObject::tr("Compatibilidad · Etapa 1 de 5"));
    auto *brand = new QLabel;
    const QPixmap branding(payload.filePath("omnia-game-suite.svg"));
    brand->setPixmap(branding.scaled(288, 81, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    systemLayout->insertWidget(0, brand, 0, Qt::AlignLeft);
    auto *summary = new QLabel(compatible
        ? (previous.isEmpty() ? QObject::tr("Hyprland detectado. Se instalarán Desktop, Big Mode y el servicio local.")
            : QObject::tr("Omnia %1 detectado. Este instalador ofrece %2. Se conservarán tus juegos, preferencias y cuentas.").arg(previous, version))
        : QObject::tr("Esta edición necesita una sesión de Hyprland sobre Arch Linux o un derivado, con pacman y Polkit."));
    if (compatible && !upgradeAvailable)
        summary->setText(QObject::tr("Omnia %1 ya está instalado. Este asistente contiene %2.").arg(previous, version));
    summary->setWordWrap(true);
    systemLayout->addWidget(summary);
    auto *systemDetails = new QLabel(compatible
        ? QObject::tr("Hyprland · Compatible\nDesktop, Big Mode y servicio de Omnia · Incluidos")
        : QObject::tr("Hyprland y pacman · Requeridos"));
    systemDetails->setStyleSheet("padding: 14px; background: #17283a; border: 1px solid #304965; border-radius: 9px;");
    systemDetails->setWordWrap(true);
    systemLayout->addWidget(systemDetails);
    systemLayout->addStretch();
    system->complete(compatible && upgradeAvailable);
    wizard.addPage(system);

    QLineEdit *installRoot = nullptr;
    QLineEdit *libraryRoot = nullptr;
    QCheckBox *scan = nullptr;
    QCheckBox *dux = nullptr;
    if (!updating) {
        auto *library = new QWizardPage;
        auto *libraryLayout = layoutFor(library, QObject::tr("Preparar la biblioteca"), QObject::tr("Etapa 2 de 5 · Puedes configurar estas carpetas más tarde."));
        auto folder = [&](const QString &label) {
            auto *field = new QLineEdit;
            field->setReadOnly(true);
            field->setPlaceholderText(label);
            auto *choose = new QPushButton(QObject::tr("Elegir carpeta"));
            auto *reset = new QPushButton(QObject::tr("Quitar"));
            auto *row = new QHBoxLayout;
            row->addWidget(field, 1);
            row->addWidget(choose);
            row->addWidget(reset);
            libraryLayout->addLayout(row);
            QObject::connect(reset, &QPushButton::clicked, field, &QLineEdit::clear);
            QObject::connect(choose, &QPushButton::clicked, field, [field, label] {
                const auto path = QFileDialog::getExistingDirectory(field, label, QDir::homePath());
                if (!path.isEmpty()) field->setText(path);
            });
            return field;
        };
        installRoot = folder(QObject::tr("Carpeta para instalar ports"));
        libraryRoot = folder(QObject::tr("Carpeta de juegos existente"));
        scan = new QCheckBox(QObject::tr("Buscar juegos al terminar"));
        scan->setChecked(previous.isEmpty());
        libraryLayout->addWidget(scan);
        dux = new QCheckBox(QObject::tr("Integrar el panel rápido de Dux"));
        const bool duxAvailable = QFileInfo::exists("/usr/bin/dms");
        dux->setEnabled(duxAvailable);
        dux->setChecked(duxAvailable);
        libraryLayout->addWidget(dux);
        wizard.addPage(library);
    }

    auto *install = new GatePage;
    auto *installLayout = layoutFor(install, updating ? QObject::tr("Actualizar Omnia") : QObject::tr("Revisar e instalar"),
        updating ? QObject::tr("Polkit solicita autorización para actualizar los paquetes.")
                 : QObject::tr("Etapa 3 de 5 · Polkit solicita autorización para instalar los paquetes."));
    auto *apply = new QPushButton(previous.isEmpty() ? QObject::tr("Instalar Omnia") : QObject::tr("Actualizar Omnia"));
    auto *review = new QLabel;
    review->setWordWrap(true);
    auto *log = new QPlainTextEdit;
    log->setReadOnly(true);
    log->setFixedHeight(152);
    log->hide();
    installLayout->addWidget(review);
    apply->setObjectName("primaryAction");
    auto *progress = new QProgressBar;
    progress->hide();
    installLayout->addWidget(progress);
    installLayout->addWidget(log);
    auto *restart = new QPushButton(QObject::tr("Reiniciar ahora"));
    restart->setObjectName("primaryAction");
    restart->hide();
    auto *actions = new QHBoxLayout;
    actions->addStretch();
    actions->addWidget(apply);
    actions->addWidget(restart);
    installLayout->addLayout(actions);
    auto *process = new QProcess(install);
    process->setProcessEnvironment(hostEnvironment());
    process->setProcessChannelMode(QProcess::MergedChannels);
    bool restarting = false;
    QObject::connect(restart, &QPushButton::clicked, install, [=, &wizard, &restarting] {
        restarting = true;
        wizard.applying = true;
        restart->setEnabled(false);
        progress->setRange(0, 0);
        wizard.button(QWizard::CancelButton)->setEnabled(false);
        process->start("/usr/bin/omnia-suite-update", {"--restart-installed"});
    });
    QObject::connect(apply, &QPushButton::clicked, install, [=, &wizard] {
        apply->setEnabled(false);
        wizard.applying = true;
        wizard.button(QWizard::CancelButton)->setEnabled(false);
        wizard.button(QWizard::BackButton)->setEnabled(false);
        log->clear();
        progress->setRange(0, 0);
        progress->show();
        log->show();
        QStringList arguments{payload.filePath("apply.sh")};
        if (updating)
            arguments << "update";
        else
            arguments << (dux->isChecked() ? "dux" : "") << installRoot->text()
                      << libraryRoot->text() << (scan->isChecked() ? "scan" : "");
        process->start("/usr/bin/bash", arguments);
    });
    QObject::connect(process, &QProcess::readyReadStandardOutput, log, [=] {
        log->appendPlainText(QString::fromUtf8(process->readAllStandardOutput()).trimmed());
    });
    QObject::connect(process, &QProcess::errorOccurred, install, [=, &wizard, &restarting](QProcess::ProcessError error) {
        if (error != QProcess::FailedToStart) return;
        log->appendPlainText(process->errorString());
        wizard.applying = false;
        wizard.button(QWizard::CancelButton)->setEnabled(true);
        progress->hide();
        if (restarting) restart->setEnabled(true);
        else {
            apply->setEnabled(true);
            wizard.button(QWizard::BackButton)->setEnabled(true);
        }
    });
    QObject::connect(process, &QProcess::finished, install, [=, &wizard, &restarting](int code, QProcess::ExitStatus status) {
        const bool success = code == 0 && status == QProcess::NormalExit;
        wizard.applying = false;
        wizard.button(QWizard::CancelButton)->setEnabled(true);
        progress->setRange(0, 100);
        progress->setValue(success ? 100 : 0);
        if (restarting) {
            if (success) wizard.accept();
            else restart->setEnabled(true);
            return;
        }
        if (updating && success) {
            apply->hide();
            restart->show();
            restart->setFocus();
        }
        install->complete(success && !updating);
        apply->setEnabled(!success);
        wizard.button(QWizard::BackButton)->setEnabled(!success);
        log->appendPlainText(success ? QObject::tr("Omnia está instalado.") : QObject::tr("La instalación no se completó."));
    });
    const int installPage = wizard.addPage(install);
    QObject::connect(&wizard, &QWizard::currentIdChanged, install, [=, &wizard](int page) {
        if (updating) wizard.button(QWizard::FinishButton)->setVisible(false);
        if (page != installPage) return;
        QStringList choices{QObject::tr("Omnia %1 · Desktop, Big Mode y servicio local").arg(version)};
        if (!updating && dux->isChecked()) choices << QObject::tr("Panel rápido de Dux");
        if (installRoot && !installRoot->text().isEmpty()) choices << QObject::tr("Destino de los ports: %1").arg(installRoot->text());
        if (libraryRoot && !libraryRoot->text().isEmpty()) choices << QObject::tr("Carpeta de juegos: %1").arg(libraryRoot->text());
        review->setTextFormat(Qt::PlainText);
        review->setText(choices.join('\n'));
    });

    if (!updating) {
        auto *stores = new QWizardPage;
        auto *storeLayout = layoutFor(stores, QObject::tr("Conectar tiendas"), QObject::tr("Etapa 4 de 5 · Opcional. También puedes conectar cuentas desde Ajustes."));
        auto *storeInfo = new QLabel(QObject::tr("Steam, Epic Games, GOG y Amazon Games. Inicia sesión en la ventana de la tienda."));
        storeInfo->setWordWrap(true);
        storeLayout->addWidget(storeInfo);
        auto *connect = new QPushButton(QObject::tr("Abrir cuentas de tiendas"));
        QObject::connect(connect, &QPushButton::clicked, stores, [] { launch("--setup-stores"); });
        storeLayout->addWidget(connect);
        wizard.addPage(stores);

        auto *done = new QWizardPage;
        auto *doneLayout = layoutFor(done, QObject::tr("Omnia está listo"), QObject::tr("Etapa 5 de 5 · Elige cómo empezar."));
        for (const auto &entry : {qMakePair(QObject::tr("Abrir Desktop"), QString("--manager")),
                                 qMakePair(QObject::tr("Abrir Big Mode"), QString("--window"))}) {
            auto *button = new QPushButton(entry.first);
            QObject::connect(button, &QPushButton::clicked, done, [mode = entry.second] { launch(mode); });
            doneLayout->addWidget(button);
        }
        wizard.addPage(done);
    }
    wizard.show();
    return app.exec();
}
