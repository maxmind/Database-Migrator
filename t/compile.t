use strict;
use warnings;

use Test::Fatal;
use Test::More;

{

    package Test::Migrator;

    use Moose;

    sub _build_database_exists { }
    sub _build_dbh             { }
    sub _create_database       { }
    sub _run_ddl               { }

    ::is(
        ::exception{ with 'Database::Migrator::Core' },
        undef,
        'no exception consuming Database::Migrator::Core role'
    );
}

done_testing();
