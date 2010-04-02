package ParallelExec::Worker;

use strict;
use warnings;
use ParallelExec::Common;
use Time::HiRes qw(time);

use constant {
	red	=> "[1;31m",
	green	=> "[1;32m",
	blue	=> "[1;34m",
};

sub printc
{
	my $color = shift;
	print "\033$color@_\033[0;0m\n";
}

my $childpid = undef;
sub end
{
	if ( defined $childpid ) {
		kill shift, $childpid
			and return;
	}
	exit 0;
}

my $initialized = 0;
sub start
{
	my $ret = ParallelExec::Common::msg(
		ParallelExec::Common::type_worker(),
		new => $$
	);
	die "pexec: Cannot start worker - no response from server\n"
		unless $ret and defined $ret->{worker};
	
	$initialized = 1;

	$0 = "pexec-worker $ret->{worker}";
	printc green, "Started worker $ret->{worker}";

	foreach my $signame ( qw(INT KILL) ) {
		$SIG{$signame} = \&end;
	}

	my %opts;
	for (;;) {
		$opts{pid} = $$;
		ParallelExec::Common::snd(
			ParallelExec::Common::type_job(),
			%opts
		);
		my $ret = ParallelExec::Common::rcv();
		die "pexec: no response from server\n"
			unless $ret;

		#exit $ret->{exit} if exists $ret->{exit};
		unless ( exists $ret->{exec} ) {
			warn "pexec: nothing to do\n";
			next;
		}

		print "\n";
		$childpid = fork();
		if ( $childpid ) {
			my $start = time;
			my @start = times;
			waitpid $childpid, 0;
			$childpid = undef;
			my $stop = time;
			my @stop = times;
			$opts{ret} = $?;
			printc $? ? red : green,
				sprintf "[%.2fs real; %.2fs user; %.2fs system]> %d %2x",
				$stop - $start,
				$stop[2] - $start[2],
				$stop[3] - $start[3],
				$? >> 8, $? & 0xff;
		} else {
			exec_command( $ret );
		}
	}
}

sub exec_command
{
	my $ret = shift;
	my $exec = $ret->{exec};
	my $pwd = $ret->{pwd};
	my $env = $ret->{env};
	chdir $pwd
		or die "pexec: Cannot change directory: $!\n";
	printc blue, "[$pwd]\$\033[0;37m @$exec";
	delete @ENV{ keys %ENV };
	@ENV{ keys %$env } = values %$env;
	exec { $exec->[0] } @$exec;
	die "pexec: Execution failed: $!\n";
}

END {
	if ( $initialized ) {
		my $ret = ParallelExec::Common::msg(
			ParallelExec::Common::type_worker(),
			died => $$
		);
	}
}

1;
