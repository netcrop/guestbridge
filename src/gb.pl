#!ENV PERL
use VERSION;
use strict;
use warnings qw FATAL;
use POSIX qw setsid setgid setuid;
use Data::Dumper;
use Socket;
use Fcntl qw :flock;
my %me = ();
my $lockfh = undef;
#############################
# restore nic
#############################
sub renic {
    # restore bridge and bridged taps
    foreach ( call me.bridge link ) {
        me.any = ();
        @_ = split /\s+/;
        foreach ( me.i = 3; me.i < scalar @_; me.i ++ ){
            next unless us[me.i] =~ m;master;;
            me.any{us[me.i]} = us[me.i + 1];
        }
        us[1] =~ tr/://d;
        next unless defined me.any{master};
        me.nic{us[1]} = me.any{master}; 
        me.cin{me.any{master}} .= " us[1]";
    }
    me.any = ();
    while ( (me.key, me.value) = each %me.cin ){
        @me.any = split(" ", me.value );
        me.tmp = undef;
        me.i = 0;
        foreach (@me.any) {
            if ( defined me.tap{us} ){
                run @me.permit me.ip tuntap delete dev us mod tap;
                me.i++;
                next;
            }
            next unless defined me.nic{us};
            me.tmp = us unless defined me.tmp;
        }
        next unless me.i == (scalar( @me.any) - 1);
        next unless defined me.tmp;
        run @me.permit me.ip link set me.tmp nomaster;
        run @me.permit me.ip link set me.tmp down;
        run @me.permit me.ip link delete me.key type bridge;
    }
}
sub clean {
    say "clean start";
    return if me.cleanup == 0;
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
            open my $fh, '<', us or die "can't open";
            me.tmp = <$fh>;
            run @me.permit me.kill -s SIGKILL me.tmp;
            run @me.permit me.rm -f us;
            close $fh;
            next;
        }
        run @me.permit me.rm -f us if m;sock$;;
    }
    return unless -d me.virtiofsdsocksdir;
    me.any = glob "me.virtiofsdsocksdir/* me.virtiofsdsocksdir/\.??*"; 
    run @me.permit me.rmdir me.virtiofsdsocksdir unless defined scalar me.any; 
    say "clean end";
}
sub dumpfilter {
    my ($hash) = @_;
    return [ ( sort {$b cmp $a} keys %$hash) ];
}
sub debug {
    return unless me.debugging == 1;
    say @_;
    open my $fh, '>', '/tmp/gb.log' or die "can't open /tmp/gb.log";
    $Data::Dumper::Sortkeys = \&dumpfilter;
    print $fh Dumper( \%me);
    close $fh;
}
sub delocate {
    clean();
    foreach ((0,1,2)){
        me.tmp = (caller(us))[3];
        next unless defined me.tmp;
        me.tmp .= " [" . (caller(us))[2] . "]";
    }
    if ( defined $lockfh ){
        flock $lockfh, LOCK_UN or die "can't unlock";
        close $lockfh;
        $lockfh = undef;
    }
    debug();
    die @_;
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
    close STDOUT;
#    close STDERR;
    setgid me.kvm[3];
    setuid me.kvm[2];
    open STDIN, '</dev/null';
    open STDOUT, '+>/dev/null';
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
# validate config
############################
sub setup {
    delocate ("Pls add: me.user[0] to grp: me.kvm[0]")
    unless me.username eq me.kvmgroup[3];
    delocate "me.socksdir/me.guestname still in place" if -S "me.socksdir/me.guestname";
    if (not -w me.vfiodir or not -x me.vfiodir ){
        run @me.permit me.chown :me.kvm[3] me.vfiodir;
        run @me.permit me.chmod 0775 me.vfiodir;
    }
    if(! -d me.virtiofsdsocksdir || ! -w me.virtiofsdsocksdir || ! -x -w me.virtiofsdsocksdir){
        me.tmp = int(rand(99999)) + 10000;
        me.tmp = "me.tmpdir/me.tmp";
        mkdir me.tmp, 0770 or delocate "mkdir me.tmp";
        chmod 0770, me.tmp;
        chown( me.user[2], me.kvm[3], me.tmp) or delocate "chown me.user[2] me.kvm[3] me.tmp";
        run @me.permit me.mv me.tmp me.virtiofsdsocksdir;
    }
    foreach ( values %me.path ){
        delocate "us missing." unless -d us;        
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
        if (defined me.any{-monitor}){
            me.any{-monitor} =~ m;unix:(.+)/[^/]+;;
            me.socksdir = $1;
        }
        if ( defined me.any{file} && defined me.any{format}){
            me.guestimg = me.any{file};
        }
        if ( defined me.any{-name}){
            me.guestname = me.any{-name};
        }
        if ( defined me.any{mac} && defined me.any{netdev} ){
            me.tap{me.any{netdev}} = me.any{mac}; 
            me.tmp = me.any{mac} =~ tr/://rd;
            me.config_bridge{me.tmp} = me.any{mac};
            next;
        }
        if ( defined me.any{path} ){
            me.any{path} =~ m;(.+)/[^/]+-(.+)\.sock;;
            me.virtiofsdsocksdir = $1 if defined $1;
            me.path{$2} = $2 =~ tr;@;\/;r if defined $2;
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
    me.bind = 'xhci_hcd' if me.bind eq 'xhci_pci';
    me.bind = 'xhci-hcd' if me.bind eq 'xhci-pci';
    me.bind =~ tr/_/-/ unless -d "me.pcidir/me.bind";
    me.idpath = "me.pcidir/me.bind/new_id";
    me.bindpath = "me.pcidir/me.bind/bind";
    @_ = call me.lspci -s me.bdf -n;
    delocate "me.bdf not found." if scalar(@_) == 0;
    @me.id = split( /\s+/, us[0] );
    me.id[2] =~ tr/:/ /;
    run @me.permit me.chown me.username: me.idpath me.bindpath;
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
    me.bind = 'xhci_hcd' if me.bind eq 'xhci_pci';
    me.bind = 'xhci-hcd' if me.bind eq 'xhci-pci';
    me.bind =~ tr/_/-/ unless -d "me.pcidir/me.bind";
    me.unbind =~ tr/_/-/ unless -d "me.pcidir/me.unbind";
    me.unbindpath = "me.pcidir/me.unbind/unbind";
    me.bindpath = "me.pcidir/me.bind/bind";
    me.idpath = "me.pcidir/me.bind/new_id";
    @_ = call me.lspci -s me.bdf -n;
    @me.id = split(/\s+/, us[0]);
    me.id[2] =~ tr/:/ /;
    run @me.permit me.chown me.username: me.idpath me.bindpath me.unbindpath;
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
#############################
#   rebind devices to module
#############################
sub redevice {
#    say "redevice start";
    foreach( split(/\n{2}/, join ("",call me.lspci -vmk ) ) ){
        %me.any = ();
        foreach(split(/\n/)){
            next unless m;([^: ]+):\s*([^ ]+)\s*;;
            me.any{$1} = $2 unless defined me.any{$1};
        }
        next unless defined me.any{Device};
        me.real{me.any{Device}} = me.any{Driver} if defined me.any{Driver};
        if ( defined me.any{Module} ){
            if (me.any{Module} eq 'xhci_pci'){
                me.module{me.any{Device}} = 'xhci_hcd';
            }else{
                me.module{me.any{Device}} = me.any{Module};
            }
        }
    }
    while ( (me.key,me.value) = each %me.wish ){
        if ( not defined me.real{ me.key } ) {
            me.value =~ tr/-/_/;
            next if not defined me.module{me.key};
            run @me.permit me.modprobe me.module{me.key};
            gb_bind me.key, me.module{me.key};
            next;
        }
        next if not defined me.module{me.key};
        next if me.module{me.key} eq me.real{me.key};
        run @me.permit me.modprobe me.module{me.key};
        gb_rebind me.key, me.real{me.key}, me.module{me.key};
    }
}
#################################
# rebind devices to vfio drivers
#################################
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
    return unless scalar %me.path > 0;
    run @me.permit me.chmod 4755 me.virtiofsd;
    while ( (me.key, me.value ) = each %me.path ){
        next if -S "me.virtiofsdsocksdir/me.guestname-me.key.sock";
        daemon me.virtiofsd --syslog --socket-path=me.virtiofsdsocksdir/me.guestname-me.key.sock --thread-pool-size=8 -o source=me.value; 
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
sub start {
    run @me.permit me.chmod 4755 me.qemu;
    daemon me.qemu -chroot /var/tmp/ -runas kvm @me.config;
    run @me.permit me.chmod 0755 me.qemu;
}
sub status {
   delocate "me.socksdir/me.guestname not created" unless -S "me.socksdir/me.guestname";
    run @me.permit me.chown me.kvm[0]:me.kvm[0] me.socksdir/me.guestname;
    run @me.permit me.chmod ug=rw me.socksdir/me.guestname; 
}
#############################
# Start VM
#############################
sub startvm {
    me.cleanup = 1;
    me.guestcfg = $ARGV[0];
    die "me.guestcfg not text file." unless -T me.guestcfg;
    config();
    setup();
    device();
    virtiofsd();
    nic();
    sleep 1;
    perm();
    start();
    sleep 2;
    status();
}
#############################
# Cron
#############################
sub cron {   
    me.cleanup = 0;
    foreach ( glob "me.socksdir/*"){
        next unless -S us;
        me.guestname = s;.*/;;rg;
        me.guestcfg = "me.gbdir/conf/me.guestname";
        socket(SOCK,PF_UNIX,SOCK_STREAM,0) or die "socket us"; 
        next if connect(SOCK,sockaddr_un("us"));
        next if defined( me.answer = <SOCK>);
        close SOCK;
        config();
        redevice();
        foreach (glob "me.virtiofsdsocksdir/* me.virtiofsdsocksdir/\.??*"){
            next unless m;me.guestname;;
            run @me.permit me.rm -f us;
        } 
        renic();
        run @me.permit rm -f us;
    }
    # we trust previous procedure rebind VGA correct
    # only do the following when booting host OS
    return if defined me.guestname;
    bootgpu();
}

sub bootgpu {
    me.cleanup = 0;
    @_ = glob "/dev/fb*";
    return unless scalar @_ == 0;
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
    while ( (me.key, me.value) = each %me.module){
        next if( me.value ne me.primarygpu);
        if ( not defined me.real{me.key}) {
            run @me.permit me.modprobe me.primarygpu;
            gb_bind me.key, me.primarygpu;
            return;
        }
        return if( me.real{me.key} eq me.primarygpu);
        run @me.permit me.modprobe me.primarygpu;
        gb_rebind me.key, me.real{me.key}, me.primarygpu;
        return;
    }
}
sub funlock {
    run @me.permit touch me.lockfile unless -e me.lockfile;
    run @me.permit chmod a=r me.lockfile unless -r me.lockfile;
    me.cleanup = 0;
    next if defined $lockfh; 
    open $lockfh, '<', me.lockfile or die "can't open";    
    flock $lockfh, (LOCK_NB | LOCK_EX) or die "can't lock";
    us[0]();
    flock $lockfh, LOCK_UN or die "can't unlock";
    close $lockfh;
    $lockfh = undef;
}
#############################
# Main
#############################
sub usage {
    me.progname = $0;
    me.progname =~ s;.*/;;;
    print <<USAGE;
Usage: me.progname [guestconfig file] [-c | -d | -cron ] [-b | -bootgpu]
    E.g:
    me.progname [guestconfig]
    me.progname -cron
    me.progname -bootgpu
USAGE
    exit 1;
}
sub main {
    me.cleanup = 0;
    me.debugging = 1;
    me.bdfpattern = qw ..\:..\..;
    me.lockfile = qw /run/lock/gb;
    me.primarygpu = qw nouveau;
    me.gbdir = qw GUESTBRIDGEDIR;
    me.vfiodir = qw VFIODIR;
    me.pcidir = qw PCIDIR;
    me.socksdir = qw SOCKSDIR;
#    me.virtiofsd = qw /bin/virtiofsd;
    me.tmpdir = '/var/tmp/';
    me.rootdir = qw /;
    me.username = getpwuid($<);
    @me.user = getpwnam(me.username);
    @me.permit = qw me.sudo;
    @me.kvm = getpwnam('kvm') or die "Pls create a systemd user 'kvm'.";
    @me.kvmgroup = getgrnam('kvm');
    me.virtiofsdsocksdir = qw /run/virtiofsd;
    usage() unless defined $ARGV[0];
    if ( -r $ARGV[0]){ funlock \&startvm;exit;}
    if ($ARGV[0] =~ m;-c|-d|-cron;){ funlock \&cron;exit;}
    if ( $ARGV[0] =~ m;-b|-bootgpu;){ funlock \&bootgpu; exit;} 
    usage();
}
#################
# Execution
#################
main();
