package Database::Migrator::Types;

use strict;
use warnings;

our $VERSION = '0.13';

use MooseX::Types::Moose;
use MooseX::Types::Path::Class;
use Path::Class ();

use parent 'MooseX::Types::Combine';

__PACKAGE__->provide_types_from(
    'MooseX::Types::Moose',
    'MooseX::Types::Path::Class',
);

1;

# ABSTRACT: Type library for use by Database::Migrator

__END__

=pod

=for Pod::Coverage .*

=cut
