use strict;
use warnings;

use Fey::Test;
use Test::More tests => 4;

use Fey::Loader;

{
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= $_ for @_ };

    my $loader = Fey::Loader->new( dbh => Fey::Test->mock_dbh() );
    like( $warnings, qr/no driver-specific Fey::Loader subclass/,
          'warning was emitted when we could not find a driver-specific load subclass' );

    is( $loader->subclass_package, 'Fey::Loader::DBI' );
}

SKIP:
{
    skip 'These tests require DBD::SQLite 1.14+', 2
        unless eval 'use DBD::SQLite 1.14; 1;';

    my $dbh = Fey::Test->mock_dbh();
    $dbh->{Driver}{Name} = 'SQLite';

		{
  	  my $loader = Fey::Loader->new( dbh => $dbh );
	    is( $loader->subclass_package, 'Fey::Loader::SQLite', 'found the right subclass' );
		}

    {
			# Make sure Fey::Loader finds the right subclass after that subclass
	    # has been loaded.
	    my $loader = Fey::Loader->new( dbh => $dbh );
	    is( ref $loader->_subclass, 'Fey::Loader::SQLite', 'works after load' );
		}

}

