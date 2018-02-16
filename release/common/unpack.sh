#!/bin/bash

function cleanup() { 
    hdiutil detach ${DEV_NAME} || 
      { sleep 5 && hdiutil detach ${DEV_NAME} -force; }; 
    return $1 && $?; 
};

unpack_build () {
    unpack_platform="$1"
    dir_name="$2"
    pkg_file="$3"
    locale=$4
    unpack_jars=$5
    update_settings_string=$6

    if [ ! -f "$pkg_file" ]; then
      return 1
    fi 
    mkdir -p $dir_name
    pushd $dir_name > /dev/null
    case $unpack_platform in
        mac|mac64|mac-ppc|Darwin_ppc-gcc|Darwin_Universal-gcc3|Darwin_x86_64-gcc3|Darwin_x86-gcc3-u-ppc-i386|Darwin_x86-gcc3-u-i386-x86_64|Darwin_x86_64-gcc3-u-i386-x86_64)
            os=`uname`
            # How we unpack a dmg differs depending on which platform we're on.
            if [[ "$os" == "Darwin" ]]
            then
                cd ../
                echo "installing $pkg_file"
                ../common/unpack-diskimage.sh "$pkg_file" mnt $dir_name
            else
                7z x ../"$pkg_file" > /dev/null
                if [ `ls -1 | wc -l` -ne 1 ]
                then
                    echo "Couldn't find .app package"
                    return 1
                fi
                unpack_dir=`ls -1`
                mv "${unpack_dir}"/*.app .
                rm -rf "$unpack_dir"
                appdir=`ls -1d *.app`
                # The updater guesses the location of these files based on
                # its own target architecture, not the mar. If we're not
                # unpacking mac-on-mac, we need to copy them so it can find
                # them. It's important to copy (and not move), because when
                # we diff the installer vs updated build afterwards, the
                # installer version will have them in their original place.
                cp "${appdir}/Contents/Resources/update-settings.ini" "${appdir}/update-settings.ini"
                cp "${appdir}/Contents/Resources/precomplete" "${appdir}/precomplete"
            fi
            update_settings_file=`find . -name update-settings.ini`
            ;;
        win32|win64|WINNT_x86-msvc|WINNT_x86-msvc-x86|WINNT_x86-msvc-x64|WINNT_x86_64-msvc|WINNT_x86_64-msvc-x64)
            7z x ../"$pkg_file" > /dev/null
            if [ -d localized ]
            then
              mkdir bin/
              cp -rp nonlocalized/* bin/
              cp -rp localized/*    bin/
              rm -rf nonlocalized
              rm -rf localized
              if [ $(find optional/ | wc -l) -gt 1 ]
              then 
                cp -rp optional/*     bin/
                rm -rf optional
              fi
            elif [ -d core ]
            then
              mkdir bin/
              cp -rp core/* bin/
              rm -rf core
            else
              for file in *.xpi
              do
                unzip -o $file > /dev/null
              done
              unzip -o ${locale}.xpi > /dev/null
            fi
            update_settings_file='bin/update-settings.ini'
            ;;
        linux-i686|linux-x86_64|linux|linux64|Linux_x86-gcc|Linux_x86-gcc3|Linux_x86_64-gcc3)
            if `echo $pkg_file | grep -q "tar.gz"`
            then
                tar xfz ../"$pkg_file" > /dev/null
            elif `echo $pkg_file | grep -q "tar.bz2"`
            then
                tar xfj ../"$pkg_file" > /dev/null
            else
                echo "Unknown package type for file: $pkg_file"
                exit 1
            fi
            update_settings_file=`echo $product | tr '[A-Z]' '[a-z]'`'/update-settings.ini'
            ;;
    esac

    if [ ! -z $unpack_jars ]; then
        for f in `find . -name '*.jar' -o -name '*.ja'`; do
            unzip -o "$f" -d "$f.dir" > /dev/null
        done
    fi

    if [ ! -z $update_settings_string ]; then
       echo "Modifying update-settings.ini"
       cat  $update_settings_file | sed -e "s/^ACCEPTED_MAR_CHANNEL_IDS.*/ACCEPTED_MAR_CHANNEL_IDS=${update_settings_string}/" > ${update_settings_file}.new
       diff -u $update_settings_file{,.new}
       echo " "
       rm ${update_settings_file}
       mv $update_settings_file{.new,}
    fi

    popd > /dev/null

}
