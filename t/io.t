use lib './lib';
use Tiny::Loop;
use strict;
use warnings;
use Test::More;
use Time::HiRes qw(time);
use Socket;



my $loop = Tiny::Loop->new();
my $total_expected = 0;


{
	my $expected = 0;
	socketpair(my $rdr, my $wtr, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
	my $msg = '';
	my $t2; $t2 = $loop->io( fileno $rdr, 2, sub {

		my $fd    = shift;
		my $event = shift;


		is($event, 2); ## POLLIN event
		is($fd, fileno $rdr, "fileno " . fileno $rdr);

		my $ret = $rdr->sysread($msg, 200);
		is($ret, 3);
		is(substr($msg, 0, $ret), "hi\n");

		++$expected;

		## creating io listner for the same fd
		$loop->io( fileno $rdr, 2, sub {
			my $ret = $rdr->sysread($msg, 200);
			is($ret, 6);
			is(substr($msg, 0, $ret), "hello\n");
			is($expected, 1);
			$total_expected += --$expected;
			close $rdr;
			close $wtr;
		});

		## write again, the new listner should catch it
		$wtr->syswrite("hello\n", 6);
	});

	$wtr->syswrite("hi\n", 3);
}



{ ## timer inside io callback
	my $expected = 0;
	socketpair(my $rdr, my $wtr, AF_UNIX, SOCK_STREAM, PF_UNSPEC);
	my $msg = '';
	my $t2; $t2 = $loop->io( fileno $rdr, 2, sub {

		my $fd    = shift;
		my $event = shift;

		is($event, 2); ## POLLIN event
		is($fd, fileno $rdr, "fileno " . fileno $rdr);

		my $ret = $rdr->sysread($msg, 200);
		is($ret, 5);
		is(substr($msg, 0, $ret), "hixx\n");

		++$expected;

		## creating io listner for the same fd
		$loop->timer(1000, 0, sub {
			is($expected, 1);
			close $rdr;
			close $wtr;
		});
	});

	$wtr->syswrite("hixx\n", 5);
}

$loop->start();
done_testing(12);
