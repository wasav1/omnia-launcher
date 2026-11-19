#pragma once
#include <QtWidgets>

inline QIcon lucideIcon(const QString &name, const QColor &color = QColor("#edf4f8")) {
    QPixmap glyph(":/lucide/" + name + ".svg");
    if (glyph.isNull()) return {};
    QPainter painter(&glyph);
    painter.setCompositionMode(QPainter::CompositionMode_SourceIn);
    painter.fillRect(glyph.rect(), color);
    painter.end();
    return QIcon(glyph);
}

class OmniaStyle : public QProxyStyle {
public:
    OmniaStyle() : QProxyStyle(QStyleFactory::create("Fusion")) {}
    QIcon standardIcon(StandardPixmap standard, const QStyleOption *option = nullptr,
                       const QWidget *widget = nullptr) const override {
        const QString name = [standard]() -> QString {
            switch (standard) {
            case SP_MessageBoxInformation: return "info";
            case SP_MessageBoxWarning: return "triangle-alert";
            case SP_MessageBoxCritical: return "circle-alert";
            case SP_MessageBoxQuestion: return "circle-help";
            case SP_DialogOkButton: case SP_DialogYesButton: return "check";
            case SP_DialogCancelButton: case SP_DialogCloseButton: case SP_DialogNoButton: return "x";
            case SP_DialogSaveButton: return "save";
            case SP_DialogOpenButton: case SP_DirOpenIcon: return "folder-open";
            case SP_DirIcon: return "folder";
            case SP_DriveHDIcon: return "hard-drive";
            case SP_ArrowLeft: return "arrow-left";
            case SP_ArrowRight: return "arrow-right";
            case SP_ArrowUp: return "arrow-up";
            case SP_ArrowDown: return "arrow-down";
            case SP_TrashIcon: return "trash-2";
            case SP_BrowserReload: return "refresh-cw";
            default: return {};
            }
        }();
        if (!name.isEmpty()) {
            const auto icon = lucideIcon(name);
            if (!icon.isNull()) return icon;
        }
        return QProxyStyle::standardIcon(standard, option, widget);
    }
};

inline QWidget *omniaHeader(const QString &mode, const QString &icon,
                            const QColor &accent, const QPixmap &logo = {}) {
    auto header = new QFrame;
    header->setObjectName("OmniaHeader");
    auto row = new QHBoxLayout(header);
    row->setContentsMargins(16, 11, 16, 11);
    row->setSpacing(12);
    auto mark = new QLabel;
    mark->setPixmap(logo.isNull() ? lucideIcon(icon, accent).pixmap(34, 34)
                                 : logo.scaled(38, 38, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    row->addWidget(mark);
    auto brand = new QVBoxLayout;
    brand->setSpacing(1);
    auto name = new QLabel("OMNIA");
    name->setObjectName("BrandName");
    brand->addWidget(name);
    auto tagline = new QLabel("DESKTOP SUITE");
    tagline->setObjectName("BrandCaption");
    brand->addWidget(tagline);
    row->addLayout(brand);
    row->addStretch();
    auto modeLabel = new QLabel("  " + mode);
    modeLabel->setObjectName("ModeBadge");
    modeLabel->setStyleSheet(QString("color: %1;").arg(accent.name()));
    auto modeIcon = new QLabel;
    modeIcon->setPixmap(lucideIcon(icon, accent).pixmap(18,18));
    row->addWidget(modeIcon);
    row->addWidget(modeLabel);
    return header;
}

inline void applyOmniaAppearance(QApplication &app) {
    app.setStyle(new OmniaStyle);
    QPalette palette;
    palette.setColor(QPalette::Window, QColor("#080d13"));
    palette.setColor(QPalette::WindowText, QColor("#edf4f8"));
    palette.setColor(QPalette::Base, QColor("#101923"));
    palette.setColor(QPalette::AlternateBase, QColor("#141f2b"));
    palette.setColor(QPalette::Text, QColor("#edf4f8"));
    palette.setColor(QPalette::PlaceholderText, QColor("#8793ab"));
    palette.setColor(QPalette::Button, QColor("#192634"));
    palette.setColor(QPalette::ButtonText, QColor("#edf4f8"));
    palette.setColor(QPalette::Highlight, QColor("#336599"));
    palette.setColor(QPalette::HighlightedText, Qt::white);
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor("#778092"));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor("#778092"));
    app.setPalette(palette);
    QFont font = app.font(); font.setPointSize(10); app.setFont(font);
    app.setStyleSheet(R"(
        QWizard, QDialog { background: #080d13; color: #edf4f8; }
        QFrame#OmniaHeader { background: #0b131c; border: 1px solid #253646; border-radius: 12px; }
        QLabel#BrandName { font-size: 20px; font-weight: 750; }
        QLabel#BrandCaption, QLabel#RailCaption { color: #92a5b5; font-size: 10px; font-weight: 650; }
        QLabel#ModeBadge { font-size: 14px; font-weight: 650; }
        QLabel#Kicker { color: #9ad8ff; font-size: 11px; font-weight: 700; }
        QWidget#WizardRail { background: #0b131c; }
        QFrame#RailStep { border: 1px solid transparent; border-radius: 10px; }
        QFrame#RailStep[active="true"] { background: #162b40; border-color: #336599; border-left: 3px solid #67a9dd; }
        QListWidget#SettingsNav { border: none; background: #0b131c; padding: 4px; }
        QListWidget#SettingsNav::item { padding: 12px 9px; }
        QPushButton[danger="true"] { background: #8f423d; border-color: #bb645e; font-weight: 650; }
        QPushButton[danger="true"]:hover { background: #a9504a; }
        QPushButton[danger="true"]:disabled { background: #35252a; border-color: #593638; }
        QFrame#Card[variant="danger"] { background: #24181f; border-color: #754741; }
        QFrame#Card[variant="success"] { background: #12251f; border-color: #2b5947; }
        QLabel { background: transparent; }
        QLabel#PageTitle { font-size: 27px; font-weight: 700; }
        QLabel#Subtitle, QLabel#Muted { color: #a2b3c0; }
        QLabel#CardTitle { font-size: 15px; font-weight: 600; }
        QFrame#Card { background: #101923; border: 1px solid #29394a; border-radius: 12px; }
        QLabel#Result { color: #bdc9ee; padding: 10px 0; }
        QPushButton { background: #141f2b; color: #edf4f8; border: 1px solid #34485d;
            border-radius: 8px; padding: 9px 17px; min-height: 18px; }
        QPushButton:hover { background: #323a49; border-color: #65738c; }
        QPushButton:pressed { background: #202630; }
        QPushButton:disabled { color: #768093; background: #1e222a; border-color: #2d333e; }
        QPushButton[primary="true"] { background: #336599; border-color: #336599; font-weight: 600; }
        QPushButton[primary="true"]:hover { background: #4b87bd; border-color: #4b87bd; }
        QPushButton[primary="true"]:disabled { background: #243f5d; color: #9aafc7; border-color: #243f5d; }
        QPushButton[primary="true"][mode="update"]:enabled { background: #265c4a; border-color: #3c876b; }
        QPushButton[primary="true"][mode="update"]:hover { background: #30755d; }
        QPushButton[primary="true"][mode="settings"]:enabled { background: #4e407f; border-color: #7965b6; }
        QPushButton[primary="true"][mode="settings"]:hover { background: #65559c; }
        QScrollArea, QScrollArea > QWidget > QWidget { background: #080d13; }
        QListWidget::indicator:checked { image: url(:/lucide/check.svg); background: #336599; border-radius: 4px; }
        QLineEdit, QComboBox { background: #0d1620; border: 1px solid #424b5b;
            border-radius: 7px; padding: 9px 12px; min-height: 20px; selection-background-color: #336599; }
        QLineEdit:focus, QComboBox:focus { border-color: #5b8ec1; }
        QComboBox::drop-down { border: none; width: 26px; }
        QComboBox QAbstractItemView { background: #252b36; color: #edf4f8; selection-background-color: #284d73; }
        QListWidget, QTableWidget, QTextBrowser, QPlainTextEdit { background: #101923;
            border: 1px solid #253646; border-radius: 9px; padding: 8px; color: #e4e9f5; }
        QListWidget::item { padding: 7px; border-radius: 6px; }
        QListWidget::item:selected { background: #284d73; color: #ffffff; }
        QPlainTextEdit { font-family: monospace; font-size: 11px; }
        QCheckBox { spacing: 10px; padding: 6px 0; }
        QCheckBox::indicator { width: 18px; height: 18px; }
        QCheckBox::indicator:checked { image: url(:/lucide/check.svg); background: #336599; border-radius: 4px; }
        QComboBox::down-arrow { image: url(:/lucide/chevron-down.svg); width: 15px; height: 15px; }
        QCheckBox::indicator:unchecked { background: #101923; border: 1px solid #6a7890; border-radius: 4px; }
        QProgressBar { background: #292f3a; border: none; border-radius: 4px; min-height: 7px; max-height: 7px; }
        QProgressBar::chunk { background: #4b87bd; border-radius: 4px; }
        QTabWidget::pane { border: 1px solid #253646; border-radius: 8px; }
        QTabBar::tab { padding: 10px 14px; background: #101923; }
        QTabBar::tab:selected { background: #284d73; color: #ffffff; }
        QHeaderView::section { background: #252b36; color: #aebbd5; padding: 9px; border: none; }
        QScrollBar:vertical { background: #101923; width: 9px; margin: 0; }
        QScrollBar::handle:vertical { background: #46516a; border-radius: 4px; min-height: 24px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        QToolTip { background: #252c39; color: #edf4f8; border: 1px solid #51617e; padding: 6px; }
    )");
}

inline QFrame *omniaCard(const QString &title, const QString &description, QWidget *parent = nullptr, const QString &icon = {},
                         const QString &variant = {}) {
    auto card = new QFrame(parent); card->setObjectName("Card");
    card->setProperty("variant", variant);
    auto layout = new QVBoxLayout(card); layout->setContentsMargins(18, 14, 18, 14); layout->setSpacing(6);
    auto heading = new QLabel(title); heading->setObjectName("CardTitle");
    if (icon.isEmpty()) {
        layout->addWidget(heading);
    } else {
        auto header = new QHBoxLayout;
        auto glyph = new QLabel;
        const auto color = variant == "danger" ? QColor("#f08b84") : variant == "success" ? QColor("#6fd6aa") : QColor("#9ad8ff");
        glyph->setPixmap(lucideIcon(icon, color).pixmap(19, 19));
        header->addWidget(glyph);
        header->addWidget(heading, 1);
        layout->addLayout(header);
    }
    auto text = new QLabel(description); text->setObjectName("Muted"); text->setWordWrap(true); layout->addWidget(text);
    return card;
}
