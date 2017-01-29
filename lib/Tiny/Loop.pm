package Tiny::Loop;
use strict;
use warnings;
use Time::HiRes qw(time usleep);
use Data::Dumper;
use Scalar::Util qw(weaken);

our $VERSION = 0.0.1;

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	tie @{ $self->{timers} }, "Tiny::Loop::Array", sub { $_[0]->[0] <=> $_[1]->[0] };

	$self->{ backend }  =  Tiny::Loop::Select->new();
	$self->update_time();
	return $self;
}


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


sub start {
	my $self = shift;
	my $total_elapsed = 0;
	while (1){

		{	# update timer
			$self->update_time();
		}

		my $now         = $self->now;
		my $timers_list = $self->{timers};

		TIMER_AGAIN: for (@{ $timers_list }) {
			my $timer = $timers_list->[0];

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
			## not ready yet exit this loop and try again
			## later
			last;
		}

		if (!scalar @{ $timers_list } ){ last; }
		my $wait = ($self->{timers}->[0]->[0] - $now) / 1000;
		select(undef, undef, undef, $wait);
	}
}


package Tiny::Loop::Timer; {
	sub new {}
};


package Tiny::Loop::Select; {
	sub new {}
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
