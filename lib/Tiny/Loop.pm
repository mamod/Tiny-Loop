package Tiny::Loop;
use strict;
use warnings;
use Time::HiRes qw(time usleep);
use Data::Dumper;
use Scalar::Util qw(weaken);

our $VERSION = 0.0.1;

our $POLLIN  = 2;
our $POLLOUT = 4;
our $POLLERR = 8;

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	tie @{ $self->{timers} }, "Tiny::Loop::Array", sub { $_[0]->[0] <=> $_[1]->[0] };
	$self->{ io }  =  Tiny::Loop::Select->new( $self );

	$self->update_time();
	return $self;
}

#hiiii

sub now { shift->{time} }
sub update_time {
	shift->{time} = int( time() * 1000 );
}


sub timer {
	my $self    = shift;
	my $timeout = shift;
	my $repeat  = shift;
	my $cb      = shift;

	my $timer = [$self->now + $timeout, $repeat, $cb, @_];
	push @{$self->{timers}}, $timer;
	return $timer;
}


sub timer_again {
	my $self = shift;
	my $timer = shift;
	my $timeout = $timer->[1];
	$timer->[0] = $self->now + $timeout;
	push @{$self->{timers}}, $timer;
}


sub timer_stop {
	my $self = shift;
	my $timer = shift;
	$timer->[0] = 0;
	$timer->[1] = 0;
	$timer->[2] = undef;
}


sub io {
	my $self = shift;
	$self->{ io }->add(@_);
}


sub io_stop {
	my $self = shift;
	$self->{ io }->stop(@_);
}


sub start {
	my $self = shift;
	my $total_elapsed = 0;
	while (1){

		{	# update timer
			$self->update_time();
		}

		my $now         = $self->now;
		my $timers_list = $self->{timers};

		TIMER_AGAIN: if (my $timer = $timers_list->[0]) {

			if ( $timer->[0] <= $now ){

				shift @{ $timers_list };

				{	# callback
					my $cb     = $timer->[2];
					$cb->($timer->[3]) if $cb;
				}

				{	## repaet!
					my $repeat = $timer->[1];
					$self->timer_again($timer) if ( $repeat );
				}

				## timers still active
				goto TIMER_AGAIN;
			}

			## it's guranteed that the first timer
			## is the one should be fired, so if it's
			## not ready yet then next timers will not
			## be ready too, so go to the next polling
			## state io_poll
		}

		my $wait = undef;
		if ($self->{timers}->[0]){
			$wait = ($self->{timers}->[0]->[0] - $now) / 1000;
			select(undef, undef, undef, $wait) if !$self->{ io }->{nfds};
		}

		$self->{io}->poll( $wait );
		last if (!scalar @{ $timers_list } ); ## loop break
	}
}





package Tiny::Loop::Select; {
	use strict;
	use warnings;
	use POSIX qw(:errno_h);
	use Data::Dumper;

	sub new {
		my $class = shift;
		my $loop  = shift;
		my $self  = bless { loop => $loop }, $class;

		$self->{nfds}     = 0;
		$self->{queue}    = [];
		$self->{watchers} = {};
		$self->{events}   = ['', '', ''];
		return $self
	}


	sub add {
		my $self  = shift;
		my $fd    = shift;
		my $ev    = shift;
		my $cb    = shift;

		my $io = [$fd, $ev, $cb];
		$self->{watchers}->{$fd} = $io;

		if ($ev & $POLLIN){
			vec($self->{events}->[0], $fd, 1) = 1;
		}

		if ($ev & $POLLOUT){
			vec($self->{events}->[1], $fd, 1) = 1;
		}

		if ($ev & $POLLERR){
			vec($self->{events}->[2], $fd, 1) = 1;
		}

		$self->{nfds}++;
		return $self->{watchers}->{$fd};
	}


	## TODO
	sub stop {
		my $self  = shift;
		my $io    = shift;
	}


	sub poll {

		my $self = shift;
		my $wait = shift;
		my $loop = $self->{ loop };

		my $watchers = $self->{watchers};

		my $rout = '';
		my $wout = '';
		my $eout = '';
		my $nfds = 0;

		my $base = $loop->{time};

		POLL_AGAIN: while ( $self->{nfds} ){

			$nfds = select(
				$rout = $self->{events}->[0],
				$wout = $self->{events}->[1],
				$eout = $self->{events}->[2],
				$wait
			);

			## update time on every watch tick
			$loop->update_time();

			## an error
			if ( $nfds == -1 ){
				## on windows we may get an WSEINVAL error if we have all
				## fd sets nulled this is an odd behaviour so we need to
				## overcome a loop saturation
				select(undef, undef, undef, 0.001) if $! == 10022;

				## other errors should never happen
				die $! if ( $! != EINTR );
			}

			## no events or error [ 0 || -1 ]
			goto MAYBE_POLL_AGAIN if ($nfds <= 0 );

			my $nevents = 0;
			for ( keys %{ $self->{watchers} } ) {

				my $w  = $self->{watchers}->{$_};

				my $fd = $w->[0];
				my $ev = $w->[1];
				my $cb = $w->[2];

				my $poll_event = 0;
				if ($ev & $POLLIN){
					$poll_event |= vec($rout, $fd, 1) ? $POLLIN : 0;
				}

				if ($ev & $POLLOUT){
					$poll_event |= vec($wout, $fd, 1) ? $POLLOUT : 0;
				}

				if ($ev & $POLLERR){
					$poll_event |= vec($eout, $fd, 1) ? $POLLERR : 0;
				}

				if ( $poll_event ){
					delete $self->{watchers}->{$_};
					$self->{nfds}--;

					eval {
						vec($self->{events}->[0], $fd, 1) = 0;
						vec($self->{events}->[1], $fd, 1) = 0;
						vec($self->{events}->[2], $fd, 1) = 0;
					};

					$cb->($fd, $poll_event);
					$nevents++;

					## io callback might call a timer function
					## so we need to check if a new timeout has
					## been updated
					if ($loop->{timers}->[0]){
						$wait = ($loop->{timers}->[0]->[0] - $base) / 1000;
					}
				}

				last if $nevents == $nfds;
			}

			MAYBE_POLL_AGAIN: {
				## there is no timers!! keep polling
				goto POLL_AGAIN if !defined $wait;

				## next timer time out should happen immediately
				## leave io polling for now and check back on next tick
				return if ($wait <= 0);

				## update wait timeout
				my $diff = ($self->{ loop }->{time} - $base) / 1000;
				return if ($diff >= $wait);
				$wait -= $diff;
			}
		}
	}
};





package Tiny::Loop::Array; {
	use strict;
	use warnings;
	use base 'Tie::Array';

	sub TIEARRAY {
		my ($class, $comparator) = @_;
		bless {
			array => [],
			comp  => (defined $comparator ? $comparator : sub { $_[0] cmp $_[1] })
		}, $class;
	}

	sub STORE {
		my ($self, $index, $elem) = @_;
		if (scalar @{ $self->{array} } < $index){
			$self->{array}->[$index] = 0;
			return;
		}

		splice @{ $self->{array} }, $index, 0;
		$self->PUSH($elem);
	}

	sub PUSH {
		my ($self, @elems) = @_;
		ELEM: for my $elem (@elems) {
			my ($lo, $hi) = (0, $#{ $self->{array} });
			while ($hi >= $lo) {
				my $mid     = int(($lo + $hi) / 2);
				my $mid_val = $self->{array}[$mid];
				my $cmp     = $self->{comp}($elem, $mid_val);
				if ($cmp == 0) {
					splice(@{ $self->{array} }, $mid, 0, $elem);
					next ELEM;
				} elsif ($cmp > 0) {
					$lo = $mid + 1;
				} elsif ($cmp < 0) {
					$hi = $mid - 1;
				}
			}
			splice(@{ $self->{array} }, $lo, 0, $elem);
		}
	}

	sub UNSHIFT   { goto &PUSH }
	sub FETCHSIZE { scalar @{ $_[0]->{array} } }
	sub STORESIZE { $#{ $_[0]->{array} } = $_[1] - 1 }
	sub FETCH     { $_[0]->{array}->[ $_[1] ] }
	sub CLEAR     { @{ $_[0]->{array} } = () }
	sub POP       { pop(@{ $_[0]->{array} }) }
	sub SHIFT     { shift(@{ $_[0]->{array} }) }

	sub EXISTS { exists $_[0]->{array}->[ $_[1] ] }
	sub DELETE { delete $_[0]->{array}->[ $_[1] ] }
}

1;

__END__

=head1 NAME

Tiny::Loop - Tiny event loop
