use Test::More; 
use Test::Deep;
use strict;
use vars qw($dsn $user $password);

if (defined $ENV{DBI_DSN}) {
  plan tests => 22;
} else {
  plan skip_all => 'cannot test without DB info set in $ENV{DBI_DSN}. See README for details.';
}   

BEGIN { use_ok('Data::FormValidator::FromDBI') }


use DBI;
my $DBH =  DBI->connect($ENV{DBI_DSN}, $ENV{DBI_USER}, $ENV{DBI_PASS});
ok($DBH,'connecting to database'), 

# create test table
my $drv = $DBH->{Driver}->{Name};

ok(open(IN, "<t/create_test_table.".$drv.".sql"), 'opening SQL create file');
my $sql = join "", (<IN>);
my $created_test_table = $DBH->do($sql);
ok($created_test_table, 'creating test table');

my $profile;
eval {
	$profile = generate_profile($DBH,'db2dfv_test');
};
is($@,'', "eval'ing code execution");

cmp_deeply( $profile->{required}, supersetof('int4_not_null'),'not null eq required');

ok ((grep {/int8_col/} @{ $profile->{optional} } ) ,'optional');


my $con = $profile->{constraints};
is($con->{varchar_col}->[0]->{name},'max_length' ,'field length constraint');

like($con->{bool_col}->[0], qr/tf/,'bool type checking');

is($con->{primary_id}->[0],'RE_num_int' ,'int2 type check');
is($con->{int4_not_null}->[0],'RE_num_int' ,'int4 type check');

is($con->{int8_col}->[0] , 'RE_num_int' ,'int8 type check');

is($con->{float4_col}->[0], 'RE_num_real' ,'float4 type check');
is($con->{float8_col}->[0], 'RE_num_real' ,'float8 type check');

is($con->{date_col}->[0]->{constraint_method}, 'date_and_time' ,'date type check for date_col');
is($con->{time_col}->[0]->{constraint_method}, 'date_and_time' ,'time type check for time_col');
is($con->{timestamp_col}->[0]->{constraint_method}, 'date_and_time' ,'timestamp type check for timestamp_col');

TODO: {
    local $TODO = 'not ready yet. Perhaps I just need to upgrade DBD::Pg.';
    like($con->{pick_one}->[1],qr/duck\|goose\|caboose/, 'db constraint parsing test for pick_one col');
}

# but is it really valid?
BEGIN { use_ok('Data::FormValidator') } 
my $dfv;
eval {
	$dfv = Data::FormValidator->new({default => $profile});
};
is($@,'', 'basic syntax reality check');

my %good_data = (
	primary_id    => 1,
	int4_not_null => 4,
	int8_col	  => 16,
	float4_col	  => 2.3,
	float8_col	  => '-6.7',
	text_col      => 'text',		
	varchar_col	  => 'hi',
	char_col	  => 'abc',
	bool_col	  => 1,
	date_col	  => '12/03/2003',
	time_col	  => '12:23:02 PM',
	pick_one	  => 'duck',
);

my $results;
eval {
	$results = $dfv->check(\%good_data,$profile);
};
is($@,'', "eval'ling validate() call");
my $valid = $results->valid;

is_deeply($valid,\%good_data,'comparing expected good data to validation results');

my %bad_data = (
	primary_id    => 'bad',
	int4_not_null => 'worse',
	int8_col	  => 'superbad',
	float4_col	  => 'ouch',
	float8_col	  => 'doh!',
	varchar_col	  => 'way too long',
	char_col	  => 'still too long',
	bool_col	  => 'wrong',
	date_col	  => 'not a date',
	time_col	  => 'or a time',
	pick_one	  => 'wrong choice',
);

{
    my $results;
    eval { $results = $dfv->check(\%bad_data,$profile); };
    is($@,'', "eval'ling validate() call");
    my $valid = $results->valid;

    is_deeply([sort  $results->invalid ],[ sort keys %bad_data ],'comparing expected bad data to invalid list');
}

# We use an end block to clean up even if the script dies.
 END {
 	if ($DBH) {
 		if ($created_test_table) {
 			$DBH->do("DROP TABLE db2dfv_test");
 		}
 		$DBH->disconnect;
 	}
 };

