#!/usr/bin/env perl

use Test::More;

unless (eval { require DBD::SQLite }) {
  plan(skip_all => 'No SQLite driver');
  exit 0;
}

### Test RDB class using in-core scratch db
package My::Test::RDB;

use parent 'Rose::DB';

__PACKAGE__->use_private_registry;

__PACKAGE__->register_db(
			 domain => 'test',
			 type   => 'vapor',
			 driver => 'SQLite',
			 database => ':memory:',
			);

# SQLite in-memory db evaporates when original dbh is closed.
{
  my $dbh;
  sub dbi_connect {
    my($self,@args) = @_;
    $dbh = $self->SUPER::dbi_connect(@args) unless $dbh;
    $dbh;
  }
}


package My::Test::Logger;

sub new { my $str = ''; return bless \$str, shift; }

sub info { my($self,$msg) = @_; $$self .= $msg; }

sub warn { my($self,$msg) = @_; $$self .= $msg; }

sub message { my $self = shift; $$self; }

### And then, the rest of the tests
package main;

require Rose::DBx::CannedQuery::Glycosylated;

# Set up the test environment
my $rdb = new_ok('My::Test::RDB' => [ connect_options =>
				      { RaiseError => 1 },
				      domain => 'test',
				      type => 'vapor' ],
		 'Setup test db');
my $dbh = $rdb->dbh;
$dbh->do('CREATE TABLE test ( id INTEGER PRIMARY KEY,
                              name VARCHAR(16),
                              color VARCHAR(8) );');
foreach my $data ( [ 1, q{'widget'}, q{'blue'}  ],
		   [ 2, q{'fidget'}, q{'red'}   ],
		   [ 3, q{'midget'}, q{'green'} ],
		   [ 4, q{'gidget'}, q{'red'}   ] ) {
  $dbh->do(q[INSERT INTO test VALUES ( ] .
	   join(',', @$data) . ' );');
}


# . . . and start the testing
my $sweet;

SKIP : {

  skip 'Need Log::Any::Adapter::Carp for default logger', 3
    unless eval { require Log::Any::Adapter::Carp; };
  my $warning = '';
  $sweet = new_ok('Rose::DBx::CannedQuery::Glycosylated' =>
		     [ rdb_class => 'My::Test::RDB',
		       rdb_params => { domain => 'test',
				       type => 'vapor'},
		       sql => 'SELECT * FROM test WHERE color = ?',
		       verbose => 3, name => 'testme' ],
		     'Create object with verbosity level 3');

  my $warning = '';
  $SIG{__WARN__} = sub { $warning .= shift; };

  $sweet->do_many_queries({ first => [ 'red' ],
			    second => ['green' ],
			  });
  like($warning,
       qr/\s*[A-Za-z0-9 :\-]+::\Q Executing bind set first for query testme\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing testme with bind values:\E
	  \s*[A-Za-z0-9 :\-]+::\s+red
	  \s*[A-Za-z0-9 :\-]+::\Q with query modifiers:\E
	  \s*[A-Za-z0-9 :\-]+::\s+\Q{}\E
	  \s*[A-Za-z0-9 :\-]+::\Q Got 2 results\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing bind set second for query testme\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing testme with bind values:\E
	  \s*[A-Za-z0-9 :\-]+::\s+green
	  \s*[A-Za-z0-9 :\-]+::\Q with query modifiers:\E
	  \s*[A-Za-z0-9 :\-]+::\s+\Q{}\E
	  \s*[A-Za-z0-9 :\-]+::\Q Got 1 results\E
	 /sx,
       'multiple named query trace message (default output)');

  $warning = '';

  $sweet->do_many_queries([ [ [ 'red' ], [ [] ] ], [ ['green' ], 1 ] ]);

  like($warning,
       qr/\s*[A-Za-z0-9 :\-]+::\Q Executing bind set Element0000 for query testme\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing testme with bind values:\E
	  \s*[A-Za-z0-9 :\-]+::\s+red
	  \s*[A-Za-z0-9 :\-]+::\Q with query modifiers:\E
	  \s*\s*[A-Za-z0-9 :\-]+::\s+\Q[]\E
	    \s*[A-Za-z0-9 :\-]+::\Q Got 2 results\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing bind set Element0001 for query testme\E
	  \s*[A-Za-z0-9 :\-]+::\Q Executing testme with bind values:\E
	  \s*\s*[A-Za-z0-9 :\-]+::\s+green
	  \s*[A-Za-z0-9 :\-]+::\Q with query modifiers:\E
	  \s*[A-Za-z0-9 :\-]+::\s+\Q{}, 1\E
	  \s*[A-Za-z0-9 :\-]+::\Q Got 1 results\E
	 /sx,
       'multiple anonymous query trace message (default output)');

}
  
$sweet = new_ok('Rose::DBx::CannedQuery::Glycosylated' =>
		[ rdb_class => 'My::Test::RDB',
		  rdb_params => { domain => 'test',
				  type => 'vapor'},
		  sql => 'SELECT * FROM test WHERE color = "blue"',
		  verbose => 3, name => 'custom_log_test',
		  logger => My::Test::Logger->new ],
		'Create object with custom logger');

$sweet->do_one_query();

is($sweet->logger->message,
   "Executing custom_log_test with query modifiers:\n\t{}Got 1 results",
   'Log message to custom logger');

done_testing;
