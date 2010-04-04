package ParallelExec::Server;

use strict;
use warnings;
use ParallelExec::Common;

use IPC::SysV qw(S_IRUSR S_IWUSR IPC_CREAT IPC_NOWAIT);
use IPC::Msg ();
use Storable qw(freeze thaw);

my %cmds = (
	ParallelExec::Common::type_add()	=> \&srv_add,
	ParallelExec::Common::type_append()	=> \&srv_append,
	ParallelExec::Common::type_status()	=> \&srv_status,
	ParallelExec::Common::type_worker()	=> \&srv_worker,
	ParallelExec::Common::type_job()	=> \&srv_job,
);

my $try_start = 0;

sub end
{
	exit 0;
}

sub check_server
{
	my $ret = ParallelExec::Common::msg(
		ParallelExec::Common::type_status(),
	);
	die "pexec: Another server responded, not starting.\n" if $ret;
}

my $msg;
sub start
{
	check_server();

	$0 = "pexec-server";
	$msg = IPC::Msg->new( ParallelExec::Common::msgid(),
		IPC_CREAT | S_IRUSR | S_IWUSR );
	die "Cannot start message queue: $!\n" unless $msg;
	$msg->set( qbytes => 32 * ParallelExec::Common::msgsize() );

	foreach my $signame ( qw(INT KILL) ) {
		$SIG{$signame} = \&end;
	}

	{
		my $data;
		my $type;
		do {
			$type = $msg->rcv(
				$data,
				ParallelExec::Common::msgsize(),
				0,
				IPC_NOWAIT
			);
		} while ( defined $type );

	}

	for (;;) {
		my $data_in;
		my $type = $msg->rcv(
			$data_in,
			ParallelExec::Common::msgsize(),
			-ParallelExec::Common::msgmaintype(),
			0
		);
		next unless $data_in;
		my $func = $cmds{ $type };
		unless ( $func ) {
			warn "pexecserver: Wrong type $type\n";
			next;
		}
		my $data_in_obj = thaw $data_in;
		my $data_out_obj = &$func( $data_in_obj );
		respond( $data_in_obj->{rettype}, $data_out_obj )
			if defined $data_out_obj;

		try_start_new_job() if $try_start;
	}
}

sub respond
{
	my $rettype = shift;
	my $data_out_obj = shift;
	my $data_out = freeze $data_out_obj;
	$msg->snd( $rettype, $data_out, 0 );
}

END {
	if ( $msg ) {
		print "Removing message queue\n";
		$msg->remove();
	}
}

my %workers;
my @queue;
my %last_by_pid;

my %stat_by_pid;

sub srv_add
{
	return {} unless keys %workers;
	my $in = shift; # {exec} {env} {pwd} {ppid}
	my $pid = $in->{ppid};
	$last_by_pid{ $pid } = $in;
	$stat_by_pid{ $pid } ||= {
		failed => 0, failedall => 0,
		jobs => 0, jobsall => 0,
		done => 0, doneall => 0,
	};
	push @queue, $in;
	$stat_by_pid{ $pid }->{jobs}++;
	$stat_by_pid{ $pid }->{jobsall}++;
	$try_start = 1;
	return { added => 1 }; # {added}
}

sub srv_append
{
	return {} unless keys %workers;
	my $in = shift; # {exec} {env} {pwd} {ppid}
	my $pid = $in->{ppid};

	return srv_add( $in )
		unless $last_by_pid{ $pid };

	$in->{depends} = $last_by_pid{ $pid };
	$last_by_pid{ $pid } = $in;
	push @queue, $in;
	$stat_by_pid{ $pid }->{jobs}++;
	$stat_by_pid{ $pid }->{jobsall}++;
	$try_start = 1;
	return { added => 1 }; # {added}

}

sub srv_status
{
	my $in = shift; # {ppid} ({full}) ({reset})
	my $stat = $stat_by_pid{ $in->{ppid} };
	if ( $in->{reset} ) {
		$stat->{jobs} = 0;
		$stat->{failed} = 0;
		$stat->{done} = 0;
	}
	return $stat || {}; # unless $in->{full};

	my @all = qw(jobsall failedall doneall);
	my %stat;
	@stat{ @all } = (0, 0, 0);
	foreach my $s ( values %stat_by_pid ) {
		foreach my $all ( @all ) {
			$stat{ $all } += $s->{ $all };
		}
	}
	return \%stat;
}

sub srv_worker
{
	my $in = shift; # {new} / {died}
	my $pid;
	if ( $pid = $in->{new} ) {
		my @i = sort { $a <=> $b }
			map { $workers{ $_ }->{worker} }
			keys %workers;
		my $try = 0;
		foreach my $i ( @i ) {
			if ( $i == $try ) {
				$try++;
			} else {
				last;
			}
		}
		$workers{ $pid } = { worker => $try };
		return $workers{ $pid };
	} elsif ( $pid = $in->{died} ) {
		delete $workers{ $pid };
		return {};
	} else {
		return undef;
	}
}

sub srv_job
{
	my $in = shift; # {pid} ({ret}) {rettype}
	my $pid = $in->{pid};
	my $worker = $workers{ $pid };


	if ( defined $worker->{job} ) {
		$worker->{job}->{ret} = $in->{ret};
		my $stat = $stat_by_pid{ $worker->{job}->{ppid} };
		$stat->{done}++;
		$stat->{doneall}++;
		if ( $in->{ret} ) {
			$stat->{failed}++;
			$stat->{failedall}++;
		}
	}

	if ( my $job = nextjob() ) {
		$worker->{job} = $job;
		return $job; # ({exec}) ({env}) ({pwd})
	} else {
		delete $worker->{job};
		$worker->{rettype} = $in->{rettype};
		return undef;
	}
}

sub nextjob
{
	return undef unless @queue;

	my $end = scalar @queue;
	for ( my $i = 0; $i < $end; $i++ ) {
		my $job = $queue[ $i ];
		if ( not $job->{depends} or defined $job->{depends}->{ret} ) {
			splice @queue, $i, 1;
			return $job;
		}
	}
	return undef;
}

sub try_start_new_job
{
	$try_start = 0;

	return undef unless @queue;

	my @freeworkers = grep { not exists $_->{job} } values %workers;
	return unless @freeworkers;
	my $worker = (sort { $a->{worker} <=> $b->{worker} } @freeworkers)[0];

	if ( my $job = nextjob() ) {
		$worker->{job} = $job;
		respond( $worker->{rettype}, $job );
	}
}

1;
