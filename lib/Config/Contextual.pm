package Config::Contextual;

use strict;
use warnings;

use Exporter qw( import );
our @ISA    = qw( Exporter );
our @EXPORT = qw( shared_config );

use Notifications;

my $shared_config = undef;

sub shared_config { return $shared_config //= __PACKAGE__->new_config(); }

sub new_config
    {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{source_names}           = [];   # names in order of priority
    $self->{source}                 = {};   # name => object
    $self->{unloaded_source_names}  = [];   # queue of sources waiting to be loaded
    $self->{source_settings}        = {};   # source_name => setting_name => array of objects
    $self->{ranked_settings}        = {};   # setting_name => array of objects
    $self->{cache}                  = {};   # context_id => setting_name => settings object
    return $self;
    }

sub add_source
    {
    my $self        = shift;
    my $source_name = shift;
    my $source      = shift;

    $self->{source}{$source_name} =         $source;
    push @{$self->{source_names}},          $source_name;
    push @{$self->{unloaded_source_names}}, $source_name;

    return;
    }

sub source_names
    {
    my $self = shift;

    return @{$self->{source_names}};
    }

sub source
    {
    my $self        = shift;
    my $source_name = shift;

    error( "Unknown source: $source_name" )   if not $self->{source}{$source_name};

    return $self->{source}{$source_name};
    }

sub sources
    {
    my $self = shift;

    return map { $self->{source}{$_} } $self->source_names();
    }

sub set_value_of
    {
    my $self         = shift;
    my $setting_name = shift;
    my $value        = shift;
    my $param        = { @_ };

    my $source_name = $param->{source} || 'runtime';
    my $source      = $self->source( $source_name );
    $source->add_setting(
                        Config::Contextual::Setting->new(
                                                    $setting_name => $value,
                                                    context       => $param->{context},
                                                    flags         => $param->{flags},
                                                    origin        => sprintf "code: %s line %s", (caller(0))[1,2],
                                                    )
                        );

    # TODO: steve 2015-02-22 optimisation: just load the new setting
    push @{$self->{unloaded_source_names}}, $source_name;

    return;
    }

sub value_of
    {
    my $self         = shift;
    my $setting_name = shift;
    my $context      = shift;

    my $setting = $self->setting( $setting_name, $context );

    return  if not $setting;
    return $setting->value();
    }

sub all_setting_names
    {
    my $self = shift;

    $self->must_be_ready();

    my $duplicate = {};
    my @names = sort
                grep { not $duplicate->{$_}++ }
                map { keys %{$self->{source_settings}{$_}}}
                $self->source_names();

    return @names;
    }

sub all_settings
    {
    my $self    = shift;
    my $context = shift;

    return grep { $_ } map { $self->setting( $_, $context ) } $self->all_setting_names();
    }

sub setting
    {
    my $self           = shift;
    my $setting_name   = shift;
    my $lookup_context = shift;

    my $lookup_context_id = $self->context_id( $lookup_context );
    my $cache             = $self->cache( $lookup_context );

    debug( "looking up $setting_name (context: $lookup_context_id)" );

    # prevent deep recursion
    return  if $self->{is_looking_up}{$setting_name}++;

    $self->must_be_ready();

    if( not $cache->{is_valid}{$setting_name} )
        {
        miss( "Cached value: $setting_name (context: $lookup_context_id)" );

        my $matching_setting = undef;

        if( my $locked_by = $self->{cache}{locked_setting}{$setting_name} )
            {
            LOCKER:
            foreach my $locker ( values %{$locked_by} )
                {
                my $is_locked = 1;
                my $locking_context = $locker->context();
                foreach my $locking_name ( keys %{$locking_context} )
                    {
                    my $check_value = $self->value_of( $locking_name, $lookup_context );
                    info( sprintf "comparing locking context %s:%s with %s:%s", $locking_name, $locking_context->{$locking_name} // '~', $locking_name, $check_value // '~' );
                    $is_locked = 0  if not ( defined $check_value and $check_value eq $locking_context->{$locking_name} );
                    info( "is_locked = $is_locked" );
                    last if not $is_locked;
                    }
                if( $is_locked )
                    {
                    # early return - locked value, no need to look further!
                    delete $self->{is_looking_up}{$setting_name};
                    return $locker;
                    }
                }
            }

        RANKED_SETTING:
        foreach my $ranked_setting ( $self->ranked_settings( $setting_name ) )
            {
            # all of the setting's context pairs MUST match current context
            my $check_context = $ranked_setting->context();

            $cache->{impacted}{$_}{$setting_name} = undef   foreach keys %{$check_context};

            foreach my $check_name ( keys %{$check_context} )
                {
                my $current_value = $self->value_of( $check_name, $lookup_context );
                if( not defined $current_value or $check_context->{$check_name} ne $current_value )
                    {
                    detail( sprintf( "context mismatch: %s", $ranked_setting->description() ),
                                current  => sprintf( "%s:%s", $check_name, $current_value // '<undef>' ),
                                required => sprintf( "%s:%s", $check_name, $check_context->{$check_name}  ),
                                );
                    next RANKED_SETTING;
                    }
                }
            $matching_setting = $ranked_setting;
            detail( sprintf( "picked setting: %s", $matching_setting->description() ) );
            last RANKED_SETTING;
            }

        my $cached_value = $cache->{setting}{$setting_name} ? $cache->{setting}{$setting_name}->value() : undef;
        my $new_value    = $matching_setting        ? $matching_setting->value()        : undef;

        if( ( not defined $cached_value and not defined $new_value )
            or ( $cached_value and $new_value and $cached_value eq $new_value ) )
            {
            detail( sprintf( "Re-evaluated value unchanged: %s:%s (context: %s)",
                            $setting_name,
                            $new_value // '<undef>',
                            $lookup_context_id,
                            )
                  );
            }
        else
            {
            debug( sprintf( "changed value: %s:%s => %s (context: %s)",
                        $setting_name,
                        $cached_value // '<undef>',
                        $new_value    // '<undef>',
                        $lookup_context_id,
                        )
                    );
            $self->invalidate_impacted_settings( setting_names => [ $setting_name ], context_ids => [ $lookup_context_id ] );
            }

        $cache->{setting}{$setting_name}  = $matching_setting;
        $cache->{is_valid}{$setting_name} = 1;
        debug( sprintf( "cached valid value: %s:%s => %s (context: %s)",
                    $setting_name,
                    $cached_value // '<undef>',
                    $new_value    // '<undef>',
                    $lookup_context_id,
                    )
                );
        }
    else
        {
        hit( sprintf( "Cache value: %s:%s (context: %s)",
                    $setting_name,
                    $cache->{setting}{$setting_name}->value() // '<undef>',
                    $lookup_context_id,
                    )
                );
        }

    delete $self->{is_looking_up}{$setting_name};

    return $cache->{setting}{$setting_name};
    }

sub cache
    {
    my $self       = shift;
    my $context    = shift;
    my $context_id = $self->context_id( $context );

    if( not $self->{cache}{$context_id} )
        {
        $self->{cache}{$context_id} = {};
        my $cache = $self->{cache}{$context_id};

        foreach my $setting_name ( keys %{ $context || {} } )
            {
            $cache->{is_valid}{$setting_name} = 1;
            $cache->{setting}{$setting_name}  = Config::Contextual::Setting->new(
                                                                                $setting_name => $context->{$setting_name},
                                                                                origin        => sprintf "cache specifier: %s line %s", (caller(0))[1,2],,
                                                                                );
            }
        }

    return $self->{cache}{$context_id};
    }

sub context_id
    {
    my $self    = shift;
    my $context = shift || {};

    return join( ",", map { join( ":", $_, $context->{$_} ) } sort keys %{ $context || {} } );
    }

sub must_be_ready
    {
    my $self = shift;

    $self->load_unloaded_sources();

    return;
    }

sub load_unloaded_sources
    {
    my $self = shift;

    return if not @{$self->{unloaded_source_names}};

    start( "loading unloaded sources" );
    my $duplicate = {};
    while( my $source_name = shift @{$self->{unloaded_source_names}} )
        {
        next if $duplicate->{$source_name}++;
        $self->load_source_settings( $source_name );
        }
    finish( "loading unloaded sources" );

    return;
    }

sub load_source_settings
    {
    my $self        = shift;
    my $source_name = shift;

    debug( "Loading $source_name" );

    my $source_settings = $self->{source_settings}{$source_name} //= {};

    $self->invalidate_rankings( keys %{$source_settings} );

    %{$source_settings} = ();   # empty hash but keep reference
    foreach my $setting ( $self->{source}{$source_name}->settings() )
        {
        my $setting_name = $setting->name();
        debug( sprintf( "loaded %s", $setting->description() ) );
        $source_settings->{$setting_name} //= [];
        push @{$source_settings->{$setting_name}}, $setting;
        }

    $self->invalidate_rankings( keys %{$source_settings} );

    debug( "Loaded $source_name" );

    return;
    }

sub source_settings
    {
    my $self         = shift;
    my $source_name  = shift;
    my $setting_name = shift;

#     detail( "getting settings from: $source_name" );
    $self->load_source_settings( $source_name )     if not $self->{source_settings}{$source_name};

    return @{ $self->{source_settings}{$source_name}{$setting_name} || [] };
    }

sub ranked_settings
    {
    my $self         = shift;
    my $setting_name = shift;

    if( not $self->{ranked_settings}{$setting_name} )
        {
        miss( "ranked settings: $setting_name" );

        $self->{ranked_settings}{$setting_name} = [];
        my $ranking = $self->{ranked_settings}{$setting_name};

        # go through sources backwards in order to catch first instance of locked settings
        my $source_rank    = 1;
        SOURCE:
        foreach my $source_name ( reverse $self->source_names() )
            {
            $source_rank++;
            my $position_rank = 1;
            SETTING:
            foreach my $setting ( $self->source_settings( $source_name, $setting_name ) )
                {
                detail( sprintf "ranking: %s", $setting->description() );
                $position_rank++;
                my $context_rank = $setting->context_size();
                my $ranked_setting = {
                                    rank    => [ -$source_rank, -$context_rank, $position_rank ],
                                    setting => $setting,
                                    };
                push @{$ranking}, $ranked_setting;
                }
            }

        # sort by ranking
        @{$ranking} =   sort {
                               $a->{rank}[0] <=> $b->{rank}[0]
                            or $a->{rank}[1] <=> $b->{rank}[1]
                            or $a->{rank}[2] <=> $b->{rank}[2]
                            }
                        @{$ranking};
        debug( sprintf( "ranked %s settings", $setting_name ) => [ map {
                                                                                sprintf( "%s | %s",
                                                                                    sprintf( "%3d:%3d:%3d", @{$_->{rank}} ),
                                                                                    $_->{setting}->description(),
                                                                                    );
                                                                                }
                                                                            @{$ranking}
                                                                            ]
                );

        # set up locks globally by name and context - context used differently
        # to normal, so not kept in same structure as normal cached values
        delete $self->{cache}{locked_setting}{$setting_name};
        foreach my $setting ( reverse map { $_->{setting} } @{$ranking} )
            {
            if( $setting->is_locked() )
                {
                $self->{cache}{locked_setting}{$setting_name}{$setting->context_id()} //= $setting;
                }
            }
        }
    else
        {
        hit( "ranked settings: $setting_name" );
        }

    return map { $_->{setting} } @{ $self->{ranked_settings}{$setting_name} || [] };
    }

sub invalidate_rankings
    {
    my $self = shift;
    my @setting_names = @_;

    delete @{$self->{ranked_settings}}{@setting_names};

    if( @setting_names )
        {
        debug( "invalidated ranked settings for $_" ) foreach @setting_names;
        $self->invalidate_impacted_settings( setting_names => [ @setting_names ] );
        }

    return;
    }

sub invalidate_impacted_settings
    {
    my $self          = shift;
    my $param         = { @_ };
    my @setting_names = @{ $param->{setting_names} || []                         };
    my @context_ids   = @{ $param->{context_ids}   || [ keys %{$self->{cache}} ] };

    # TODO: steve 2015-02-22 better way with less impact?

    # invalidate the cached values within the default cache
    $self->invalidate_cached_values( '', @setting_names );

    # invalidate cached values of impacted settings in all contexts
    foreach my $context_id ( @context_ids )
        {
        my $cache = $self->{cache}{$context_id};
        debug( "checking impact",
                context_id => $context_id,
                impactors  => [ @setting_names ],
                impactees  => [ sort map { keys %{ $cache->{impacted}{$_} || {} } } @setting_names ],
                );
        $self->invalidate_cached_values( $context_id, map { keys %{ $cache->{impacted}{$_} || {} } } @setting_names );
        }

    return;
    }

sub invalidate_cached_values
    {
    my $self       = shift;
    my $context_id = shift;
    my @setting_names = @_;

    my $cache = $self->{cache}{$context_id};
    delete @{$cache->{is_valid}}{@setting_names};
    debug( "invalidated cached value of $_ (context: $context_id)" )  foreach @setting_names;

    return;
    }

1;
