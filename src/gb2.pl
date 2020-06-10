#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw setsid setgid setuid;
use Data::Dumper;
die "[guestimage file]: $!" unless defined $ARGV[0] && -r $ARGV[0]; 
my %me = ();
sub clean {
    say "clean start me.cleanup";
    return if me.cleaup;
    say "cleaning";
    me.cleanup = 0;
    # restore bridge and bridged taps
    foreach ( call me.bridge link ) {
        me.any = ();
        @_ = split /\s+/;
        foreach ( me.i = 3; me.i < scalar @_; me.i ++ ){
            next unless us[me.i] =~ m;master;;
            me.any{us[me.i]} = us[me.i + 1];
        }
        us[1] =~ tr/://d;
        me.clean{us[1]} = me.any{master} if defined me.any{master}; 
    }
    # restore disconnected taps.
    foreach ( call me.ip tuntap ){
        @_ = split /:/;
        defined us[0] || next;
        next if defined me.clean{us[0]};
        me.clean{us[0]} = 0; 
    }
    while ( (me.key, me.value) = each %me.clean){
        # don't bother with devices were there before this process.
        next if defined me.master{me.key};
        if ( defined me.tap{me.key} ){
            run @me.permit me.ip tuntap delete dev me.key mod tap;
            next;
        }
        if ( defined me.config_bridge{me.value} ){
            next unless defined me.nic{me.config_bridge{me.value}};
            me.tmp = me.nic{me.config_bridge{me.value}};
            run @me.permit me.ip link set me.tmp nomaster;
            run @me.permit me.ip link set me.tmp down;
            run @me.permit me.ip link delete me.value type bridge;
            next;
        }
    }
    # restore device drivers
    while ( (me.key, me.value ) = each %me.wish ){
        unless (defined me.real{me.key}){
            next unless defined me.module{me.key};
            run @me.permit me.modprobe me.module{me.key};
            gb_bind(me.key, me.module{me.key});
            next;
        }
        next if me.real{me.key} eq me.value;
        run @me.permit me.modprobe me.module{me.key};
        gb_rebind( me.key, me.value, me.module{me.key});
    }    
    # remove virtiofsd socks
    foreach ( glob "me.socksdir/*"){
        me.tmp = s;.*/;;rg;
        me.socksname{me.tmp} = us;
    }
    foreach ( glob "me.virtiofsdsocksdir/* me.virtiofsdsocksdir/\.??*" ){
        me.tmp = s;.*\/;;rg;
        me.tmp =~ s;-@.*;;g;
        me.tmp =~ s;.*\.;;g;
        next if me.socksname{me.tmp};
        if( m;pid$;){
            say us;
            open my $fh, '<', us or die "can't open";
            me.tmp = <$fh>;
            run @me.permit me.kill -s SIGKILL me.tmp;
            run @me.permit me.rm -f us;
            close $fh;
            next;
        }
        run @me.permit me.rm -f us if m;sock$;;
    }
    say "clean end";
}
sub dumpfilter {
    my ($hash) = @_;
    return [ ( sort {$b cmp $a} keys %$hash) ];
}
sub debug {
    open my $fh, '>', '/tmp/gb.log' or die "can't open /tmp/gb.log";
    $Data::Dumper::Sortkeys = \&dumpfilter;
    print $fh Dumper( \%me);
    close $fh;
}
sub delocate {
    clean();
    debug();
    die ((caller(2))[3], " [", (caller(1))[2], "] ", @_);
}
sub run {
    system( split(/\s+/, us[0])) == 0 or delocate(us[0]);
}
sub call {
    pipe( me.rfh,me.wfh ) or delocate ("can't pipe");
    # also check pid is defined or not
    # pipe must be local variable.
    me.pid = open( my $pipe,'-|' ) // delocate ("cant fork");
    if ( not me.pid ){
        # child process
        close me.rfh;
        system( split(/\s+/, us[0]) ) == 0 or delocate ("us[0]:");
        exit;
    }
    # parent process
    close me.wfh;
    close me.rfh;
    @_ = <$pipe>;
    close $pipe;
    return @_;
}
sub daemon {
    return if me.pid = fork;
    # child pid is 0
    delocate ("can't fork:") unless defined me.pid;
    delocate ("can't chdir to me.rootdir:") unless chdir me.rootdir;
    umask 0077;
    delocate ("can't setsid") if setsid() < 0;
    close STDIN;
#    close STDOUT;
#    close STDERR;
    setgid me.kvm[3];
    setuid me.kvm[2];
    open STDIN, '</dev/null';
#    open STDOUT, '+>/dev/null';
#    open STDERR, '+>/dev/null';
    exec( split(/\s+/, us[0]) ) or delocate ("us[0]:");
    # in case child don't delocate.
    exit;
}
sub perm {
    return unless scalar %me.path > 0;
    # check sockets creation
    @_ = glob "me.virtiofsdsocksdir/* me.virtiofsdsocksdir/\.??*";
    delocate ("empty me.virtiofsdsocksdir:") unless scalar @_ > 0;
    run @me.permit me.chown :me.kvm[0] @_;
    run @me.permit me.chmod g=rw @_;
}
############################
# variabler/array/hash must
# use different names.
############################
sub setup {
    me.guestimg = $ARGV[0];
    us = me.guestimg;
    s;.*\/;;;
    s;\..*;;;
    me.guestname = us;
    me.rootdir = qw /;
    me.bdfpattern = qw ..\:..\..;
    me.login = getlogin();
    @me.user = getpwnam(me.login);
    @me.permit = qw SUDO unless me.user[2] == 0;
    @me.kvm = getpwnam('kvm');
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
    me.rm = qw RM;
    me.kill = qw KILL;
    me.guestcfg = "me.gbdir/conf/me.guestname";
    delocate ("Pls add: me.user[0] to grp: me.kvm[0]") unless me.user[2] != me.kvm[2];
    delocate ("me.guestcfg not avaliable.") unless -r me.guestcfg;
    delocate "me.socksdir/me.guestname still in place" if -S "me.socksdir/me.guestname";
    if (not -w me.vfiodir or not -x me.vfiodir ){
        run @me.permit me.chown :me.kvm[3] me.vfiodir;
        run @me.permit me.chmod 0775 me.vfiodir;
    }
    if(! -d me.virtiofsdsocksdir || ! -w me.virtiofsdsocksdir || ! -x -w me.virtiofsdsocksdir){
        me.tmp = int(rand(99999)) + 100000;
        me.tmp = "var/tmp/me.tmp";
        mkdir(me.tmp, 0770);
        chmod 0770, me.tmp;
        chown (me.user[2], me.kvm[2], me.tmp);
        run @me.permit me.mv me.tmp me.virtiofsdsocksdir;
    }
}
sub config {
    open(INPUT, '<', me.guestcfg) or delocate ("can't open me.guestcfg");
    chomp(@me.config = <INPUT>);
    foreach(@me.config){
        %me.any = ();
        foreach(split(/,/)){
            if(m;([^"' ]+)\s*=\s*["']{0,1}([^"' ]+)["']{0,1};){
                me.any{$1} = $2;
                next;
            }
            if(m;([^"' ]+)\s*["']{0,1}([^"' ]+)["']{0,1};){
                me.any{$1} = $2;
                next;
            }
        }
        if ( defined me.any{mac} && defined me.any{netdev} ){
            me.tap{me.any{netdev}} = me.any{mac}; 
            me.tmp = me.any{mac} =~ tr/://rd;
            me.config_bridge{me.tmp} = me.any{mac};
            next;
        }
        if ( defined me.any{path} ){
            me.any{path} =~ m;me.guestname-(.+)\.sock;;
            me.path{$1} = $1 =~ tr;@;\/;r;
            next;
        }
        if (defined me.any{-device} && defined me.any{host}){
            me.wish{me.any{host}} = me.any{-device} if me.any{host} =~ me.bdfpattern;
            next;
        }
    }
}
sub gb_bind {
    delocate ("[bdf][bind driver: vfio-pci]") if scalar(@_) < 2;
    delocate ("invalid bdf:") unless us[0] =~ me.bdfpattern;
    me.bdf = "0000:us[0]";
    me.bind = us[1];
    me.bind =~ tr/_/-/ unless -d "me.pcidir/me.bind";
    me.idpath = "me.pcidir/me.bind/new_id";
    me.bindpath = "me.pcidir/me.bind/bind";
    @_ = call me.lspci -s me.bdf -n;
    @me.id = split( /\s+/, us[0] );
    me.id[2] =~ tr/:/ /;
    run @me.permit me.chown me.login: me.idpath me.bindpath;
    open( my $fh, '>', me.idpath ) or delocate ("can't open me.idpath");
    print $fh me.id[2];
    close $fh;
    open( $fh, '>', me.bindpath ) or delocate ("can't open me.bindpath");
    print $fh me.bdf;
    close $fh;
    run @me.permit me.chown root: me.idpath me.bindpath;
}
sub gb_rebind {
    delocate ("[bdf][unbind driver: ehci-pci/vfio-pci][bind driver:]") if scalar(@_) < 3;
    delocate ("invalid bdf: us[0]") unless us[0] =~ me.bdfpattern;
    me.bdf = "0000:us[0]";
    me.unbind = us[1];
    me.bind = us[2];
    me.bind =~ tr/_/-/ unless -d "me.pcidir/me.bind";
    me.unbind =~ tr/_/-/ unless -d "me.pcidir/me.unbind";
    me.unbindpath = "me.pcidir/me.unbind/unbind";
    me.bindpath = "me.pcidir/me.bind/bind";
    me.idpath = "me.pcidir/me.bind/new_id";
    @_ = call me.lspci -s me.bdf -n;
    @me.id = split(/\s+/, us[0]);
    me.id[2] =~ tr/:/ /;
    run @me.permit me.chown me.login: me.idpath me.bindpath me.unbindpath;
    open my $fh, '>', me.unbindpath or delocate ("can't open me.unbindpath");
    print $fh me.bdf;
    close $fh;
    open $fh, '>', me.idpath or delocate ("can't open me.iddpath");
    print $fh me.id[2];
    close $fh;
    open $fh, '>', me.bindpath or delocate ("can't open me.binddpath");
    print $fh me.bdf;
    close $fh;
    run @me.permit me.chown root: me.idpath me.bindpath me.unbindpath;
}
sub device {
    foreach( split(/\n{2}/, join ("",call me.lspci -vmk ) ) ){
        %me.any = ();
        foreach(split(/\n/)){
            next unless m;([^: ]+):\s*([^ ]+)\s*;;
            me.any{$1} = $2 unless defined me.any{$1};
        }
        next unless defined me.any{Device};
        me.real{me.any{Device}} = me.any{Driver} if defined me.any{Driver};
        me.module{me.any{Device}} = me.any{Module} if defined me.any{Module};
    }
    while ( (me.key,me.value) = each %me.wish ){
        if ( not defined me.real{ me.key } ) {
            me.value =~ tr/-/_/;
            run @me.permit me.modprobe me.value;
            gb_bind me.key, me.value;
            next;
        }
        next if me.value eq me.real{me.key};
        if ( me.real{me.key} =~ "amdgpu|nouveau" ){
            gb_rebind me.key, me.real{me.key}, me.value;
            run @me.permit me.modprobe --remove me.real{me.key};
            next;
        }
        gb_rebind me.key, me.real{me.key}, me.value;
    }
}
sub virtiofsd {
    run @me.permit me.chmod 4755 me.virtiofsd;
    while ( (me.key, me.value ) = each %me.path ){
        next if -S "me.virtiofsdsocksdir/me.guestname-me.key.sock";
        daemon me.virtiofsd --syslog --socket-path=me.virtiofsdsocksdir/me.guestname-me.key.sock --thread-pool-size=6 -o source=me.value; 
    }
    run @me.permit me.chmod 0755 me.virtiofsd;
}
sub nic {
    foreach( call me.ip -o link show ){
        %me.any = ();
        @_ = split /\s+/;
        foreach ( me.i = 3; me.i < scalar @_; me.i++ ){
            next unless us[me.i] =~ m;permaddr|link/ether|master;;
            me.any{us[me.i]} = us[ me.i + 1];
        }
        us[1] =~ tr/://d;
        me.nic{me.any{permaddr}} = us[1] if defined me.any{permaddr};
        me.nic{me.any{'link/ether'}} = us[1] if defined me.any{'link/ether'};
        me.master{us[1]} = me.any{master} if defined me.any{master};
    }
    # one physical nic belongs to only one bridge
    foreach ( values %me.nic ){
        defined me.config_bridge{us} || next;
        # already has this bridge
        me.config_bridge{us} = undef;
    }
    # filter out non exists physical nic from config bridge   
    while ( (me.key, me.value) = each %me.config_bridge ){
        next unless defined me.value;
        me.config_bridge{me.key} = undef unless defined me.nic{me.value};
    }
    # filter out impossible taps from config tap
    while ( (me.key, me.value) = each %me.tap) {
        me.tap{me.key} = undef unless defined me.nic{me.value};
    }
    # create bridges that are not already in place.
    while ( (me.key, me.value) = each %me.config_bridge ) {
        defined me.value || next;
        # bridge name
        me.tmp = me.nic{me.value} // next;
        run @me.permit me.ip address flush dev me.tmp;
        run @me.permit me.ip link add name me.key type bridge;
        run @me.permit me.ip link set me.key up;
        run @me.permit me.ip link set me.tmp down;
        run @me.permit me.ip link set me.tmp up;
        run @me.permit me.ip link set me.tmp master me.key;
    }
    # filter out existing taps and bridge them.
    foreach ( values %me.nic ){
        defined me.tap{us} || next;
        # already has this tap and it's also bridged.
        if (defined me.master{us}) {
            me.tap{us} = undef;
            next;
        }
        me.tap{us} =~ tr/://d;
        run @me.permit me.ip link set dev us up;
        run @me.permit me.ip link set us master me.tap{us};
    }
    # add new taps and bridge them.
    while ( (me.key, me.value) = each %me.tap ){
        defined me.value || next;
        run @me.permit me.ip tuntap add dev me.key mode tap user me.user[0];
        run @me.permit me.ip link set dev me.key up;
        me.value =~ tr/://d;
        run @me.permit me.ip link set me.key master me.value;
        me.value = undef;
    }
}
setup();
config();
device();
virtiofsd();
nic();
perm();
