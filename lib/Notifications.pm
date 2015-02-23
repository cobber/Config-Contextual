# really simple notifications
package Notifications;

use strict;
use warnings;

use Exporter qw( import );
our @ISA    = qw( Exporter );
our @EXPORT = qw( detail debug hit miss start finish info warning error );

use YAML;

sub notify
    {
#     return;
    my $event = uc( shift );
    my $msg   = ( @_ % 2 ) ? shift : undef;
    my $param = { @_ };
    $msg //= delete $param->{message};

    my $indent = "\t\t";
    printf "%-15s %s\n", $event . ':', join( "\n$indent",
            map  { s/\n/\n$indent/gmr }
            grep { $_ }
            (
                $msg,
                keys %{$param} ? ( Dump( $param ) . '...' ) : undef,
            )
        );
    return;
    }

sub detail  { return; notify( 'detail',  @_ ); }
sub debug   { return; notify( 'debug',   @_ ); }
sub hit     { return; notify( 'hit',     @_ ); }
sub miss    { return; notify( 'miss',    @_ ); }
sub start   { return; notify( 'start',   @_ ); }
sub finish  { return; notify( 'finish',  @_ ); }
sub info    { notify( 'info',    @_ ); }
sub warning { notify( 'warning', @_ ); }
sub error   { notify( 'error',   @_ ); }

1;
