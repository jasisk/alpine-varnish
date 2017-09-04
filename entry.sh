#!/bin/sh

: ${VARNISH_OPTS:='-j unix -a "${VARNISH_BIND_ADDR:-0.0.0.0}:${VARNISH_BIND_PORT:-6801}" -F -P /var/run/varnish.pid -s "malloc,${VARNISH_MALLOC_SIZE:-256m}"'}

if [ -n "${VARNISH_BACKEND}" ]; then
  VARNISH_OPTS=${VARNISH_OPTS}' -b ${VARNISH_BACKEND}'
else
  VARNISH_OPTS=${VARNISH_OPTS}' -f "/etc/varnish/${VARNISH_VCL_CONF:-default.vcl}"'
fi

if [ "$1" = 'varnishd' ]; then
  exec "$@" `eval "echo ${VARNISH_OPTS}"`
fi

case "$1" in
  varnish*)
    /sbin/su-exec varnish:varnish "$@"
    ;;
  *)
    exec "$@"
esac
