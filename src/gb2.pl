#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw(setsid setgid setuid);
use Data::Dumper;
die "[guestimage file]: $!" unless defined $ARGV[0] && -r $ARGV[0]; 
my %me = ();
sub setup {
    me.guestimg = $ARGV[0];
    $_ = me.guestimg;
    s;.*\/;;;
    s;\..*;;;
    me.guestname = $_;
    me.rootdir = qw /;
    me.bdfpattern = qw ..\:..\..;
    me.user = getlogin();
    @me.User = getpwnam(me.user);
    @me.Permit = qw SUDO unless me.User[2] == 0;
    @me.Kvm = getpwnam('kvm');
    me.cleanup = 1;
    me.gbdir = qw GUESTBRIDGEDIR;
    me.vfiodir = qw VFIODIR;
    me.socksdir = qw SOCKSDIR;
    me.virtiofsdsocksdir = qw VIRTIOFSDSOCKSDIR;
    me.pcidir = qw PCIDIR;
    me.chown = qw CHOWN;
    me.chmod = qw CHMOD;
    me.ip = qw IP;
    me.lspci = qw LSPCI;
    me.modprobe = qw MODPROBE;
    me.qemu = qw QEMU;
    me.bridge = qw BRIDGE;
    me.virtiofsd = qw VIRTIOFSD;
    me.guestcfg = "me.gbdir/conf/me.guestname";
}
sub clean {
    return unless me.cleaup;
    me.cleanup = 0;
}
sub delocate {
    clean();
    die @_;
}
sub run {
    system( split( /\s+/, $_[0])) == 0 or delocate "$_[0]: $!";
}
setup();
