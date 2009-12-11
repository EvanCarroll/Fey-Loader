package Fey::Loader::SQLite;

use strict;
use warnings;

use Moose;

extends 'Fey::Loader::DBI';

use DBD::SQLite;

use Fey::Validate qw( validate SCALAR_TYPE );


package # hide from PAUSE
    DBD::SQLite::Fixup;

BEGIN
{
    unless ( defined &DBD::SQLite::db::column_info )
    {
        *DBD::SQLite::db::column_info = \&_sqlite_column_info;
    }

    unless ( defined &DBD::SQLite::db::statistics_info )
    {
        *DBD::SQLite::db::statistics_info = \&_sqlite_statistics_info;
    }
}

sub _sqlite_column_info {
    my($dbh, $catalog, $schema, $table, $column) = @_;

    $column = undef
        if defined $column && $column eq '%';

    my $sth_columns = $dbh->prepare( qq{PRAGMA table_info('$table')} );
    $sth_columns->execute;

    my @names = qw( TABLE_CAT TABLE_SCHEM TABLE_NAME COLUMN_NAME
                    DATA_TYPE TYPE_NAME COLUMN_SIZE BUFFER_LENGTH
                    DECIMAL_DIGITS NUM_PREC_RADIX NULLABLE
                    REMARKS COLUMN_DEF SQL_DATA_TYPE SQL_DATETIME_SUB
                    CHAR_OCTET_LENGTH ORDINAL_POSITION IS_NULLABLE
                  );

    my @cols;
    while ( my $col_info = $sth_columns->fetchrow_hashref ) {
        next if defined $column && $column ne $col_info->{name};

        my %col;

        $col{TABLE_NAME} = $table;
        $col{COLUMN_NAME} = $col_info->{name};

        my $type = $col_info->{type};
        if ( $type =~ s/(\w+)\((\d+)(?:,(\d+))?\)/$1/ ) {
            $col{COLUMN_SIZE}    = $2;
            $col{DECIMAL_DIGITS} = $3;
        }

        $col{TYPE_NAME} = $type;

        $col{COLUMN_DEF} = $col_info->{dflt_value}
            if defined $col_info->{dflt_value};

        if ( $col_info->{notnull} ) {
            $col{NULLABLE}    = 0;
            $col{IS_NULLABLE} = 'NO';
        }
        else {
            $col{NULLABLE}    = 1;
            $col{IS_NULLABLE} = 'YES';
        }

        for my $key (@names) {
            $col{$key} = undef
                unless exists $col{$key};
        }

        push @cols, \%col;
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my $sth = $sponge->prepare("column_info $table", {
        rows => [ map { [ @{$_}{@names} ] } @cols ],
        NUM_OF_FIELDS => scalar @names,
        NAME => \@names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());
    return $sth;
}

sub _sqlite_statistics_info {
    my($dbh, $catalog, $schema, $table, $unique_only) = @_;

    my @names = qw( TABLE_CAT TABLE_SCHEM TABLE_NAME NON_UNIQUE INDEX_QUALIFIER
                    INDEX_NAME TYPE ORDINAL_POSITION COLUMN_NAME COLLATION
                    CARDINALITY PAGES FILTER_CONDITION
                 );

    my $sth_indexes = $dbh->prepare( qq{PRAGMA index_list('$table')} );
    $sth_indexes->execute;

    my @indexes;
    for my $index ( @{ $sth_indexes->fetchall_arrayref } ) {
        next if $unique_only && ! $index->[2];

        my $sth_index_info = $dbh->prepare( qq{PRAGMA index_info('$index->[1]')} );
        $sth_index_info->execute;

        for my $index_part ( @{ $sth_index_info->fetchall_arrayref } ) {
            my %index;

            $index{TABLE_NAME} = $table;
            $index{NON_UNIQUE} = $index->[2] ? 0 : 1;
            $index{INDEX_NAME} = $index->[1];
            $index{ORDINAL_POSITION} = $index_part->[1] + 1;
            $index{COLUMN_NAME} = $index_part->[2];

            push @indexes, \%index;
        }
    }

    my $sponge = DBI->connect("DBI:Sponge:", '','')
        or return $dbh->DBI::set_err($DBI::err, "DBI::Sponge: $DBI::errstr");
    my $sth = $sponge->prepare("statistics_info $table", {
        rows => [ map { [ @{$_}{@names} ] } @indexes ],
        NUM_OF_FIELDS => scalar @names,
        NAME => \@names,
    }) or return $dbh->DBI::set_err($sponge->err(), $sponge->errstr());
    return $sth;
}


package Fey::Loader::SQLite;

sub _add_table
{
    my $self       = shift;
    my $schema     = shift;
    my $table_info = shift;

    return if $table_info->{TABLE_NAME} =~ /^sqlite_/;

    $self->SUPER::_add_table( $schema, $table_info );
}

sub _is_auto_increment
{
    my $self     = shift;
    my $table    = shift;
    my $col_info = shift;

    my $name = $col_info->{COLUMN_NAME};

    my @pk = $self->_primary_key( $table->name() );

    # With SQLite3, a table can only have one autoincrement column,
    # and it must be that table's primary key ...
    return 0 unless @pk == 1 && $pk[0] eq $name;

    my $sql = $self->_table_sql( $table->name() );

    # ... therefore if the table's SQL includes the string
    # autoincrement, then the primary key must be auto-incremented.
    return $sql =~ /autoincrement/m ? 1 : 0;
}

sub _primary_key
{
    my $self = shift;
    my $name = shift;

    return @{ $self->{__primary_key__}{$name} }
        if $self->{__primary_key__}{$name};

    my @pk = $self->dbh()->primary_key( undef, undef, $name );
    $self->{__primary_key__}{$name} = \@pk;

    return @pk;
}

sub _table_sql
{
    my $self = shift;
    my $name = shift;

    return $self->{__table_sql__}{$name}
        if $self->{__table_sql__}{$name};

    return $self->{__table_sql__}{$name} =
        $self->dbh()->selectcol_arrayref
            ( 'SELECT sql FROM sqlite_master WHERE tbl_name = ?', {}, $name )->[0];
}

sub _default
{
    my $self    = shift;
    my $default = shift;

    if ( $default =~ /CURRENT_(?:TIME(?:STAMP)?|DATE)/ )
    {
        return Fey::Literal::Term->new($default);
    }
    else
    {
        return $self->SUPER::_default($default);
    }
}

no Moose;
__PACKAGE__->meta()->make_immutable();

1;

__END__

=head1 NAME

Fey::Loader::SQLite - Loader for Postgres schemas

=head1 SYNOPSIS

  my $loader = Fey::Loader->new( dbh => $dbh );

  my $schema = $loader->make_schema( name => $name );

=head1 DESCRIPTION

C<Fey::Loader::SQLite> implements some SQLite-specific loader
behavior.

=head1 METHODS

This class provides the same public methods as L<Fey::Loader::DBI>.

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
