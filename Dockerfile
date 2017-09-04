FROM alpine:3.6
MAINTAINER Jean-Charles Sisk <jeancharles@gasbuddy.com>

ARG VARNISH_VERSION=4.1.8

# UID/GID 1000 to workaround mount issues + no user
# namespaces (Docker <1.10)
RUN addgroup -S varnish && \
    adduser -S -D -H -h /etc/varnish -s /sbin/nologin -G varnish -g varnish varnish

RUN TMPDIR=$(mktemp -d) && \
    apk -U --no-progress add su-exec pcre libexecinfo gcc musl-dev ncurses-libs && \
    apk --no-progress add -t .buildtools curl make libc-dev libgcc \
        pcre-dev ncurses-dev libedit-dev py-docutils automake autoconf libtool \
        linux-headers libexecinfo-dev && \
    ln -s python3 /usr/bin/python && \
    curl -sSL http://varnish-cache.org/_downloads/varnish-${VARNISH_VERSION}.tgz | tar xz -C "${TMPDIR}" && \
    curl -sSL https://github.com/aondio/libvmod-bodyaccess/archive/4.1/bodyaccess-4.1.tar.gz | tar xz -C "${TMPDIR}" && \
    cd "${TMPDIR}/varnish-${VARNISH_VERSION}" && \
    sed -i '/^struct vpf_fh/i #include <sys/stat.h>' ./include/vpf.h && \
    sed -i '/^CFLAGS[^-]*-Wall -Werror/ s/^/#/' ./configure && \
    sed -i 's/\(defined (__GNUC__)\)/!defined(__arm__) \&\& \1 /' lib/libvarnishcompat/execinfo.c && \
    sed -i 's/ev\[NEEV\]/*ev/' bin/varnishd/waiter/cache_waiter_epoll.c && \
    sed -i '/cache-epoll/a ev = malloc(NEEV * sizeof(struct epoll_event));\nassert(ev != NULL);' bin/varnishd/waiter/cache_waiter_epoll.c && \
    sed -i '/AZ(close(vwe->epfd));/a free(ev);' bin/varnishd/waiter/cache_waiter_epoll.c && \
    ./configure --without-jemalloc && \
    make -j$(grep -c ^processor /proc/cpuinfo 2>/dev/null || 1) && \
    make install && \
    cd "${TMPDIR}/libvmod-bodyaccess-4.1" && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install && \
    apk del .buildtools && \
    rm -rf "${TMPDIR}" /var/cache/apk/* /usr/share/man

RUN chown varnish:varnish /usr/local/var/varnish/

EXPOSE 6801
COPY default.vcl /etc/varnish/
COPY entry.sh /entry.sh

VOLUME /etc/varnish/

ENTRYPOINT ["/entry.sh"]
CMD ["varnishd"]
