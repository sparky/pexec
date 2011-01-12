package ParallelExec::Adder;

use strict;
use warnings;
use ParallelExec::Common;
use Cwd qw(fastcwd abs_path);

my $type;
sub add_cmd
{
	my %o;
	while ( $_[0] =~ /^-([a-zA-Z])(.+)/ ) {
		$o{ $1 } = $2;
		shift @_;
	}
	die "pexec: command missing\n"
		unless scalar @_;
	die "pexec: $_[0]: command not found\n"
		unless require_prog( $_[0] );

	my %opts;
	if ( exists $o{n} ) {
		$opts{nice} = $o{n};
	}
	if ( exists $o{i} ) {
		$opts{ionice} = $o{i};
	}
	if ( exists $o{p} ) {
		$opts{prio} = $o{p};
	}
	my $ret = ParallelExec::Common::msg(
		$type,
		exec => \@_,
		pwd => fastcwd(),
		env => \%ENV,
		%opts
	);
	if ( $ret and $ret->{added} ) {
		#warn "pexec: Added job to server.\n";
		exit 0;
	}
	warn "pexec: Couldn't send command to server, running locally.\n";
	exec @_;
	die "pexec: Couldn't execute command locally.\n";
}

sub add
{
	$type = ParallelExec::Common::type_add();
	return &add_cmd;
}

sub append
{
	$type = ParallelExec::Common::type_append();
	return &add_cmd;
}

sub require_prog
{
	my $prog = shift;
	if ( $prog =~ m#/# and -x $prog ) {
		return abs_path( $prog );
	}
	foreach my $dir ( split /:+/, $ENV{PATH} ) {
		my $full = "$dir/$prog";
		return $full if -x $full;
	}
	return undef;
}

1;
