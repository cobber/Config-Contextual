package Config::Contextual::Setting;

use strict;
use warnings;

use Notifications;

sub new
    {
    my $class = shift;
    my $name = shift;
    my $value = shift;
    $value = [ $value ] if ref $value ne 'ARRAY';
    my $self = bless { name => $name, value => $value, @_ }, $class;
    detail( "New setting", setting => $self );
    return $self;
    }

sub name         { my $self = shift; return $self->{name};     }
sub value        { my $self = shift; return $self->{value}[0]; }
sub context      { my $self = shift; return $self->{context};  }
sub context_size { my $self = shift; return $self->{context_size} //= scalar keys %{ $self->{context} || {} } }
sub context_id   { my $self = shift; my $context = $self->{context}; return join( ",", map { join( ":", $_, $context->{$_} ) } sort keys %{ $context || {} } ); }
sub origin       { my $self = shift; return $self->{origin};   }

sub flags        { my $self = shift; return $self->{flags}; }
sub is_locked    { my $self = shift; return $self->{flags}{is_locked} ? 1 : 0; }
sub is_hidden    { my $self = shift; return $self->{flags}{is_hidden} ? 1 : 0; }
sub description
    {
    my $self = shift;
    return sprintf( "%-s | %s | %s | %s",
                    $self->name(),
                    $self->value(),
                    $self->context_id(),
                    $self->origin(),
                    );
    }

1;
