# Perl base image

This image is intended as a base that will automatically install
any dependencies then run an `app.pl` Perl script.

It expects two files:

- `aptfile` - list of Debian packages to install via `apt-get`
- `cpanfile` - CPAN modules to install, as defined by [the cpanfile spec](https://metacpan.org/pod/cpanfile)

