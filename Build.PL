shift(@ARGV) if $ARGV[0] eq 'Build'; # accomodate with CPAN autoinstall
use Module::Build;

Module::Build->new(
   module_name => 'Data::FormValidator::FromDBI',
	license => 'perl',
   create_makefile_pl   => 'traditional',
	requires => {
		'Params::Validate'		   => 0,
		'DBD::Pg'					   => 1.32,
		DBI						   => 1.30,
	},
)->create_build_script;

