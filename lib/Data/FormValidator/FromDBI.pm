package Data::FormValidator::FromDBI;

use 5.005;
use strict;
use Params::Validate qw/validate_pos/;

require Exporter;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

$VERSION = '0.04_01';

@ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Data::FormValidator::FromDBI ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
%EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

@EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

@EXPORT = qw( generate_profile	);


sub generate_profile {
	validate_pos (@_,1,1);
	my ($dbh,$table) = @_;

    # parameters are: $catalog, $schema, $table, $column
    my $sth = $dbh->column_info( undef, undef , $table, undef ) ||
		die 'table attributes not found';

	my %profile = ();

	my %Text_Types = (qw/
		12 	1
		1	1
	/);

	for my $col (@{ $sth->fetchall_arrayref({})  }) {
		_add_required_or_optional(\%profile,$col->{COLUMN_NAME},$col->{NULLABLE});

		_add_length_constraint(\%profile,$col->{COLUMN_NAME},$col->{COLUMN_SIZE}) if $Text_Types{$col->{DATA_TYPE}};

		_add_type_constraints(\%profile,$col->{COLUMN_NAME},$col->{DATA_TYPE},$col->{TYPE_NAME});

		_add_db_constraint(\%profile,$col->{COLUMN_NAME},$col->{pg_constraint}) if ($col->{pg_constraint});
	}

	# transform validator packages to hash to array.
	# (storing it as a hash in the the first place prevented dupes)
	$profile{validator_packages} = [  keys %{ $profile{validator_packages} } ] if $profile{validator_packages};

	return \%profile;
}

=head1 INTERNAL DOCUMENTATION

The below documentation is provided for developers of this module
only. These APIs may change without notice. Mere users of the module
need to read no furter. 

=cut 

sub _add_required_or_optional {
	my ($profile,$name,$optional) = @_;
	if ($optional) {
		push @{ $profile->{optional} }, $name
	}
	else {
		push @{ $profile->{required} }, $name;
	}

}

sub _add_length_constraint {
	my ($profile,$name,$max_size) = @_;

	if ($max_size > 0)  {
		push @{ $profile->{constraints}->{$name} },
		{
			name => 'max_length',
			constraint => qr/^.{0,$max_size}$/, 
		};

		$profile->{msgs}->{constraints}->{'max_length'} = 
		'Exceeds maximum allowed field length';
	}
}


sub _add_db_constraint {
	my ($profile,$name,$constraint) = @_;

	# '((approval_state = \'needs_approval\'::"varchar") OR (approval_state = \'approved\'::"varchar"))'
	my $enum_list_re = qr/$name = \'(.*?)\'/;

	if ($constraint =~ $enum_list_re) {
		my @re_bits = ();
		while ($constraint =~ /$enum_list_re/g ) {
			push @re_bits, $1;
		};

		my $re = '^'.(join '|', @re_bits).'$';
		push @{ $profile->{constraints}->{$name} }, qr/$re/;
	}

}

=head2 _add_type_constraints()

   _add_type_constraints($dfv_profile,$name,$type_num,$type_name);

Modify C<$dfv_profile> by reference by adding constraints for the field
named C<$name> by analyzing its related C<$type_num> and C<$type_name>.

=cut

sub _add_type_constraints {
	my ($profile,$name,$type_num,$type_name) = @_;

    # TODO: Enhance these formats to use DateTime::Format::Pg and friends
    # For better DB-specific date formatting. 
	my %date_map = (
		date	                      => ['MM/DD/YYYY','Date'],
		timestamp                     => ['MM/DD/YYYY hh:mm:ss pp','Time'],
		'timestamp without time zone' => ['MM/DD/YYYY hh:mm:ss pp','Time'],
		time                          => ['hh:mm:ss pp','Time'],
		'time without time zone'      => ['hh:mm:ss pp','Time'],
	);

	my %num_map = (
            4	=> 'RE_num_int',
		    5   => 'RE_num_int',
            8	=> 'RE_num_int',
            2   => 'RE_num_real',
            7   => 'RE_num_real',
	);


	if ($date_map{$type_name}) {
		_add_date_and_time_constraint($profile, $name, @{ $date_map{$type_name}})
	}
	elsif ($num_map{$type_num}) {
        # I found bools in Pg 8.0 that had a type number of 4
        if ($type_name =~ /bool/i) {
            push @{ $profile->{constraints}->{$name} }, qr/^[10tf]$/i;
        }
        else {
            _add_number_constraint($profile,$name, $num_map{$type_num});
        }
    }
	else {
		# We don't know any constraints to add for this type.
		# That's OK.
	}




}

sub _add_date_and_time_constraint {
	my ($profile,$name,$format) = @_;
    # validator_packages will be converted from a hash to array later to prevent dupes.
	$profile->{validator_packages}->{'Data::FormValidator::Constraints::Dates'} = 1;
	push @{ $profile->{constraints}->{$name} },
		{
			constraint_method => 'date_and_time',
			params=>[\$format],

		};

	$profile->{msgs}->{constraints}->{'date_and_time'} = 
		"Invalid Date  Format";
}

sub _add_number_constraint {
	my ($profile,$name,$constraint) = @_;
	push @{ $profile->{constraints}->{$name} }, $constraint;

	$profile->{msgs}->{constraints}->{$constraint} ||= 'Invalid number format';
}

1;
__END__

=head1 NAME

Data::FormValidator::FromDBI - Generate FormValidator Profiles from DBI schemas

=head1 SYNOPSIS

  use Data::FormValidator::FromDBI;
  my $profile = generate_profile($dbh,$table);

  # For human inspection.
  use Data::Dumper;
  print Dumper $profile;

=head1 DESCRIPTION

 my $profile = generate_profile($DBH,$table);	

This routine takes a database handle and table name as input and
returns a Data::FormValidator profile based on the constraints found in the
database. 

This could be used directly to avoid writing a validation profile in Perl at
all. Or you could print out a copy of the result and modify it by hand to create
an even more powerful validation profile.

For the moment it has only been tested some with PostgreSQL 8.0, but better
support for other databases is desired. See the L<TODO> list below. 

Currently the following details are used to create the profile.

=over 4

=item required and optional

Fields defined as "not null" will be marked as required. Otherwise they will be
optional.

=item maximum length

For text fields, a constraint will be added to insure that the text does
not exceed the allowed length in the database

=item type checking

boolean, and numeric types will be checked that their input looks reasonable
for that type.

For date, time, and timestamp fields, a constraint will be generated to verify that the
input will be in a format that Postgres accepts.  

=item basic constraint parsing

One basic constraint is current recognized and transformed. If a field must
match one of a predetermined set of values, it will be tranformed into an
appropriate regular expression. In Postgres, this constraint may look like this:

 ((approval_state = \'needs_approval\'::"varchar") OR (approval_state = \'approved\'::"varchar"))

That will transformed into:

 approval_state => qr/^needs_approval|approved$/


=back

=head1 TODO

 - Better support for more databases and database versions
 - Allow users to override date format strings
 - Allow users to override constraint messages

=head2 EXPORT

generate_profile

=head1 SEE ALSO

L<Data::FormValidator>

=head1 CONTRIBUTING

Patches, questions and feedback are welcome. This project is maintained using
darcs ( http://www.darcs.net/ ). My darcs archive is here:
http://mark.stosberg.com/darcs_hive/dfv-fromdbi/

=head1 AUTHOR

Mark Stosberg, E<lt>mark@summersault.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Mark Stosberg

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
