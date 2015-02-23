Config-Contextual
-----------------

Yet another configuration module :-)

Goals:
------

    storage agnostic.       use whatever format(s) or source(s) you like
    auditable.              find out where that configuration setting came from
    dynamic.                provide different values based on the current context, which can change at any time
    simple to configure.    configuration must be understandable for the end-user.
    simple to use.          code should do no more than ask for a configuration variable of a certain name.

Design:
-------

    Settings:
        Each configuration variable is defined by one or more setting objects.
        Each object defines the name and value(s) of the variable, as well as
        an optional context and/or set of flags to indicate how the variable
        should be managed.

        Settings have been intentionally designed to be simple LISTS of 1 or more
        textual or numerical values. (think of a typical configuration dialog:
        mostly on/off, name, number, or level information.)

        A context may be provided with each setting, defining under what circumstances
        the value is valid.

        Finally, flags such as 'hidden' or 'locked' may be applied to a setting to
        indicate that it must not be included in logfiles etc. or may not be
        overridden by higher priority settings with overlapping context.

    Singleton controller:
        The controller is the global mediator between configuration sources
        (files, database, network, environment variables, ...) and your
        program.
        Generally there will only be one configuration controller, but
        singleton operation is not enforced in any way.

        The controller provides little more than the following API:

            add_source( <name>, <source object> )
            all_settings()
            setting( <name> )
            value_of( <name>, [ <context> ] )
            set_value_of( <name>, <value)>, [ <context>, <flags>, <source> ] )

    Setting sources:
        The controller uses one or more source objects to get and set configuration
        settings in configuration files etc.
        A setting source can be any object which provided the following methods:

            settings()
            can_store_settings()
            store_setting( <setting> )

        Sources are processed in the order in which they are provided, so an extreme
        configuration might look something like:

            config->add_source( runtime              => ... );
            config->add_source( command_line         => ... );
            config->add_source( environment          => ... );
            config->add_source( user_config_db       => ... );
            config->add_source( user_config_file     => ... );
            config->add_source( network_config       => ... );
            config->add_source( config_db            => ... );
            config->add_source( host_config          => ... );
            config->add_source( application_defaults => ... );

        Each object simply provides its settings via the settings() method.
        Note that these objects may also use configuration settings for connection
        data, for example: config_db will probably need a database name, user and password
        in order to connect.
        In this case, the config_db will be 'put on hold' until suitable values can be
        found (or undef is returned because no value was found anywhere).
            
    Handling settings:
        Settings are first collected from all sources and ranked according to the following
        criteria:

            the position of the source in the source list (runtime first, application_defaults last)

            the context specificity, the more elements in a setting's context the higher the priority

            the position of the setting within it's sources settings (for this
                    reason, sources should NOT sort settings, but rather return
                    them in priority order: e.g. files must return settings in
                    the same order as they appear in the file, runtime sources
                    should return their settings in reverse chronological order
                    (newest first)

        Whenever a setting is loaded from a source, any existing ranking will
        be destroyed and re-created on demand.

        In order to get a setting's value, the following process is used:

            ensure that all sources have provided their settings
                note: some sources may specify that their settings be re-loaded
                under certain circumstances

            ensure that the setting objects with the specified name are sorted
            according to the above ranking.

            prepare a context cache for the requested context
                add a dummy setting object for each context value

            evaluate the context of each setting in order until a setting is found
            which has a valid context. (The empty context is always valid!)

            cache the value in conjunction with the requested context

            return the cached value

    Special considerations:
        
        Sources must be re-entrant safe.
            The settings() method must return the full list of settings, or if
            the method is called while loading settings, it must return nothing.

        Whenever settings are invalidated, their cached value is retained. Only if the
            value obtained after re-validating the setting is different will a
            'setting_changed' notification be sent.
