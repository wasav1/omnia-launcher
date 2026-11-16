#pragma once

#include <QObject>
#include <QTimer>

class SessionToken final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString value READ value NOTIFY valueChanged)

public:
    explicit SessionToken(QObject *parent = nullptr);
    QString value() const;

signals:
    void valueChanged();

private:
    QString read() const;
    QString path_;
    QString value_;
    QTimer refresh_;
};
