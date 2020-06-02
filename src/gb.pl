#!ENV PERL
use VERSION;
use strict;
use warnings;
use Data::Dumper;
my ($guestimg,$gbdir,$vfiodir,$socksdir,$tmp,$user)
 = ( $ARGV[0],"GUESTBRIDGEDIR", "VFIODIR", "SOCKSDIR",undef,getlogin());
my (@Permit,@Config,%Bridge,%Tap,%Nic,%Tmp,%Master) = ( (), (), (), (), (),(),());
sub call {
    pipe(my ($rfh,$wfh)) or die "Cann't create pipe $!";
    my $pid = open(my $pipe,'-|') // die "Can't fork:$!";
    if(not $pid){
        # Child process.
        close($rfh);
        CORE::system(@_) == 0 or die "@_: $!";
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
( -r $guestcfg ) || die "Guest config: $guestcfg not avaliable.";
( -c "$vfiodir/vfio" ) || die "$vfiodir/vfio not avaliable.";
( -S "$socksdir/$guestname" ) && die "$socksdir/$guestname still in place.";
# Array is requred for call function.
@Permit = qw(SUDO) if ( $< != 0 ); 
if( not $user cmp getgrnam('kvm')){
    die "Pls manually add UID: $< to group: kvm";
}
open(INPUT, '<', $guestcfg) or die "can't open $guestcfg.";
chomp(@Config = <INPUT>);
# Requred bridges and taps
foreach(@Config){
    foreach(split(/,/)){
        next if(not m;([^"' ]+)\s*=\s*["']{0,1}([^"' ]+)["']{0,1};);
        $Tmp{$1} = $2;
    }
    defined($Tmp{mac}) || next;
    defined($Tmp{netdev}) || next;
    $Tap{$Tmp{netdev}} = $Tmp{mac};
    $tmp = $Tmp{mac} =~ tr/://rd;
    $Bridge{$tmp} = $Tmp{mac}; 
}
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
    call((@Permit,qw(IP address flush dev), $tmp));
    call((@Permit,qw(IP link add name), $_, qw(type bridge)));
    call((@Permit,qw(IP link set), $_, qw(up)));
    call((@Permit,qw(IP link set), $tmp, qw(down)));
    call((@Permit,qw(IP link set), $tmp, qw(up)));
    call((@Permit,qw(IP link set), $tmp, qw(master), $_));
}
# Filter out exist taps
foreach(values %Nic){
    defined($Tap{$_}) || next;
    # Already has this tap and it's also bridged.
    if(defined($Master{$_})){
        $Tap{$_} = undef;
        next;
    }
    $Tap{$_} =~ tr/://d;
    call((@Permit,qw(IP link set),$_ ,'master',$Tap{$_}));
    $Tap{$_} = undef;
}
# Add taps
foreach(keys %Tap){
    defined($Tap{$_}) || next;
    call((@Permit,qw(IP tuntap add dev),$_,qw(mode tap user), $user));
    $Tap{$_} =~ tr/://d;
    call((@Permit,qw(IP link set),$_ ,'master',$Tap{$_}));
    $Tap{$_} = undef;
}
=head
# Filter out already bridged taps
foreach(keys %Master){
    defined($Tap{$_}) || next;
    $Tap{$_} = undef;
}
=cut
#print Dumper(\@Config);
#print Dumper(\%Bridge);
#print Dumper(\%Nic);
print Dumper(\%Master);
print Dumper(\%Tap);
