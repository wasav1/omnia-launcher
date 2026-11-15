#!/bin/bash
gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.unloadEffect glass
gdbus call --session --dest org.kde.KWin --object-path /Effects --method org.kde.kwin.Effects.loadEffect blur
