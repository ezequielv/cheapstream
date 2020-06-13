#!/bin/sh
#
# Written by Vasiliy Solovey, 2016
#
# Modified by Ezequiel Valenzuela, 2020
#
set -e

# support functions {{{
prgname="${0##*/}"

echo_to_stderr()
{
  echo "$prgname:" "$@" 1>&2
}

usage()
{
  cat <<EOS
Syntax:
  $prgname [arm|x86]

EOS
  exit 1
}

info()
{
  echo_to_stderr "[info]" "$@"
}

error()
{
  echo_to_stderr "ERROR:" "$@"
  return 1
}

die()
{
  error "$@" || exit 1
}

# args: DIRECTORY
mkdir_clean()
{
  l_dir="$1"
  [ -n "${l_dir}" ] \
    || die "mkdir_clean(): invalid args: please specify a directory pathname"

  if [ -d "${l_dir}/" ] ; then
    rm -fr "${l_dir}" \
      || error "could not remove existing directory '${l_dir}'" \
      || return $?
  fi
  [ ! -e "${l_dir}" ] \
    || error "pathname '${l_dir}' already exists, but it is not a directory." \
    || return $?
  mkdir -pv "${l_dir}"
}

unset g_acestream_apk

# updates g_acestream_apk environment variable.
# returns 0 if there is a valid value in that variable on exit, non-zero
# otherwise.
set_acestream_app_cond()
{
  [ -z "${g_acestream_apk}" ] || return 0
  [ -n "${1}" -a -f "${1}" -a -r "${1}" ] \
    || return $?
  g_acestream_apk="${1}"
}

# }}}

ARCH_OWN="$1"
ARCH="$ARCH_OWN"
case "$ARCH" in
  arm | armv7 )
    ARCH="armv7"
    ARCH_OWN="arm"
    ;;
  x86 )
    : ;;
  '' )
    usage ;;
  * )
    die "unsupported/unrecognised architecture id: '${ARCH}'" ;;
esac
info "ARCH='${ARCH}'"

ARCH_EXT_LIST="$ARCH"
case "$ARCH_EXT_LIST" in
  armv7 )
    ARCH_EXT_LIST="armeabiv7a armeabi-v7a" ;;
esac
info "ARCH_EXT_LIST='${ARCH_EXT_LIST}'"

: "${BUILD_DIR:=build_dir}"
: "${DIST_DIR:=dist}"

LATEST_ANDROID_ENGINE_URI="http://dl.acestream.org/products/acestream-engine/android/$ARCH/latest"

startdir="${0%/*}"
[ -n "${startdir}" -a "${startdir}" != "$0" ] \
  || startdir="."
case "$startdir" in
  /* ) : ;;
  . ) unset startdir ;;
esac
case "$startdir" in
  /* ) : ;;
  '' | * )
    startdir="$PWD${startdir:+/}${startdir}" ;;
esac

cd "$startdir"
info "working directory: '${PWD}' ('${startdir}')"

info "Cleaning up..."
mkdir_clean "$BUILD_DIR"
mkdir_clean "$DIST_DIR"

: "${DOWNLOADS_DIR:=$PWD/downloads}"
info "downloads directory: '${DOWNLOADS_DIR}'"
[ -n "${DOWNLOADS_DIR}" -a ! -d "${DOWNLOADS_DIR}/" ] \
  && mkdir -pv "${DOWNLOADS_DIR}"

cd $BUILD_DIR
info "building in directory: '${PWD}'"

# use the environment variable ACESTREAM_APK, if non-empty.
if [ -n "${ACESTREAM_APK}" ] ; then
  info "attempting to use specified ACESTREAM_APK: '${ACESTREAM_APK}'"
  case "${ACESTREAM_APK}" in
    # absolute path: leave unmodified
    /* )
      set_acestream_app_cond "${ACESTREAM_APK}" \
        || :
      ;;
    # relative paths: try to find the file
    * )
      for t_basedir in \
        "$startdir" \
        "$DOWNLOADS_DIR" \
        # end
      do
        t_f="${t_basedir:+${t_basedir}}/${ACESTREAM_APK}"
        set_acestream_app_cond "${t_f}" \
          || continue
        break
      done
      ;;
  esac
  [ -n "${g_acestream_apk}" ] \
    || f_abort "could not find a (valid) file for the specified value of ACESTREAM_APK ('${ACESTREAM_APK}')"
fi

if [ -z "${g_acestream_apk}" ] ; then
  g_acestream_apk="${DOWNLOADS_DIR:+${DOWNLOADS_DIR}/}acestream.apk"
  if [ -f "${g_acestream_apk}" -a -s "${g_acestream_apk}" ] ; then
    info "found previously downloaded acestream apk file: '${g_acestream_apk}'. skipping download."
  else
    echo "Downloading latest AceStream engine for Android..."
    wget "$LATEST_ANDROID_ENGINE_URI" -O "${g_acestream_apk}"
  fi
fi
info "using acestream apk file: '${g_acestream_apk}'"

info "Unpacking..."
mkdir -pv acestream_bundle
unzip -q "${g_acestream_apk}" -d acestream_bundle

info "Extracting resources..."
mkdir acestream_engine
for t_basefname in \
  private_py.zip \
  private_res.zip \
  public_res.zip \
  # end
do
  info "attepmting to find and extract the archive: '*${t_basefname}' . . ."
  unset t_processed

  for t_archpref in ${ARCH_EXT_LIST} ''
  do
    for t_basedir in acestream_bundle
    do
      for t_topdir in \
        "res/raw" \
        "assets/engine" \
        # end
      do
        t_fname="${t_basedir:+${t_basedir}/}${t_topdir:+${t_topdir}/}${t_archpref:+${t_archpref}_}${t_basefname}"
        [ -e "${t_fname}" ] || continue

        info " found archive: '${t_fname}'. extracting . . ."
        t_processed=x
        unzip -q "${t_fname}" -d acestream_engine \
          || die "failed to decompress the archive '${t_fname}'"

        [ -n "${t_processed}" ] && break
      done
      [ -n "${t_processed}" ] && break
    done
    [ -n "${t_processed}" ] && break
  done
  [ -n "${t_processed}" ] \
    || die "could not find an archive based on the basename '${t_basefname}'"
done

info "Patching Python..."
mkdir -pv python27
unzip -q acestream_engine/python/lib/python27.zip -d python27
cp -rf ../mods/python27/* python27/

info "Removing spurious *.py[co] (python) files . . ."
find python27/ -iname '*.py[co]' -print0 | sort -z | xargs -0r --verbose rm -v

info "Patching AceStream engine..."
cp -f ../mods/acestreamengine/* acestream_engine/
chmod +x acestream_engine/python/bin/python

info "Bundling Python..."
cd python27
zip -q -r python27.zip *
mv -f python27.zip ../acestream_engine/python/lib/
cd ..

info "Making distributable..."
cd "${startdir}"
mkdir -pv "$DIST_DIR/androidfs"
cp -r chroot/* "$DIST_DIR/androidfs/"
cp -r -f "platform/${ARCH_OWN}/"* "$DIST_DIR/androidfs/"
cp scripts/start_acestream.sh "$DIST_DIR/"
cp scripts/stop_acestream.sh "$DIST_DIR/"
cp scripts/acestream-user.conf "$DIST_DIR/"
cp scripts/acestream.sh "$DIST_DIR/androidfs/system/bin/"
mv "$BUILD_DIR/acestream_engine/"* "$DIST_DIR/androidfs/data/data/org.acestream.media/files/"

info "Done!"
