#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw(setsid setgid setuid);
use Data::Dumper;
die "[guestimage file]: $!" unless defined $ARGV[0] && -r $ARGV[0]; 
my %me = ();
me.bdfpattern = '..\:..\..';
@me.kvm = getpwnam('kvm');
me.user = getlogin();
