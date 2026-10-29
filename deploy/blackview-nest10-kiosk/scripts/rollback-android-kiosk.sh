#!/bin/sh
set -eu

adb get-state >/dev/null
adb shell cmd package set-home-activity com.blackview.iot.calendar/.ui.LauncherActivity
adb shell am force-stop com.casehome.kiosk
adb shell am start -n com.blackview.iot.calendar/.ui.LauncherActivity
echo 'The original Blackview calendar launcher is active again.'
