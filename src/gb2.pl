#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw(setsid setgid setuid);
use Data::Dumper;
die "[guestimage file]: $!" unless defined $ARGV[0] && -r $ARGV[0]; 
my %me = ();
sub clean {
    return unless me.cleaup;
    me.cleanup = 0;
}
sub delocate {
    clean();
    die @_;
}
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
    me.mv = qw MV;
    me.guestcfg = "me.gbdir/conf/me.guestname";
    delocate "Pls add: me.User[0] to grp: me.Kvm[0]" unless me.User[2] != me.Kvm[2];
    delocate "me.guestcfg not avaliable." unless -r me.guestcfg;
    delocate "me.socksdir/me.guestname still in place" if -S "me.socksdir/me.guestname";
    if (not -w me.vfiodir or not -x me.vfiodir ){
        run("@me.Permit me.chown :me.Kvm[3] me.vfiodir");
        run("@me.Permit me.chmod 0775 me.vfiodir");
    }
    if(! -d me.virtiofsdsocksdir || ! -w me.virtiofsdsocksdir || ! -x -w me.virtiofsdsocksdir){
        me.tmp = int(rand(99999)) + 100000;
        me.tmp = "var/tmp/me.tmp";
        mkdir(me.tmp, 0770);
        chmod (me.tmp, 0770);
        chown (me.User[2], me.Kvm[2], me.tmp);
    }
}
sub config {
    open(INPUT, '<', me.guestcfg) or delocate "can't open me.guestcfg";
    chomp(@me.Config = <INPUT>);
    foreach(@me.Config){
        %me.Tmp = ();
        foreach(split(/,/)){
            if(m;([^"' ]+)\s*=\s*["']{0,1}([^"' ]+)["']{0,1};){
                me.Tmp{$1} = $2;
                next;
            }
            if(m;([^"' ]+)\s*["']{0,1}([^"' ]+)["']{0,1};){
                me.Tmp{$1} = $2;
                next;
            }
        }
        if ( defined me.Tmp{mac} && defined me.Tmp{netdev} ){
            me.Tap{me.Tmp{netdev}} = me.Tmp{mac}; 
            me.tmp = me.Tmp{mac} =~ tr/://rd;
            me.Bridge{me.tmp} = me.Tmp{mac};
            next;
        }
        if ( defined me.Tmp{path} ){
            me.Tmp{path} =~ m;me.guestname-(.+)\.sock;;
            me.Path{$1} = $1 =~ tr;@;\/;r;
            next;
        }
        if (defined me.Tmp{-device} && defined me.Tmp{host}){
            me.Wish{me.Tmp{host}} = me.Tmp{-device} if me.Tmp{host} =~ me.bdfpattern;
            next;
        }
    }
}
sub run {
    system( split( /\s+/, $_[0])) == 0 or delocate "$_[0]: $!";
}
setup();
config();
print Dumper(\%me);
