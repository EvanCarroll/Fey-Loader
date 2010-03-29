package Fey::Loader;

use strict;
use warnings;

our $VERSION = '0.11';

use Moose;
use Fey::Loader::DBI;

has dbh => (
	isa        => 'Object'
	, is       => 'ro',
	, weak_ref => 1
	, required => 1
);

has 'subclass_package' => (
	isa       => 'Str'
	, is      => 'ro'
	, handles => qr/.*/
	, default => sub {
		my $self = shift;
		my $class = $self->meta->name;
		my $dbh = $self->dbh;

		my $driver = $dbh->{Driver}{Name};

    my $subclass = $class . '::' . $driver;

    {
        # Shuts up UNIVERSAL::can
        no warnings;
        return $subclass if $subclass->can('new');
    }

    return $subclass if eval "use $subclass; 1;";

    if ( $@ ) {
			die $@ unless $@ =~ /Can't locate/;
		}
		else {

    warn <<"EOF";

There is no driver-specific $class subclass for your driver ($driver)
... falling back to the base DBI implementation. This may or may not
work.

EOF

		}

    return $class . '::' . 'DBI';
	}

);

has '_subclass' => (
	isa       => 'Object'
	, is      => 'rw'
	, handles => ['make_schema']
);

sub BUILD {
	my ( $self, $params ) = @_;
	my $defer_to = $self->subclass_package->new( $params );
	$self->_subclass( $defer_to->new( $params ) );
}

1;

__END__

=head1 NAME

Fey::Loader - Load your schema definition from a DBMS

=head1 SYNOPSIS

  my $loader = Fey::Loader->new( dbh => $dbh );

  my $loader = Fey::Loader->new( dbh          => $dbh,
                                 schema_class => '...',
                                 table_class  => '...',
                               );

  my $schema = $loader->make_schema();

=head1 DESCRIPTION

C<Fey::Loader> takes a C<DBI> handle and uses it to construct a set of
Fey objects representing that schema. It will attempt to use an
appropriate DBMS subclass if one exists, but will fall back to using a
generic loader otherwise.

The generic loader simply uses the various schema information methods
specified by C<DBI>. This in turn depends on these methods being
implemented by the driver.

See the L<Fey::Loader::DBI> class for more details on what parameters the
C<new()> method accepts.

=head1 METHODS

This class provides the following methods:

=head2 Fey::Loader->new( dbh => $dbh )

Given a connected C<DBI> handle, this method returns a new loader. If
an appropriate subclass exists, it will be loaded and used. Otherwise,
it will warn and fall back to using L<Fey::Loader::DBI>. Optionally you
can explicitly state the C<subclass_package> as an argument.

All arguments are handed off to an instance of the C<subclass_package>, and
all calls to an instance of Fey::Loader are defered to the implimentation
of the C<subclass_package>. This means there are other arguments that are
valid to the constructor: case and point, to all subclasses of DBI the 
C<schema_name> is a valid argument.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-fey-loader@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2006-2008 Dave Rolsky, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
