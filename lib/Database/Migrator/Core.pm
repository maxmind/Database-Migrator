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

requires qw(
    _build_database_exists
    _build_dbh
    _create_database
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

has _dbh => (
    is       => 'ro',
    isa      => 'DBI::db',
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_dbh',
);

has _logger => (
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

sub install_or_update_schema {
    my $self = shift;

    if ( $self->_database_exists() ) {
        my $database = $self->database();
        $self->_logger()->info("The $database database already exists");
    }
    else {
        $self->_create_database();
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

    $self->_logger->info("Running migration - $name");

    my @files = grep { !$_->is_dir() } $migration->children( no_hidden => 1 );

    for my $file ( sort @files ) {
        my $basename = $file->basename();
        if ( $file =~ /\.sql/ ) {
            $self->_logger()->debug(" - running $basename as sql");

            my $migration_ddl = read_file( $file->stringify() );

            $self->_run_ddl($migration_ddl);
        }
        else {
            $self->_logger()->debug(" - running $basename as perl code");

            my $perl = read_file( $file->stringify() );

            my $sub = eval_closure( source => $perl );

            $sub->($self);
        }
    }

    my $table = $self->_dbh()->quote_identifier( $self->migration_table() );
    $self->_dbh()->do( "INSERT INTO $table VALUES (?)", undef, $name );

    return;
}

sub _run_command {
    my $self    = shift;
    my $command = shift;
    my $input   = shift;

    my $stdout = q{};
    my $stderr = q{};

    my $handle_stdout = sub {
        $self->_logger()->debug(@_);

        $stdout .= $_ for @_;
    };

    my $handle_stderr = sub {
        $self->_logger()->debug(@_);

        $stderr .= $_ for @_;
    };

    $self->_logger()->debug("Running command: [@{$command}]");

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
    if ( grep { $_ =~ /\b\Q$table\E\b/ } $self->_dbh()->tables() ) {
        my $quoted = $self->_dbh()->quote_identifier($table);

        %ran
            = map { $_ => 1 }
            @{ $self->_dbh()
                ->selectcol_arrayref("SELECT migration FROM $quoted") || [] };
    }

    return [
        sort
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

1;
