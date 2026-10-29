echo "CASE NEST10 SD scan probe reached"

if test -n "${devtype}"; then
  if test -n "${devnum}"; then
    if test -n "${distro_bootpart}"; then
      if test -n "${scriptaddr}"; then
        if test -n "${filesize}"; then
          echo "CASE probe writing a copy of its loaded script"
          if fatwrite ${devtype} ${devnum}:${distro_bootpart} ${scriptaddr} /case-probe/uboot-ran.bin ${filesize}; then
            echo "CASE binary marker written with fatwrite"
          else
            if save ${devtype} ${devnum}:${distro_bootpart} ${scriptaddr} /case-probe/uboot-ran.bin ${filesize}; then
              echo "CASE binary marker written with generic save"
            else
              echo "CASE probe could not write its binary marker"
            fi
          fi
        fi
      fi
      if test -n "${kernel_addr_r}"; then
        echo "CASE probe scanning ${devtype} ${devnum}:${distro_bootpart}"
        if load ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /case-probe/input.txt; then
          if fatwrite ${devtype} ${devnum}:${distro_bootpart} ${kernel_addr_r} /case-probe/uboot-ran.txt ${filesize}; then
            echo "CASE probe marker written to SD"
          else
            echo "CASE probe reached U-Boot, but FAT write support is unavailable"
          fi
        else
          echo "CASE probe guard file was not found on the scanned filesystem"
        fi
      else
        echo "CASE probe stopped: kernel_addr_r is unavailable"
      fi
    else
      echo "CASE probe stopped: distro_bootpart is unavailable"
    fi
  else
    echo "CASE probe stopped: devnum is unavailable"
  fi
else
  echo "CASE probe stopped: devtype is unavailable"
fi

echo "CASE probe pausing for 45 seconds as a visible execution signal"
sleep 45
echo "CASE probe returning to the factory boot flow"
