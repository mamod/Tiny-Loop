use 5.010001;
use ExtUtils::MakeMaker;
#ignore
WriteMakefile(
		NAME              => 'Tiny::Loop',
		VERSION_FROM      => 'lib/Tiny/Loop.pm',
		PREREQ_PM         => {},
		($] >= 5.005 ?
			(ABSTRACT_FROM  => 'lib/Tiny/Loop.pm', # retrieve abstract from module
			 AUTHOR         => 'Mamod A. Mehyar <mamod.mehyar@gmail.com>') : ()),
);
