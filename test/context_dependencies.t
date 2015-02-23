#!/usr/bin/env perl

# impact of changing a value within a context:
#   skipped ranked values which require the value may become valid
#   valid ranked values may become invalid

use strict;
use warnings;

use FindBin qw( $RealBin );
use lib "$RealBin/../lib";

use Test::More;

use Notifications;

use Config::Contextual;
use Config::Contextual::Setting;

my $config = shared_config();

my @setup = (
            { source => 'runtime',     },

            { source => 'cli',         name => 'run_style',     value => 'alpha', },

            { source => 'user_file',   name => 'debug',         value => 1,                     context => { run_style => 'test' }, },
            { source => 'user_file',   name => 'run_style',     value => 'dev',                 },
            { source => 'user_file',   name => 'run_style',     value => 'test',                context => { version => '2' }, },
            { source => 'user_file',   name => 'user_is_admin', value => 'yes',                 },

            { source => 'database',    requires => [ qw( db_name db_user db_password ) ] },
            { source => 'database',    name => 'version',       value => 2,                     context => { run_style => 'test' }, },
            { source => 'database',    name => 'run_style',     value => 'live', },
            { source => 'database',    name => 'db_only',       value => 'yes', },
            { source => 'database',    name => 'user_is_admin', value => 'no',                  flags   => { is_locked => 1 },
                                                                                                context => { run_style => 'live' },
                                                                                                },

            { source => 'app_default', name => 'debug',         value => 0,                     },
            { source => 'app_default', name => 'debug',         value => 2,                     context => { run_style => 'alpha' }, },
            { source => 'app_default', name => 'debug',         value => 3,                     context => { run_style => 'beta'  }, },
            { source => 'app_default', name => 'run_style',     value => 'live',                },
            { source => 'app_default', name => 'debug',         value => 4,                     },
            { source => 'app_default', name => 'version',       value => 1,                     },
            { source => 'app_default', name => 'db_name',       value => 'v2-db-name',          context => { version   => '2'    }, },
            { source => 'app_default', name => 'db_user',       value => 'v2-db-user',          context => { version   => '2'    }, },
            { source => 'app_default', name => 'db_password',   value => 'v2-db-password',      context => { version   => '2'    }, },
            { source => 'app_default', name => 'db_name',       value => 'live-db-name',        context => { run_style => 'live' }, },
            { source => 'app_default', name => 'db_user',       value => 'live-db-user',        context => { run_style => 'live' }, },
            { source => 'app_default', name => 'db_password',   value => 'live-db-password',    context => { run_style => 'live' }, },
            { source => 'app_default', name => 'db_name',       value => 'test-db-name',        context => { run_style => 'test' }, },
            { source => 'app_default', name => 'db_user',       value => 'test-db-user',        context => { run_style => 'test' }, },
            { source => 'app_default', name => 'db_password',   value => 'test-db-password',    context => { run_style => 'test' }, },
            );

# Setup fake config sources
my @source_names     = ();  # names of sources in prioritised order
my $source_with_name = {};  # name => object hash for quick updates
my $line             = {};  # current line number per source
foreach my $setup ( @setup )
    {
    my $source_name = $setup->{source};
    my $source      = $source_with_name->{$source_name};

    if( not $source_with_name->{$source_name} )
        {
        $source = test_source->new(
                                    requires => $setup->{requires},
                                    reverse  => $source_name eq 'runtime' ? 1 : 0,
                                    );
        $source_with_name->{$source_name} = $source;
        push @source_names, $source_name;
        }

    next if not $setup->{name};

    $source->add_setting(
                        Config::Contextual::Setting->new(
                                                        $setup->{name} => $setup->{value},
                                                        context        => $setup->{context},
                                                        flags          => $setup->{flags},
                                                        origin         => sprintf( "%s line %d", $source_name, ++$line->{$source_name} ),
                                                        )
                        );
    }

# setup configuration manager
foreach my $source_name ( @source_names )
    {
    $config->add_source( $source_name => $source_with_name->{$source_name} );
    }

debug( '-' x 100 );

# use configurations in various contexts
is( $config->value_of( 'run_style' ), 'alpha', 'initial config' );
is( $config->value_of( 'debug'     ),      2, 'initial config' );

debug( confg_controller => $config );

$config->set_value_of( run_style => 'fred' );
$config->set_value_of( run_style => 'test' );
$config->set_value_of( version   => '2', context => { version => '2' } );

debug( confg_controller => $config );

is( $config->value_of( 'debug'                           ),      1, 'side effect - different context' );
is( $config->value_of( 'run_style'                       ), 'test', 'changed setting'                 );
is( $config->value_of( 'debug', { run_style => 'live' }  ),      0, 'explicit context'                );

is( $config->value_of( 'run_style' ), 'test', 'unchanged default values' );
is( $config->value_of( 'debug'     ),      1, 'unchanged default values' );

note( "All settings:" );
foreach my $setting ( $config->all_settings() )
    {
    note( "    " . $setting->description() );
    }

note( "All settings for version = 1" );
foreach my $setting ( $config->all_settings( { version => 1 }) )
    {
    note( "    " . $setting->description() );
    }

note( "All settings for run_style = live" );
foreach my $setting ( $config->all_settings( { run_style => 'live' }) )
    {
    note( "    " . $setting->description() );
    }

$config->set_value_of( run_style => 'live' );
note( "All settings" );
foreach my $setting ( $config->all_settings() )
    {
    note( "    " . $setting->description() );
    }

note( "All settings for run_style = 'test'" );
foreach my $setting ( $config->all_settings( { run_style => 'test' } ) )
    {
    note( "    " . $setting->description() );
    }

note( "All settings for run_style = 'beta'" );
foreach my $setting ( $config->all_settings( { run_style => 'beta' } ) )
    {
    note( "    " . $setting->description() );
    }

note( "All settings" );
foreach my $setting ( $config->all_settings() )
    {
    note( "    " . $setting->description() );
    }


# TODO: steve 2015-02-22 dump ranked settings (all contexts)

detail( final_state => $config );

done_testing();
exit;

package test_source;

use strict;
use warnings;

use Notifications;

sub new             { my $class = shift; my $param = { @_ }; return bless { %{$param}, settings => [] }, $class; }
sub requirements    { my $self = shift; return @{ $self->{requires} || [] }; }
sub add_setting     { my $self = shift; push @{$self->{settings}}, shift; return; }

sub settings   
    {
    my $self = shift;

    return if $self->is_loading();

    $self->must_be_loaded();

    return reverse @{$self->{settings}} if $self->{reverse};
    return @{$self->{settings}};
    }

sub must_be_loaded  { my $self = shift; $self->load()   if not $self->is_loaded(); return; }
sub is_loading      { my $self = shift; return $self->{is_loading} ? 1 : 0; }
sub is_loaded       { my $self = shift; return $self->{is_loaded}  ? 1 : 0; }

sub load
    {
    my $self = shift;

    $self->{is_loaded}  = 0;
    $self->{is_loading} = 1;

    my $config = Config::Contextual->shared_config();
    foreach my $config_name ( $self->requirements() )
        {
        debug( sprintf( "Loading with %s:%s", $config_name, $config->value_of( $config_name ) // '<undef>' ) );
        }

    $self->{is_loading} = 0;
    $self->{is_loaded}  = 1;

    return;
    }

