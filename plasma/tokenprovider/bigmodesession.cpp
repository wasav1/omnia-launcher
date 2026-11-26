#include "bigmodesession.h"

#include <QCursor>
#include <QDir>
#include <QEvent>
#include <QFile>
#include <QGuiApplication>

#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>

BigModeSession::~BigModeSession()
{
    releaseWindow();
}

void BigModeSession::releaseWindow()
{
    if (m_window) {
        m_window->removeEventFilter(this);
        disconnect(m_window, nullptr, this, nullptr);
    }
    if (m_cursorOverridden) {
        QGuiApplication::restoreOverrideCursor();
        m_cursorOverridden = false;
    }
    if (m_lock >= 0) {
        close(m_lock);
        m_lock = -1;
    }
    m_window = nullptr;
}

void BigModeSession::setWindow(QWindow *window)
{
    if (m_window == window)
        return;
    releaseWindow();
    m_window = window;
    if (window) {
        const auto xdg = qEnvironmentVariable("XDG_RUNTIME_DIR");
        const auto runtime = QDir::isAbsolutePath(xdg)
            ? xdg + QStringLiteral("/omnia")
            : QDir::tempPath() + QStringLiteral("/omnia-") + QString::number(getuid());
        QDir().mkpath(runtime);
        const auto path = QFile::encodeName(runtime + QStringLiteral("/big-mode.lock"));
        m_lock = open(path.constData(), O_CREAT | O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (m_lock >= 0 && flock(m_lock, LOCK_SH) != 0) {
            close(m_lock);
            m_lock = -1;
        }
        window->installEventFilter(this);
        connect(window, &QWindow::activeChanged, this, &BigModeSession::updateCursor);
        connect(window, &QWindow::visibleChanged, this, &BigModeSession::updateCursor);
        updateCursor();
    }
    emit windowChanged();
}

void BigModeSession::setPointerHidden(bool hidden)
{
    if (m_pointerHidden == hidden)
        return;
    m_pointerHidden = hidden;
    updateCursor();
    emit pointerHiddenChanged();
}

void BigModeSession::updateCursor()
{
    const bool hide = m_pointerHidden && m_window && m_window->isActive() && m_window->isVisible();
    if (hide == m_cursorOverridden)
        return;
    if (hide)
        QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));
    else
        QGuiApplication::restoreOverrideCursor();
    m_cursorOverridden = hide;
}

bool BigModeSession::eventFilter(QObject *object, QEvent *event)
{
    if (object == m_window && (event->type() == QEvent::MouseMove || event->type() == QEvent::MouseButtonPress
                              || event->type() == QEvent::Wheel))
        emit mouseUsed();
    return false;
}
