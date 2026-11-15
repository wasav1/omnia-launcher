import QtQuick
import org.kde.taskmanager as TaskManager

// Cuenta las ventanas visibles del escritorio actual (sin contar la propia estantería): 0 = escritorio a la vista.
Item {
    id: w
    property int visibleWindows: 0
    property int coveringWindows: 0        // ventanas maximizadas o en pantalla completa (tapan el launcher)
    TaskManager.VirtualDesktopInfo { id: vdi }
    TaskManager.ActivityInfo { id: ai }
    TaskManager.TasksModel {
        id: tasks
        virtualDesktop: vdi.currentDesktop
        activity: ai.currentActivity
        filterByVirtualDesktop: true
        filterByActivity: true
        groupMode: TaskManager.TasksModel.GroupDisabled
    }
    function recount() {
        var n = 0, c = 0
        for (var i = 0; i < tasks.count; i++) {
            var ix = tasks.index(i, 0)
            if (tasks.data(ix, TaskManager.AbstractTasksModel.IsMinimized) === true) continue      // minimizadas no cuentan
            if (tasks.data(ix, TaskManager.AbstractTasksModel.IsHidden) === true) continue
            var t = String(tasks.data(ix, Qt.DisplayRole))
            if (t.indexOf("Estantería de juegos") < 0) {
                n++
                if (tasks.data(ix, TaskManager.AbstractTasksModel.IsMaximized) === true || tasks.data(ix, TaskManager.AbstractTasksModel.IsFullScreen) === true) c++
            }
        }
        visibleWindows = n
        coveringWindows = c
    }
    Timer { interval: 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: w.recount() }
}
