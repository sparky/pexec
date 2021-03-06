package ParallelExec::Common;

use strict;
use warnings;
use IPC::SysV qw(S_IRUSR S_IWUSR IPC_NOWAIT);
use IPC::Msg ();
use Storable qw(freeze thaw);

use constant {
	msgsize		=> (1 << 13),
	msgid		=> (1624998952 + $>),
	msgrettype	=> ((1 << 16) + $$),
	msgmaintype	=> (1 << 16),
};

use constant {
	type_add	=> msgmaintype - 101,
	type_append	=> msgmaintype - 102,
	type_status	=> msgmaintype - 103,
	type_worker	=> msgmaintype - 201,
	type_job	=> msgmaintype - 202,
};

sub obj2data
{
	my $obj = shift;
	my $data = freeze( $obj );
	if ( length $data > msgsize ) {
		require Compress::Zlib;
		$data = Compress::Zlib::compress( $data, 9 );
		if ( length $data > msgsize ) {
			warn "snd: compressed \$data to big, aborting\n";
			return undef;
		}
	}
	return $data;
}

sub data2obj
{
	my $data = shift;
	return undef unless defined $data;
	if ( "x" eq substr $data, 0, 1 ) {
		# compressed
		require Compress::Zlib;
		$data = Compress::Zlib::uncompress( $data );
	}
	return thaw( $data );
}

our $ppid = getppid;

my $msg;
sub snd
{
	my $type = shift;
	my %opts = @_;

	unless ( $msg ) {
		$msg = IPC::Msg->new( msgid, S_IRUSR | S_IWUSR )
			or return undef;
	}

	$opts{rettype} = msgrettype;
	$opts{ppid} = $ppid;

	my $data = obj2data \%opts;
	return undef unless $data;

	$msg->snd( $type, $data, IPC_NOWAIT )
		or return undef;

	return $msg;
}

sub rcv
{
	die "No msg\n"
		unless $msg;

	my $buf;
	my $rettype = $msg->rcv( $buf, msgsize, msgrettype, 0 );
	return data2obj $buf;
}

sub msg
{
	&snd
		or return undef;
	my $rcv;
	eval {
		local $SIG{ALRM} = sub { $rcv = undef; die "Alarm\n"; };
		alarm 1;
		$rcv = rcv();
		alarm 0;
	};
	warn "$@" if $@;
	return $rcv;
}

1;

__END__
sub getopts
{
	return map {
		/^-{0,2}(\S+?)(=(.*))?$/;
		defined $2 ? ($1, $3) : ($1, undef);
	} @_;
}

1;
