#pragma once
#include <QtWidgets>

inline void applyOmniaAppearance(QApplication &app) {
    app.setStyle(QStyleFactory::create("Fusion"));
    QPalette palette;
    palette.setColor(QPalette::Window, QColor("#15171c"));
    palette.setColor(QPalette::WindowText, QColor("#eef1f8"));
    palette.setColor(QPalette::Base, QColor("#1b1e25"));
    palette.setColor(QPalette::AlternateBase, QColor("#222630"));
    palette.setColor(QPalette::Text, QColor("#eef1f8"));
    palette.setColor(QPalette::PlaceholderText, QColor("#8793ab"));
    palette.setColor(QPalette::Button, QColor("#262b35"));
    palette.setColor(QPalette::ButtonText, QColor("#eef1f8"));
    palette.setColor(QPalette::Highlight, QColor("#476cf0"));
    palette.setColor(QPalette::HighlightedText, Qt::white);
    palette.setColor(QPalette::Disabled, QPalette::Text, QColor("#778092"));
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, QColor("#778092"));
    app.setPalette(palette);
    QFont font = app.font(); font.setPointSize(10); app.setFont(font);
    app.setStyleSheet(R"(
        QWizard, QDialog { background: #15171c; color: #eef1f8; }
        QLabel { background: transparent; }
        QLabel#PageTitle { font-size: 27px; font-weight: 700; }
        QLabel#Subtitle, QLabel#Muted { color: #a8b1c3; }
        QLabel#CardTitle { font-size: 15px; font-weight: 600; }
        QFrame#Card { background: #20242c; border: 1px solid #303641; border-radius: 12px; }
        QLabel#Result { color: #bdc9ee; padding: 10px 0; }
        QPushButton { background: #272c36; color: #eef1f8; border: 1px solid #3b4352;
            border-radius: 8px; padding: 9px 17px; min-height: 18px; }
        QPushButton:hover { background: #323a49; border-color: #65738c; }
        QPushButton:pressed { background: #202630; }
        QPushButton:disabled { color: #768093; background: #1e222a; border-color: #2d333e; }
        QPushButton[primary="true"] { background: #476cf0; border-color: #476cf0; font-weight: 600; }
        QPushButton[primary="true"]:hover { background: #5c7df7; }
        QPushButton[primary="true"]:disabled { background: #2b385d; color: #94a1c0; border-color: #2b385d; }
        QLineEdit, QComboBox { background: #181c23; border: 1px solid #424b5b;
            border-radius: 7px; padding: 9px 12px; min-height: 20px; selection-background-color: #476cf0; }
        QLineEdit:focus, QComboBox:focus { border-color: #7190ff; }
        QComboBox::drop-down { border: none; width: 26px; }
        QComboBox QAbstractItemView { background: #252b36; color: #eef1f8; selection-background-color: #384d83; }
        QListWidget, QTableWidget, QTextBrowser, QPlainTextEdit { background: #1b1f27;
            border: 1px solid #353d4b; border-radius: 9px; padding: 8px; color: #e4e9f5; }
        QListWidget::item { padding: 7px; border-radius: 6px; }
        QListWidget::item:selected { background: #2b3c65; color: #ffffff; }
        QPlainTextEdit { font-family: monospace; font-size: 11px; }
        QCheckBox { spacing: 10px; padding: 6px 0; }
        QCheckBox::indicator { width: 18px; height: 18px; }
        QCheckBox::indicator:unchecked { background: #1b1f27; border: 1px solid #6a7890; border-radius: 4px; }
        QProgressBar { background: #292f3a; border: none; border-radius: 4px; min-height: 7px; max-height: 7px; }
        QProgressBar::chunk { background: #6685ff; border-radius: 4px; }
        QTabWidget::pane { border: 1px solid #353d4b; border-radius: 8px; }
        QTabBar::tab { padding: 10px 14px; background: #20242c; }
        QTabBar::tab:selected { background: #303e65; color: #ffffff; }
        QHeaderView::section { background: #252b36; color: #aebbd5; padding: 9px; border: none; }
        QScrollBar:vertical { background: #1b1f27; width: 9px; margin: 0; }
        QScrollBar::handle:vertical { background: #46516a; border-radius: 4px; min-height: 24px; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
        QToolTip { background: #252c39; color: #eef1f8; border: 1px solid #51617e; padding: 6px; }
    )");
}

inline QFrame *omniaCard(const QString &title, const QString &description, QWidget *parent = nullptr) {
    auto card = new QFrame(parent); card->setObjectName("Card");
    auto layout = new QVBoxLayout(card); layout->setContentsMargins(18, 14, 18, 14); layout->setSpacing(6);
    auto heading = new QLabel(title); heading->setObjectName("CardTitle"); layout->addWidget(heading);
    auto text = new QLabel(description); text->setObjectName("Muted"); text->setWordWrap(true); layout->addWidget(text);
    return card;
}
