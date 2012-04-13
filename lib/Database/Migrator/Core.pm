package Database::Migrator::Core;

use strict;
use warnings;
use namespace::autoclean;
use autodie ':all';

use Database::Migrator::Types qw( ArrayRef Bool Dir File Maybe Str );
use DBI;
use Eval::Closure qw( eval_closure );
use File::Slurp qw( read_file );
use IPC::Run3 qw( run3 );
use Log::Dispatch;
use Moose::Util::TypeConstraints qw( duck_type );

use Moose::Role;

with 'MooseX::Getopt::Dashes';

requires qw(
    _build_database_exists
    _build_dbh
    _create_database
    _run_ddl
);

has database => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has [qw( user password host port )] => (
    is      => 'ro',
    isa     => Maybe [Str],
    default => undef,
);

has migration_table => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has migrations_dir => (
    is       => 'ro',
    isa      => Dir,
    coerce   => 1,
    required => 1,
);

has schema_file => (
    is       => 'ro',
    isa      => File,
    coerce   => 1,
    required => 1,
);

has _database_exists => (
    is       => 'ro',
    isa      => Bool,
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_database_exists',
);

has __pending_migrations => (
    traits   => ['Array'],
    is       => 'ro',
    isa      => ArrayRef [Dir],
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_pending_migrations',
    handles  => {
        _pending_migrations    => 'elements',
        has_pending_migrations => 'count',
    },
);

has dbh => (
    traits   => ['NoGetopt'],
    is       => 'ro',
    isa      => 'DBI::db',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_dbh',
);

has logger => (
    traits  => ['NoGetopt'],
    is      => 'ro',
    isa     => duck_type( [qw( debug info )] ),
    builder => '_build_logger',
);

has verbose => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has quiet => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

has dry_run => (
    is      => 'ro',
    isa     => Bool,
    default => 0,
);

sub BUILD { }
after BUILD => sub {
    my $self = shift;

    die 'Cannot be both quiet and verbose'
        if $self->quiet() && $self->verbose();
};

sub create_or_update_database {
    my $self = shift;

    if ( $self->_database_exists() ) {
        my $database = $self->database();
        $self->logger()->info("The $database database already exists");
    }
    else {
        $self->_create_database();

        my $schema_ddl = read_file( $self->schema_file()->stringify() );
        $self->_run_ddl($schema_ddl);
    }

    $self->_run_migrations();

    return;
}

sub _run_migrations {
    my $self = shift;

    $self->_run_one_migration($_) for $self->_pending_migrations();
}

sub _run_one_migration {
    my $self      = shift;
    my $migration = shift;

    my $name = $migration->basename();

    $self->logger->info("Running migration - $name");

    my @files = grep { !$_->is_dir() } $migration->children( no_hidden => 1 );

    for my $file ( sort _numeric_or_alpha_sort @files ) {
        my $basename = $file->basename();
        if ( $file =~ /\.sql/ ) {
            $self->logger()->debug(" - running $basename as sql");

            my $migration_ddl = read_file( $file->stringify() );

            $self->_run_ddl($migration_ddl);
        }
        else {
            $self->logger()->debug(" - running $basename as perl code");

            my $perl = read_file( $file->stringify() );

            my $sub = eval_closure( source => $perl );

            next if $self->dry_run();

            $sub->($self);
        }
    }

    return if $self->dry_run();

    my $table = $self->dbh()->quote_identifier( $self->migration_table() );
    $self->dbh()->do( "INSERT INTO $table VALUES (?)", undef, $name );

    return;
}

sub _run_command {
    my $self    = shift;
    my $command = shift;
    my $input   = shift;

    my $stdout = q{};
    my $stderr = q{};

    my $handle_stdout = sub {
        $self->logger()->debug(@_);

        $stdout .= $_ for @_;
    };

    my $handle_stderr = sub {
        $self->logger()->debug(@_);

        $stderr .= $_ for @_;
    };

    $self->logger()->debug("Running command: [@{$command}]");

    return if $self->dry_run();

    run3( $command, \$input, $handle_stdout, $handle_stderr );

    if ($?) {
        my $exit = $? >> 8;

        my $msg = "@{$command} returned an exit code of $exit\n";
        $msg .= "\nSTDOUT:\n$stdout\n\n" if length $stdout;
        $msg .= "\nSTDERR:\n$stderr\n\n" if length $stderr;

        die $msg;
    }

    return $stdout;
}

sub _build_pending_migrations {
    my $self = shift;

    my $table = $self->migration_table();

    my %ran;
    if ( grep { $_ =~ /\b\Q$table\E\b/ } $self->dbh()->tables() ) {
        my $quoted = $self->dbh()->quote_identifier($table);

        %ran
            = map { $_ => 1 }
            @{ $self->dbh()
                ->selectcol_arrayref("SELECT migration FROM $quoted") || [] };
    }

    return [
        sort _numeric_or_alpha_sort
            grep { !$ran{ $_->basename() } }
            grep { $_->is_dir() }
            $self->migrations_dir()->children( no_hidden => 1 )
    ];
}

sub _build_logger {
    my $self = shift;

    my $outputs
        = $self->quiet()
        ? [ 'Null', min_level => 'emerg' ]
        : [
        'Screen',
        min_level => ( $self->verbose() ? 'debug' : 'info' ),
        newline => 1,
        ];

    return Log::Dispatch->new( outputs => [$outputs] );
}

around _build_dbh => sub {
    my $orig = shift;
    my $self = shift;

    my $dbh = $self->$orig(@_);

    $dbh->{RaiseError}         = 1;
    $dbh->{PrintError}         = 1;
    $dbh->{PrintWarn}          = 1;
    $dbh->{ShowErrorStatement} = 1;

    return $dbh;
};

sub  _numeric_or_alpha_sort {
    my ( $a_num, $a_alpha ) = $a->basename() =~ /^(\d+)(.+)/;
    my ( $b_num, $b_alpha ) = $b->basename() =~ /^(\d+)(.+)/;

    $a_num ||= 0;
    $b_num ||= 0;

    return $a_num <=> $b_num or $a_alpha cmp $b_alpha;
}

1;

# ABSTRACT: Core role for Database::Migrator implementation classes

__END__

=head1 SYNOPSIS

  package Database::Migrator::SomeDB;

  use Moose;
  with 'Database::Migrator::Core';

  sub _build_database_exists { ... }
  sub _build_dbh             { ... }
  sub _create_database       { ... }

=head1 DESCRIPTION

This role implements the bulk of the migration logic, leaving a few details up
to DBMS-specific classes.

You can then subclass these DBMS-specific classes to provide defaults for
various attributes, or to override some of the implementation.

=head1 PUBLIC ATTRIBUTES

This role defines the following public attributes. These attributes may be
provided via the command line or you can set defaults for them in a subclass.

=over 4

=item * database

The name of the database that will be created or migrated. This is required.

=item * user, password, host, port

These parameters are used when connecting to the database. They are all
optional.

=item * migration_table

The name of the table which stores the name of applied migrations. This is
required.

=item * migrations_dir

The directory containing migrations. This is required, but it is okay if the
directory is empty.

=item * schema_file

The full path to the file containing the initial schema for the database. This
will be used to create the database if it doesn't already exist. This is required.

=item * verbose

This affects the verbosity of output logging. Defaults to false.

=item * quiet

If this is true, then no output will logged at all. Defaults to false.

=item * dry_run

If this is true, no migrations are actually run. Instead, the code just logs
what it I<would> do. Defaults to false.

=back

=head1 METHODS

This role provide just one public method, C<create_or_update_database()>.

It will create a new database if none exists.

It will run all unapplied migrations on this schema once it does exist.

=head1 REQUIRED METHODS

If you want to create your own implementation class, you must implement the
following methods. All of these methods should throw an error

=head2 $migrator->_build_database_exists()

This should return a boolean value indicating whether or not the database
already exists.

=head2 $migration->_build_dbh()

This should return a new L<DBI> handle by calling C<< DBI->connect(...) >>
with the appropriate parameters.

=head2 $migration->_create_database()

This should create an I<empty> database. This role will take care of executing
the DDL for defining the schema.

=head2 $migration->_run_ddl($ddl)

Given a string containing one or more DDL statements, this method must run
that DDL against the database.
