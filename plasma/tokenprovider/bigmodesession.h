#pragma once

#include <QObject>
#include <QPointer>
#include <QWindow>

class BigModeSession : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QWindow *window READ window WRITE setWindow NOTIFY windowChanged)
    Q_PROPERTY(bool pointerHidden READ pointerHidden WRITE setPointerHidden NOTIFY pointerHiddenChanged)

public:
    explicit BigModeSession(QObject *parent = nullptr) : QObject(parent) {}
    ~BigModeSession() override;
    QWindow *window() const { return m_window; }
    void setWindow(QWindow *window);
    bool pointerHidden() const { return m_pointerHidden; }
    void setPointerHidden(bool hidden);

signals:
    void windowChanged();
    void pointerHiddenChanged();
    void mouseUsed();

protected:
    bool eventFilter(QObject *object, QEvent *event) override;

private:
    void updateCursor();
    void releaseWindow();
    QPointer<QWindow> m_window;
    int m_lock = -1;
    bool m_pointerHidden = false;
    bool m_cursorOverridden = false;
};
