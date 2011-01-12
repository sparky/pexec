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
my $lastsigtime = 0;
my $lastsig = "";
sub end
{
	my $sig = shift;
	if ( defined $childpid ) {
		kill $sig, $childpid
			and return;
	} else {
		my $time = time;
		if ( $lastsig eq $sig and $lastsigtime >= $time - 5 ) {
			warn "Signal $sig received.\n";
			exit 0;
		} else {
			warn "Send signal $sig within 5 seconds to terminate worker.\n";
			$lastsig = $sig;
			$lastsigtime = $time;
			return;
		}
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

	foreach my $signame ( qw(TERM INT STOP HUP KILL) ) {
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
		unless ( $ret ) {
			die "pexec: no response from server\n"
				unless $lastsigtime >= time() - 1;
			next;
		}

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
	system "renice", $ret->{nice}, $$ if $ret->{nice};
	system "ionice", "-n", $ret->{ionice}, "-p", $$ if $ret->{ionice};
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
