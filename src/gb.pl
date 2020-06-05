#!ENV PERL
use VERSION;
use strict;
use warnings;
use POSIX qw(setsid);
#use Data::Dumper;
my ($guestimg,$gbdir,$vfiodir,$socksdir,$virtiofsdsocksdir,$tmp,$pid,$rootdir)
= ($ARGV[0],"GUESTBRIDGEDIR", "VFIODIR","SOCKSDIR","VIRTIOFSDSOCKSDIR",undef,undef,'/');
my ($permit,@Config,%Bridge,%Tap,%Nic,%Tmp,%Master,%Path,@Kvm,@User) = ((),(),(),(),(),(),(),(),(),());
sub call {
    pipe(my ($rfh,$wfh)) or die "Cann't create pipe $!";
    my $pid = open(my $pipe,'-|') // die "Can't fork:$!";
    if(not $pid){
        # Child process.
        close($rfh);
        system(@_) == 0 or die "@_: $!";
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
    CORE::system(split(/ /, $_[0])) == 0 or die "$_[0]: $!";
}
sub daemon {
    if(not ($pid = fork)){
        # child
        die "cann't fork:$!" unless defined $pid;
        die "cann't chdir to $rootdir: $!" unless chdir $rootdir;
        umask 0077;
        die "can't setsid" if setsid() < 0;
        exec(split(/ /, $_[0])) or die "$_[0]: $!";
        # just in case child don't die.
        exit;
    }
}
( -r $guestimg ) || die "Guest image: $guestimg not avaliable.";
$_ = $guestimg;
s;.*\/;;;
s;\..*;;;
my $guestname = $_;
my $guestcfg = "$gbdir/conf/$_";
@Kvm = getpwnam('kvm');
@User = getpwnam(getlogin());
# Array is requred for call function.
$permit = qw(SUDO) unless $User[2] == 0;
die "Pls add: $User[0] to group: $Kvm[0]" unless $User[2] != $Kvm[2];

( -r $guestcfg ) || die "Guest config: $guestcfg not avaliable.";
( -c "$vfiodir/vfio" ) || die "$vfiodir/vfio not avaliable.";
( -S "$socksdir/$guestname" ) && die "$socksdir/$guestname still in place.";
if( ! -w $vfiodir || ! -x $vfiodir ){
    run("$permit CHOWN :$Kvm[3] $vfiodir");
    run("$permit CHMOD 0775 $vfiodir");
}
if( ! -d $virtiofsdsocksdir || ! -w $virtiofsdsocksdir || ! -x $virtiofsdsocksdir ){
    $tmp = int(rand(99999)) + 10000;
    $tmp = "/var/tmp/$tmp";
    mkdir( $tmp,0770);
    chmod( 0770, $tmp);
    chown($User[2],$Kvm[3],$tmp);
    run("$permit MV $tmp $virtiofsdsocksdir");
}

###########################
#     Parse config file
###########################

open(INPUT, '<', $guestcfg) or die "can't open $guestcfg.";
chomp(@Config = <INPUT>);
foreach(@Config){
    %Tmp = ();
    foreach(split(/,/)){
        # Every field
        next if(not m;([^"' ]+)\s*=\s*["']{0,1}([^"' ]+)["']{0,1};);
        $Tmp{$1} = $2;
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
}

############################
#        Virfiofs
############################
run("$permit CHMOD 4755 VIRTIOFSD");
foreach(keys %Path){
    next if( -S "$virtiofsdsocksdir$guestname-$_.sock" );
    daemon("VIRTIOFSD --syslog --socket-path=$virtiofsdsocksdir$guestname-$_.sock --thread-pool-size=6 -o source=$Path{$_}");
}
run("$permit CHMOD 0755 VIRTIOFSD");
__END__
##############################
#     Add taps and Bridges.
##############################
# All nic names
foreach(call(qw( IP -o link show))){
    %Tmp = ();
    @_ = split(/\s/);
    foreach(my $i = 3; $i < scalar(@_); $i++){
        next if(not $_[$i] =~ m;permaddr|link/ether|master;);
        $Tmp{$_[$i]} = $_[$i + 1];
    }
    $_[1] =~ tr/://d;
    $Nic{$Tmp{permaddr}} = $_[1] if(defined($Tmp{permaddr}));
    $Nic{$Tmp{'link/ether'}} = $_[1] if(defined($Tmp{'link/ether'}));
    $Master{$_[1]} = $Tmp{'master'} if(defined($Tmp{'master'}));
}
# One physical nic only belongs to one bridge.
foreach(values %Nic){
    defined($Bridge{$_}) || next;
    # Already has this bridge
    $Bridge{$_} = undef;
}
# Create bridges that are not already in place.
foreach(keys %Bridge){
    defined($Bridge{$_}) || next;
    # Bridge Name
    $tmp = $Nic{$Bridge{$_}};
    run("$permit IP address flush dev $tmp");
    run("$permit IP link add name $_ type bridge");
    run("$permit IP link set $_ up");
    run("$permit IP link set $tmp down");
    run("$permit IP link set $tmp up");
    run("$permit IP link set $tmp master $_");
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
    run("$permit IP link set dev $_ up");
    run("$permit IP link set $_ master $Tap{$_}");
    $Tap{$_} = undef;
}
# Add new taps and bridge it.
foreach(keys %Tap){
    defined($Tap{$_}) || next;
    run("$permit IP tuntap add dev $_ mode tap user $User[0]");
    run("$permit IP link set dev $_ up");
    $Tap{$_} =~ tr/://d;
    run("$permit IP link set $_ master $Tap{$_}");
    $Tap{$_} = undef;
}

##################################
#   start vm
##################################
if(not ($pid = fork)){
    # child
    die "cann't fork:$!" unless defined $pid;
    die "cann't chdir to $rootdir: $!" unless chdir $rootdir;
    umask 0077;
    die "can't setsid" if setsid() < 0;
 
    $tmp = "$permit QEMU -chroot /var/tmp/ -runas kvm @Config";
    exec(split(/ /, $tmp)) or die "cann't exec: $!";
    # just in case child don't die.
    exit;
}
#######################################
# Wait until virtiofsd created sockets.
# It's time to change permission.
#######################################

@_ = glob("$virtiofsdsocksdir*");
run("$permit CHOWN :$Kvm[0] @_");
run("$permit CHMOD g=rw @_");

sleep 1;
( -S "$socksdir/$guestname" ) || die "$socksdir/$guestname not yet created.";
run("$permit CHOWN $Kvm[0]:$Kvm[0] $socksdir/$guestname");
run("$permit CHMOD ug=rw $socksdir/$guestname");

#print Dumper(\@Config);
#print Dumper(\%Bridge);
#print Dumper(\%Nic);
#print Dumper(\%Master);
#print Dumper(\%Tap);
#print Dumper(\%Path);
#__END__
