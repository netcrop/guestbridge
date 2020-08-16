#!/bin/env /bin/perl
use v5.30.3;
use strict;
use warnings;
use Data::Dumper;
my $progname = $0;
my $fh;
my $tmp;
my $quotewords = '[^\;\{\}\(\)][^\;\(\)]*';
my $identifier = '[a-zA-Z0-9_\-]';
my %fp = ();
my %cmd = ();
my @path = ('/usr/local/bin','/usr/bin');
if( defined $ARGV[0] && -r $ARGV[0]){
    my $file = $ARGV[0];
    open($fh, '<', $file) or die "can't open $file: $!";
}else{
    open($fh, '<-') or die "can't open stdin: $!";
}
@_ = <$fh>;
close($fh);
die "empty input" unless scalar @_ > 0;
sub which {
    foreach ( @path ) {
        foreach (glob "$_/*") {
            next unless -x $_ && ! -d $_;
            $tmp = s;.*/;;r;
            $cmd{$tmp} = $_ unless defined $cmd{$tmp};
        }
    }
}
which();
#print Dumper(\%cmd);
####################################
# $1 already taken by caller
# callee has to use named capture.
####################################
sub replace {
    # $_[0] will be changed by the following match. 
    $tmp = $_[0];
    $_ = $_[1] =~ s;\b(?<condition>if|unless)\b;\) $+{condition};r;
    return "${tmp}($_" if defined $+{condition};
    return "${tmp}($_[1])";
}
sub translate {
    # $_[0] will be changed by the following match. 
    $tmp = $_[0];
    $_ = $_[1] =~ s;\b(?<condition>if|unless)\b;\"\) $+{condition};r;
    return "${tmp}(\"$_" if defined $+{condition};
    return "${tmp}(\"$_[1]\")";
}
$fp{qw} = \&replace;
$fp{run} = \&translate;
$fp{call} = \&translate;
$fp{daemon} = \&translate;
$_ = $_[0] =~ s;^#\!\s*ENV\s*PERL$;#!$cmd{env} $cmd{perl};r;
print "$_";
shift @_;
foreach(@_){
    # ignore all comments
    if( m;\s*#;){
        print $_;
        next;
    }
    s{
        use[ ]+VERSION
    }{
        "use $^V";
    }sex;
    s{
        (@|%){0,1}\b{wb}me\.(\w+)([\;\) ]){0,1}
    }{
        if( defined $1 && defined $2 && defined $3){
            "${1}{\$me{${2}}}$3";
        }elsif( defined ($tmp = $cmd{lc($2)})){ 
            if( defined $3){
                "${tmp} $3"; 
            }else{
                "\$me{${2}}";
            }
        }elsif( defined $3){
            "\$me{${2}}$3";
        }else{
            "\$me{${2}}";
        }
    }sexg;
    s{
        \b{wb}(qw|run|call|daemon)[ ]+(${quotewords}) 
    }{
        next unless defined $1 && defined $2;
        $fp{$1}($1, $2);
    }sexg;
    s{
        \b{wb}(us)\b{wb} 
    }{
        next unless defined $1;
        "\$_";
    }sexg;
    print $_;
}
