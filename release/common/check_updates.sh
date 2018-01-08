check_updates () {
  # called with 7 args - platform, source package, target package, update package, old updater boolean,
  # a path to the updater binary to use for the tests, and update-settings.ini values
  update_platform=$1
  source_package=$2
  target_package=$3
  locale=$4
  use_old_updater=$5
  updater=$6
  mar_channel_IDs=$7

  # cleanup
  rm -rf source/*
  rm -rf target/*

  unpack_build $update_platform source "$source_package" $locale '' $mar_channel_IDs
  if [ "$?" != "0" ]; then
    echo "FAILED: cannot unpack_build $update_platform source $source_package"
    return 1
  fi
  unpack_build $update_platform target "$target_package" $locale 
  if [ "$?" != "0" ]; then
    echo "FAILED: cannot unpack_build $update_platform target $target_package"
    return 1
  fi
  
  case $update_platform in
      Darwin_ppc-gcc | Darwin_Universal-gcc3 | Darwin_x86_64-gcc3 | Darwin_x86-gcc3-u-ppc-i386 | Darwin_x86-gcc3-u-i386-x86_64 | Darwin_x86_64-gcc3-u-i386-x86_64) 
          platform_dirname="*.app"
          ;;
      WINNT*) 
          platform_dirname="bin"
          ;;
      Linux_x86-gcc | Linux_x86-gcc3 | Linux_x86_64-gcc3) 
          platform_dirname=`echo $product | tr '[A-Z]' '[a-z]'`
          ;;
  esac
  case `uname` in
      Darwin)
          binary_file_pattern='^Binary files'
          ;;
      MINGW*)
          binary_file_pattern='^Files.*and.*differ$'
          ;;
      Linux)
          binary_file_pattern='^Binary files'
          ;;
  esac

  if [ -f update/update.status ]; then rm update/update.status; fi
  if [ -f update/update.log ]; then rm update/update.log; fi

  if [ -d source/$platform_dirname ]; then
    if [ `uname | cut -c-5` == "MINGW" ]; then
      # windows
      # change /c/path/to/pwd to c:\\path\\to\\pwd
      four_backslash_pwd=$(echo $PWD | sed -e 's,^/\([a-zA-Z]\)/,\1:/,' | sed -e 's,/,\\\\,g')
      two_backslash_pwd=$(echo $PWD | sed -e 's,^/\([a-zA-Z]\)/,\1:/,' | sed -e 's,/,\\,g')
      cwd="$two_backslash_pwd\\source\\$platform_dirname"
      update_abspath="$two_backslash_pwd\\update"
    else
      # not windows
      # use ls here, because mac uses *.app, and we need to expand it
      cwd=$(ls -d $PWD/source/$platform_dirname)
      update_abspath="$PWD/update"
    fi

    cd source/$platform_dirname
    set -x
    "$updater" "$update_abspath" "$cwd" "$cwd" 0
    set +x
    cd ../..
  else
    echo "FAIL: no dir in source/$platform_dirname"
    return 1
  fi

  cat update/update.log
  update_status=`cat update/update.status`

  if [ "$update_status" != "succeeded" ]
  then
    echo "FAIL: update status was not successful: $update_status"
    return 1
  fi

  # If we were testing an OS X mar on Linux, the unpack step copied the
  # precomplete file from Contents/Resources to the root of the install
  # to ensure the Linux updater binary could find it. However, only the
  # precomplete file in Contents/Resources was updated, which means
  # the copied version in the root of the install will usually have some
  # differences between the source and target. To prevent this false
  # positive from failing the tests, we simply remove it before diffing.
  # The precomplete file in Contents/Resources is still diffed, so we
  # don't lose any coverage by doing this.
  cd `echo "source/$platform_dirname"`
  if [[ -f "Contents/Resources/precomplete" && -f "precomplete" ]]
  then
    rm "precomplete"
  fi
  cd ../..
  cd `echo "target/$platform_dirname"`
  if [[ -f "Contents/Resources/precomplete" && -f "precomplete" ]]
  then
    rm "precomplete"
  fi
  cd ../..

  diff -r source/$platform_dirname target/$platform_dirname  > results.diff
  diffErr=$?
  cat results.diff
  grep ^Only results.diff | sed 's/^Only in \(.*\): \(.*\)/\1\/\2/' | \
  while read to_test; do
    if [ -d "$to_test" ]; then 
      echo Contents of $to_test dir only in source or target
      find "$to_test" -ls | grep -v "${to_test}$"
    fi
  done
  grep "$binary_file_pattern" results.diff > /dev/null
  grepErr=$?
  if [ $grepErr == 0 ]
  then
    echo "FAIL: binary files found in diff"
    return 1
  elif [ $grepErr == 1 ]
  then
    if [ -s results.diff ]
    then
      echo "WARN: non-binary files found in diff"
      return 2
    fi
  else
    echo "FAIL: unknown error from grep: $grepErr"
    return 3
  fi
  if [ $diffErr != 0 ]
  then
    echo "FAIL: unknown error from diff: $diffErr"
    return 3
  fi
}
