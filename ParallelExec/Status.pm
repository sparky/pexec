package ParallelExec::Status;

use strict;
use warnings;
use ParallelExec::Common;

sub getstatus
{
	my $ret = ParallelExec::Common::msg(
		ParallelExec::Common::type_status(),
		@_,
	);
	die "pexec: No response from server.\n" unless $ret;
	return $ret;
}

sub wait
{
	my $pidjobs = 0;
	my $retcode = 0;

	for (;; sleep 1 ) {
		my $ret = getstatus();
		die "No statistics\n" unless exists $ret->{failed};
		$retcode = $ret->{failed} if defined $ret->{failed};
		my $left = $ret->{jobs} - $ret->{done};
		last unless $left > 0;
		if ( $left != $pidjobs ) {
			$pidjobs = $left;
			warn "pexec: $left left, waiting\n";
		}
	}

	{
		my $ret = getstatus( reset => 1 );
		$retcode = 200 if $retcode > 200;
		return $retcode;
	}
}

sub status
{
	my $ret = getstatus( full => 1 );
	die "pexec: No response from server.\n" unless $ret;
	print "pexec: Status:\n";
	foreach my $k ( sort keys %$ret ) {
		print "\t$k\t=> $ret->{$k}\n";
	}
}

sub help
{
	print <<'EOF';
pexec - run multiple commands from your shell
run:
	pexec <command> [arguments]

commands:
	help	- show this help message
	server	- run pexec server
	worker	- start one worker (you probably want 2 or more)
	add	- add command to server
	append	- run command after finishing last one
	wait	- wait until all commands started by this shell are executed
	status	- print server status

typical usage:
  pexec server &
  for N in $(seq $(getconf _NPROCESSORS_ONLN)); do \
    ( xterm -e pexec worker & ); \
  done

  alias p="pexec add"
  alias +="pexec append"

  p mencoder -oac copy -ovc copy -o f2.avi f1.avi
  for J in *.jpg; do \
    p convert -scale 1024x1024 -quality 75 "$J" "_$J"; \
    + mv "_$J" "$J"; \
  done
  pexec wait && echo "All done" || echo "Something failed"
EOF

}

1;
