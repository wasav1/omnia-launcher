#include "sessiontoken.h"

#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <qqml.h>

class OmniaSessionPlugin final : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char *uri) override
    {
        qmlRegisterSingletonType<SessionToken>(uri, 1, 0, "SessionToken",
            [](QQmlEngine *engine, QJSEngine *) -> QObject * {
                return new SessionToken(engine);
            });
    }
};

#include "plugin.moc"
