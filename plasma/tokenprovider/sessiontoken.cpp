#include "sessiontoken.h"

#include <QFile>
#include <QStandardPaths>

SessionToken::SessionToken(QObject *parent)
    : QObject(parent)
{
    path_ = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation) + QStringLiteral("/omnia/token");
    value_ = read();
    refresh_.setInterval(1000);
    connect(&refresh_, &QTimer::timeout, this, [this] {
        const QString next = read();
        if (next != value_) {
            value_ = next;
            emit valueChanged();
        }
    });
    refresh_.start();
}

QString SessionToken::value() const
{
    return value_;
}

QString SessionToken::read() const
{
    QFile file(path_);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return {};
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}
