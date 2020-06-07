#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw(setsid setgid setuid);
use Data::Dumper;

die "[guestimage file]:$!" unless defined $ARGV[0] && -r $ARGV[0];
my ( $guestimg,$tmp,$pid,$rootdir) = ($ARGV[0],undef,undef,'/');
my ($gbdir,$vfiodir,$socksdir,$virtiofsdsocksdir)
= qw(GUESTBRIDGEDIR VFIODIR SOCKSDIR VIRTIOFSDSOCKSDIR);
my (@Config,%Bridge,%Tap,%Nic,%Tmp,%Master,%Path,%Wish,%Module,%Real,%Clean)
= ((),(),(),(),(),(),(),(),());
my ($pcidir,$chown,$chmod,$ip,$lspci, $modprobe,$qemu,$bridge,$virtiofsd)
= qw(PCIDIR CHOWN CHMOD IP LSPCI MODPROBE QEMU BRIDGE VIRTIOFSD);
my $bdfpattern = '..\:..\..';
my @Kvm = getpwnam('kvm');
my $user = getlogin();
my @User = getpwnam($user);
my @permit = ();
my $cleanup = 1;
@permit = qw(SUDO) unless $User[2] == 0;
sub clean {
    return unless $cleanup;
    $cleanup = 0;
    say "clean start";
    # Restore bridge and taps.
    foreach(call("$bridge link")){
        %Tmp = ();
        @_ = split(/\s+/);
        foreach(my $i = 3; $i < scalar(@_); $i++){
            next unless ( $_[$i] =~ m;master;);
            $Tmp{$_[$i]} = $_[$i + 1];
        }
        $_[1] =~ tr/://d;
        $Clean{$_[1]} = $Tmp{master} if defined $Tmp{master};
    }
    while(my ($key,$value) = each %Clean){
        # Don't bother with devices were there before this process.
        next if defined $Master{$key};
        if(defined $Tap{$key}){
            run("@permit $ip tuntap delete dev $key mode tap");
            next;
        }
        if (defined $Bridge{$value}){
            next unless defined $Nic{$Bridge{$value}};
            $tmp = $Nic{$Bridge{$value}};
            run("@permit $ip link set $tmp nomaster");
            run("@permit $ip link set $tmp down");
            run("@permit $ip link delete $value type bridge");
            next;
        }
    }
    # Restore Device drivers
    while( my ($key, $value) = each %Wish){
        if ( not defined $Real{$key}){
            next unless defined $Module{$key};
            run("@permit $modprobe $Module{$key}");
            gb_bind($key, $Module{$key});
            next;
        }
        next if $Real{$key} eq $value;
        run("@permit $modprobe $Module{$key}");
        gb_rebind($key, $value, $Module{$key});
    }
    say "clean end";
}
sub delocate {
    clean();
    die @_;
}

sub call {
    pipe(my ($rfh,$wfh)) or delocate "Cann't create pipe $!";
    my $pid = open(my $pipe,'-|') // delocate "Can't fork:$!";
    if(not $pid){
        # Child process.
        close($rfh);
        system(split(/\s+/,$_[0])) == 0 or delocate "$_[0]: $!";
        exit;
    }
    # Parent process.
    close($wfh);
    close($rfh);
    @_ = <$pipe>;
    close($pipe);
    return @_;
}
sub run {
    CORE::system(split(/\s+/, $_[0])) == 0 or delocate "$_[0]: $!";
}
sub daemon {
    return if $pid = fork;
    # child pid is 0
    delocate "cann't fork:$!" unless defined $pid;
    delocate "cann't chdir to $rootdir: $!" unless chdir $rootdir;
    umask 0077;
    delocate "can't setsid" if setsid() < 0;
    close STDIN;
#   close STDOUT;
#   close STDERR;
    setgid $Kvm[3];
    setuid $Kvm[2];
    open(STDIN,"</dev/null");
#   open(STDOUT,"+>/dev/null");
#   open(STDERR,"+>/dev/null");
    exec(split(/\s+/, $_[0])) or delocate "$_[0]: $!";
    # just in case child don't delocate.
    exit;
}
sub gb_bind {
    delocate "[bdf][bind driver: vfio-pci]" if scalar(@_) < 2;
    delocate "invalid bdf:" unless $_[0] =~ $bdfpattern;
    my $bdf = "0000:$_[0]";
    my $bind = $_[1];
    $bind =~ tr/_/-/ unless -d "${pcidir}/${bind}";
    my $idpath = "$pcidir/$bind/new_id";
    my $bindpath = "$pcidir/$bind/bind";
    @_ = call("$lspci -s $bdf -n");
    my @id = split(/\s+/,$_[0]);
    $id[2] =~ tr/:/ /;
    run("@permit $chown $user: $idpath $bindpath");
    open(my $fh, '>', $idpath) or delocate "can't open $idpath";
    print $fh $id[2];
    close $fh;
    open($fh, '>', $bindpath) or delocate "can't open $bindpath";
    print $fh $bdf;
    close $fh;
    run("@permit $chown root: $idpath $bindpath");
}
sub gb_unbind {
    delocate "Requre 2 args:" if scalar(@_) < 2;
    delocate "invalid bdf:" unless $_[0] =~ $bdfpattern;
    my $bdf = "0000:$_[0]";
    my $unbind = $_[1];
    $unbind =~ tr/_/-/ unless -d "${pcidir}/${unbind}";
    my $unbindpath = "$pcidir/$unbind/unbind";
    run("@permit $chown $user: $unbindpath");
    open(my $fh, '>', $unbindpath) or delocate "can't open $unbindpath";
    print $fh $bdf;
    close $fh;
    run("@permit $chown root: $unbindpath");
}
sub gb_rebind {
    delocate "[bdf][unbind driver: ehci-pci/vfio-pci][bind driver:]" if scalar(@_) < 3;
    delocate "invalid bdf:$_[0]" unless $_[0] =~ $bdfpattern;
    my $bdf = "0000:$_[0]";
    my $unbind = $_[1];
    my $bind = $_[2];
    $bind =~ tr/_/-/ unless -d "${pcidir}/${bind}";
    $unbind =~ tr/_/-/ unless -d "${pcidir}/${unbind}";
    my $unbindpath = "$pcidir/$unbind/unbind";
    my $idpath = "$pcidir/$bind/new_id";
    my $bindpath = "$pcidir/$bind/bind";
    @_ = call("$lspci -s $bdf -n");
    my @id = split(/\s+/,$_[0]);
    $id[2] =~ tr/:/ /;
    run("@permit $chown $user: $idpath $bindpath $unbindpath");
    open(my $fh, '>', $unbindpath) or delocate "can't open $unbindpath";
    print $fh $bdf;
    close $fh;
    open( $fh, '>', $idpath) or delocate "can't open $idpath";
    print $fh $id[2];
    close $fh;
    open($fh, '>', $bindpath) or delocate "can't open $bindpath";
    print $fh $bdf;
    close $fh;
    run("@permit $chown root: $idpath $bindpath $unbindpath");
}
sub gb_perm {
    return unless scalar %Path > 0;
    # Check sockets creation.
    @_ = glob("$virtiofsdsocksdir*");
    delocate "empty $virtiofsdsocksdir:" unless scalar(@_) > 0;

    run("@permit $chown :$Kvm[0] @_");
    run("@permit $chmod g=rw @_");
}
$_ = $guestimg;
s;.*\/;;;
s;\..*;;;
my $guestname = $_;
my $guestcfg = "$gbdir/conf/$_";

delocate "Pls add: $User[0] to group: $Kvm[0]" unless $User[2] != $Kvm[2];

delocate "Guest config: $guestcfg not avaliable." unless -r $guestcfg; 
delocate "$vfiodir/vfio not avaliable." unless -c "$vfiodir/vfio";
delocate "$socksdir/$guestname still in place." if -S "$socksdir/$guestname";
if( ! -w $vfiodir || ! -x $vfiodir ){
    run("@permit $chown :$Kvm[3] $vfiodir");
    run("@permit $chmod 0775 $vfiodir");
}
if( ! -d $virtiofsdsocksdir || ! -w $virtiofsdsocksdir || ! -x $virtiofsdsocksdir ){
    $tmp = int(rand(99999)) + 10000;
    $tmp = "/var/tmp/$tmp";
    mkdir( $tmp,0770);
    chmod( 0770, $tmp);
    chown($User[2],$Kvm[3],$tmp);
    run("@permit MV $tmp $virtiofsdsocksdir");
}
###########################
#     Parse config file
###########################

open(INPUT, '<', $guestcfg) or delocate "can't open $guestcfg.";
chomp(@Config = <INPUT>);
close(INPUT);
foreach(@Config){
    %Tmp = ();
    foreach(split(/,/)){
        # Every field
        if(m;([^"' ]+)\s*=\s*["']{0,1}([^"' ]+)["']{0,1};){
            $Tmp{$1} = $2;
            next;
        }
        if(m;([^"' ]+)\s*["']{0,1}([^"' ]+)["']{0,1};){
            $Tmp{$1} = $2;
            next;
        }
    }
    # Every Line
    if (defined($Tmp{mac}) && defined($Tmp{netdev})){
        $Tap{$Tmp{netdev}} = $Tmp{mac};
        $tmp = $Tmp{mac} =~ tr/://rd;
        $Bridge{$tmp} = $Tmp{mac}; 
        next;
    }
    if(defined($Tmp{path})){
        $Tmp{path} =~ m;$guestname-(.+)\.sock;;
        $Path{$1} = $1 =~ tr;@;\/;r;
        next;
    }
    if(defined($Tmp{-device}) && defined($Tmp{host})){
        $Wish{$Tmp{host}} = $Tmp{-device} if $Tmp{host} =~ $bdfpattern;
        next;
    }
}
##################################
#   Device setup
##################################
foreach(split(/(?:\n){2}/, join("",call("$lspci -vmk")))){
    %Tmp = ();
    foreach(split(/\n/)){
        next unless ( m;([^: ]+):\s*([^ ]+)\s*; );
        $Tmp{$1} = $2 unless defined $Tmp{$1}; 
    }
    next unless defined $Tmp{Device};
    $Real{$Tmp{Device}} = $Tmp{Driver} if defined $Tmp{Driver};
    $Module{$Tmp{Device}} = $Tmp{Module} if defined $Tmp{Module};
}
while(my ($key, $value) = each %Wish){
    if( not defined $Real{$key}){
        $value =~ tr/-/_/;
        run("@permit $modprobe ${value}");
        gb_bind( $key, ${value});
        next;
    }

    next if $value eq $Real{$key};

    if ($Real{$key} =~ "amdgpu|nouveau"){
        gb_rebind($key, $Real{$key}, $value);
        run("@permit $modprobe --remove $Real{$key}");
        next;
    }

    gb_rebind($key, $Real{$key}, $value);
}
#print Dumper(\%Wish);
#print Dumper(\%Real);
#print Dumper(\%Module);
#################################
#        Virfiofsd by setuid
#################################
run("@permit $chmod 4755 $virtiofsd");
while(my ($key,$value) = each %Path){
    next if( -S "$virtiofsdsocksdir$guestname-${key}.sock" );
    daemon("$virtiofsd --syslog --socket-path=$virtiofsdsocksdir$guestname-${key}.sock
         --thread-pool-size=6 -o source=${value}");
}
# due to Daemon is nonblocking this will always run.
run("@permit $chmod 0755 $virtiofsd");
##############################
#     Add taps and Bridges.
##############################
# All nic names
foreach(call("$ip -o link show")){
    %Tmp = ();
    @_ = split(/\s+/);
    foreach(my $i = 3; $i < scalar(@_); $i++){
        next unless ( $_[$i] =~ m;permaddr|link/ether|master;);
        $Tmp{$_[$i]} = $_[$i + 1];
    }
    $_[1] =~ tr/://d;
    $Nic{$Tmp{permaddr}} = $_[1] if defined $Tmp{permaddr};
    $Nic{$Tmp{'link/ether'}} = $_[1] if defined $Tmp{'link/ether'};
    $Master{$_[1]} = $Tmp{master} if defined $Tmp{master};
}

# One physical nic only belongs to one bridge.
foreach(values %Nic){
    defined($Bridge{$_}) || next;
    # Already has this bridge
    $Bridge{$_} = undef;
}
# Create bridges that are not already in place.
while(my ($key,$value) = each %Bridge){
    defined $value || next;
    # Bridge Name
    $tmp = $Nic{$value};
    run("@permit $ip address flush dev $tmp");
    run("@permit $ip link add name $key type bridge");
    run("@permit $ip link set $key up");
    run("@permit $ip link set $tmp down");
    run("@permit $ip link set $tmp up");
    run("@permit $ip link set $tmp master $key");
}
# Filter out exist taps and bridge it.
foreach(values %Nic){
    defined($Tap{$_}) || next;
    # Already has this tap and it's also bridged.
    if(defined($Master{$_})){
        $Tap{$_} = undef;
        next;
    }
    $Tap{$_} =~ tr/://d;
    run("@permit $ip link set dev $_ up");
    run("@permit $ip link set $_ master $Tap{$_}");
    $Tap{$_} = undef;
}
# Add new taps and bridge it.
while(my ($key,$value) = each %Tap){
    defined $value || next;
    run("@permit $ip tuntap add dev $key mode tap user $User[0]");
    run("@permit $ip link set dev $key up");
    $value =~ tr/://d;
    run("@permit $ip link set $key master $value");
    $value = undef;
}
#print Dumper(\%Tap);
#print Dumper(\%Nic);
#print Dumper(\%Bridge);
#print Dumper(\@Config);
#print Dumper(\%Clean);
#######################################
# Wait until virtiofsd created sockets.
# It's time to change permission.
#######################################

gb_perm();
##################################
#   Start vm by setuid
##################################

run("@permit $chmod 4755 $qemu");
daemon("$qemu -chroot /var/tmp/ -runas kvm @Config");
run("@permit $chmod 0755 $qemu");

#sleep 1;
#( -S "$socksdir/$guestname" ) || delocate "$socksdir/$guestname not yet created.";
#run("@permit $chown $Kvm[0]:$Kvm[0] $socksdir/$guestname");
#run("@permit $chmod ug=rw $socksdir/$guestname");

#print Dumper(\%Bridge);
#print Dumper(\%Nic);
#print Dumper(\%Master);
#print Dumper(\%Path);
#__END__
