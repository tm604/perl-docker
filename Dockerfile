# This is the layer that can run things
FROM debian:buster as base
# Some standard server-like config used everywhere
ENV TZ=UTC
ENV DEBIAN_FRONTEND=noninteractive
ENV PERL_VERSION="5.30.2"

# For local development it's convenient to have a proxy, we'd want to drop
# this for any real images published externally.
RUN [ -n "$DEBIAN_PROXY" ] \
  && (echo "Acquire::http::Proxy \"http://$DEBIAN_PROXY\";" > /etc/apt/apt.conf.d/30proxy) \
  && (echo "Acquire::http::Proxy::ppa.launchpad.net DIRECT;" >> /etc/apt/apt.conf.d/30proxy) \
  || echo "No local Debian proxy configured"

RUN apt-get update \
 && apt-get -y -q --no-install-recommends install git openssh-client curl sudo lsb-release socat ca-certificates \
 && apt-get -y -q --no-install-recommends dist-upgrade \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/* \
# Locale support is probably quite useful in some cases, but
# let's let individual builds decide that via aptfile config
# && echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen \
# && locale-gen \
 && mkdir -p /etc/ssh/ \
 && ssh-keygen -F github.com || ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts

# This includes extra build deps
FROM base as builder
RUN apt-get update \
 && apt-get -y -q --no-install-recommends install build-essential make gcc git openssh-client wget libssl-dev libz-dev \
 && apt-get -y -q --no-install-recommends dist-upgrade \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# We build a recent Perl version here
FROM builder as perl-builder
RUN curl -L https://raw.githubusercontent.com/tokuhirom/Perl-Build/master/perl-build | perl - --noman -j2 $PERL_VERSION /opt/perl-$PERL_VERSION/ \
 && curl -L https://cpanmin.us > /opt/perl-$PERL_VERSION/bin/cpanm \
 && chmod +x /opt/perl-$PERL_VERSION/bin/cpanm

# Used for the real images
FROM builder as module-builder
COPY --from=perl-builder /opt/perl-$PERL_VERSION /opt/perl-$PERL_VERSION
ENV PATH="/opt/perl-$PERL_VERSION/bin:/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin:/usr/local/sbin"
RUN mkdir -p /opt/app/
WORKDIR /opt/app/
ONBUILD COPY cpanfile aptfile /opt/app/
# Install everything in the aptfile first, as system deps, then
# go through the CPAN deps. Once those are all done, remove anything
# that we would have pulled in as a build dep (compilers, for example)
# unless they happened to be in the aptfile.
ONBUILD RUN if [ -r /opt/apt/aptfile ]; then \
            apt-get -y -q update \
         && apt-get -y -q --no-install-recommends install $(cat aptfile); \
            fi \
         && cpanm -n --installdeps --with-recommends . \
         && apt-get purge -y -q $(perl -le'@seen{split " ", "" . do { local ($/, @ARGV) = (undef, "aptfile"); <> }} = () if -r "aptfile"; print for grep { !exists $seen{$_} } qw(build-essential make gcc git openssh-client wget libssl-dev libz-dev)')
ONBUILD COPY . /opt/app/
ENTRYPOINT [ "perl", "app.pl" ]

