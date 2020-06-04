#!ENV PERL
use VERSION;
use strict;
use warnings;
use Data::Dumper;
my ($guestimg,$gbdir,$vfiodir,$socksdir,$virtiofsdsocksdir,$tmp,$pid)
 = ( $ARGV[0],"GUESTBRIDGEDIR", "VFIODIR","SOCKSDIR","VIRTIOFSDSOCKSDIR",undef,undef);
my (@Permit,@Config,%Bridge,%Tap,%Nic,%Tmp,%Master,%Path,@Kvm,@User) = ((),(),(),(),(),(),(),(),(),());
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
( -r $guestimg ) || die "Guest image: $guestimg not avaliable.";
$_ = $guestimg;
s;.*\/;;;
s;\..*;;;
my $guestname = $_;
my $guestcfg = "$gbdir/conf/$_";
@Kvm = getpwnam('kvm');
@User = getpwnam(getlogin());
# Array is requred for call function.
@Permit = qw(SUDO) unless $User[2] == 0;
die "Pls add: $User[0] to group: $Kvm[0]" unless $User[2] != $Kvm[2];

( -r $guestcfg ) || die "Guest config: $guestcfg not avaliable.";
( -c "$vfiodir/vfio" ) || die "$vfiodir/vfio not avaliable.";
( -S "$socksdir/$guestname" ) && die "$socksdir/$guestname still in place.";
if( ! -w $vfiodir || ! -x $vfiodir ){
    system((@Permit,'CHOWN',":$Kvm[3]",$vfiodir));
    system((@Permit,'CHMOD','0775',$vfiodir));
}
if( ! -d $virtiofsdsocksdir || ! -w $virtiofsdsocksdir || ! -x $virtiofsdsocksdir ){
    $tmp = int(rand(99999)) + 10000;
    $tmp = "/var/tmp/$tmp";
    mkdir( $tmp,0770);
    chmod( 0770, $tmp);
    chown($User[2],$Kvm[3],$tmp);
    system((@Permit,'MV',$tmp,$virtiofsdsocksdir));
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
foreach(keys %Path){
    next if( -S "$virtiofsdsocksdir$guestname-$_.sock" );
    next if($pid = fork);
    # child
    die "cann't fork:$!" unless defined $pid;
    $tmp = "VIRTIOFSD --syslog --socket-path=$virtiofsdsocksdir$guestname-$_.sock --thread-pool-size=6 -o source=$Path{$_}";
    exec(split(/ /, $tmp)) or die "cann't exec: $!";
    # just in case child don't die.
    exit;
}

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
    system((@Permit,qw(IP address flush dev), $tmp));
    system((@Permit,qw(IP link add name), $_, qw(type bridge)));
    system((@Permit,qw(IP link set), $_, qw(up)));
    system((@Permit,qw(IP link set), $tmp, qw(down)));
    system((@Permit,qw(IP link set), $tmp, qw(up)));
    system((@Permit,qw(IP link set), $tmp, qw(master), $_));
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
    system((@Permit,qw(IP link set dev),$_,qw(up)));
    system((@Permit,qw(IP link set),$_ ,'master',$Tap{$_}));
    $Tap{$_} = undef;
}
# Add new taps and bridge it.
foreach(keys %Tap){
    defined($Tap{$_}) || next;
    system((@Permit,qw(IP tuntap add dev),$_,qw(mode tap user), $User[0]));
    system((@Permit,qw(IP link set dev),$_,qw(up)));
    $Tap{$_} =~ tr/://d;
    system((@Permit,qw(IP link set),$_ ,'master',$Tap{$_}));
    $Tap{$_} = undef;
}
#######################################
# Wait until virtiofsd created sockets.
# It's time to change permission.
#######################################

@_ = glob("$virtiofsdsocksdir*");
chmod( 0660, @_);
chown($User[2],$Kvm[3],@_);

##################################
#   start vm
##################################
if(not ($pid = fork)){
    # child
    die "cann't fork:$!" unless defined $pid;
    $tmp = "QEMU -chroot /var/tmp/ -runas kvm @Config";
    exec(split(/ /, $tmp)) or die "cann't exec: $!";
    # just in case child don't die.
    exit;
}
#print Dumper(\@Config);
#print Dumper(\%Bridge);
#print Dumper(\%Nic);
#print Dumper(\%Master);
#print Dumper(\%Tap);
#print Dumper(\%Path);
__END__
