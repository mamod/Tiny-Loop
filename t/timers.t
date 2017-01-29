use lib './lib';
use Tiny::Loop;
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);

my $WINDOW = 200;
my $interval_count = 0;

sub Date {
	return int(time() * 1000);
}

my $loop = Tiny::Loop->new();

my $starttime = Date();

$loop->timer( 1000, 0, sub {

	my $endtime = Date();
	my $diff = $endtime - $starttime;
	ok($diff > 0);

	diag('diff: ' . $diff);

	ok( (1000 - $WINDOW < $diff) && ($diff < 1000 + $WINDOW) );
});



# shouldn't execute
my $id = $loop->timer( 1, 0, sub { fail("shouldn't execute") });
$loop->timer_stop($id);



my $t1; $t1 = $loop->timer( 1000, 1000, sub {
	$interval_count += 1;
	my $endtime = Date();

	my $diff = $endtime - $starttime;

	ok($diff > 0);

	diag('diff: ' . $diff);

	my $t = $interval_count * 1000;

	ok($t - $WINDOW < $diff && $diff < $t + $WINDOW);

	ok($interval_count <= 3);

	if ($interval_count == 3) {
		$loop->timer_stop($t1);
	}
});


$loop->timer( 1000, 0, sub {
	my $param = shift;
	is('test param', $param);
}, 'test param');


my $interval_count2 = 0;
my $t2; $t2 = $loop->timer( 1000, 1000, sub {
	my $param = shift;
	++$interval_count2;
	is('test param', $param);

	$loop->timer_stop($t2) if ($interval_count2 == 3);
}, 'test param');


## tiny::loop accepts only one param
## test passing an array
$loop->timer( 1000, 0, sub {
	my $param1 = $_[0][0];
	my $param2 = $_[0][1];

	is('param1', $param1);
	is('param2', $param2);
}, ['param1', 'param2']);


my $interval_count3 = 0;
my $t3; $t3 = $loop->timer( 1000, 1000, sub {
	my $param1 = $_[0][0];
	my $param2 = $_[0][1];
	++$interval_count3;
	is('param1', $param1);
	is('param2', $param2);

	if ($interval_count3 == 3) {
		$loop->timer_stop($t3);
	}
}, ['param1', 'param2']);


# repeated timers should be called multiple times.
my $count4 = 0;
my $interval4; $interval4 = $loop->timer( 1, 1, sub {
	$loop->timer_stop($interval4) if (++$count4 > 10);
});


# we should be able to clearTimeout multiple times without breakage.
my $expectedTimeouts = 3;

sub tm {
  $expectedTimeouts--;
}

$loop->timer(200, 0, \&tm);
$loop->timer(200, 0, \&tm);
my $y = $loop->timer(200, 0, \&tm);

$loop->timer_stop($y);
$loop->timer(200, 0, \&tm);
$loop->timer_stop($y);

$loop->start();


is(3, $interval_count);
is(11, $count4);
is(0, $expectedTimeouts, 'clearTimeout cleared too many timeouts');

done_testing();
