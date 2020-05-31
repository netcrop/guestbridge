#!ENV PERL
use VERSION;
use Env qw(USER);
use strict;
use warnings;
use Cwd 'realpath';
use Data::Dumper;
my ($guestimg, $gbdir,$vfiodir,$socksdir,@cmd,@config) 
= ($ARGV[0],'GUESTBRIDGEDIR','VFIODIR','SOCKSDIR',(),());
sub call {
    pipe(my ($rfh,$wfh)) or die "Cann't create pipe $!";
    my $pid = open(my $pipe,'-|') // die "Can't fork:$!";
    if(not $pid){
        # Child process.
        close($rfh);
        CORE::system(@_);
        exit;
    }
    # Parent process.
    close($wfh);
    close($rfh);
    $_ = join("",<$pipe>);
    close($pipe);
    return $_;
}
if( not -r $guestimg){
    say "Guest image: $guestimg not avaliable.";
    exit;
}
$_ = $guestimg;
s;.*\/;;;
s;\..*;;;
my $guestname = $_;
my $guestcfg = "$gbdir/conf/$_";
if( not -r $guestcfg ){
    die "Guest config: $guestcfg not avaliable.";
}
if( not -c "$vfiodir/vfio" ){
    die "$vfiodir/vfio not avaliable.";
}
if( -S "$socksdir/$guestname" ) {
    die "$socksdir/$guestname still in place.";
}
if ( $USER ne 'root' ) {
    $cmd[0] = 'SUDO';
}
$_ = call(("GROUPS"));
if(not m;kvm;){
    push @cmd, "GPASSWD","-a","$USER","kvm";
    call(@cmd);
    die "Added $USER to kvm group. Pls logout and login again.";
}
open(INPUT, '<', $guestcfg) or die "can't open $guestcfg.";
@config = <INPUT>;
foreach(@config){
    s;GUESTNAME;$guestname;g;
}
print Dumper(\@config);
