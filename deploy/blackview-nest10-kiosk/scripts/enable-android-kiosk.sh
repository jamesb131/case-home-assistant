#!/bin/sh
set -eu

adb get-state >/dev/null
adb shell cmd package set-home-activity com.casehome.kiosk/.MainActivity
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
echo 'CASE Kiosk is now the selected Home activity.'
echo 'Rollback: scripts/rollback-android-kiosk.sh'
