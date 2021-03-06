#!/usr/bin/env perl

use strict;

use DBI;
use File::Basename qw(basename);
use Getopt::Long;

my $program = basename($0);
my $opts = {
  # Default table parameters
  'ctx-tab' => 'ftpctx',
  'conf-tab' => 'ftpconf',
  'map-tab' => 'ftpmap',
};

GetOptions($opts, 'conf-tab=s', 'ctx-tab=s', 'dbdriver=s', 'dbname=s',
  'dbpass=s', 'dbserver=s', 'dbuser=s', 'help', 'map-tab=s', 'show-sql',
  'show-tags', 'verbose');

usage() if $opts->{help};

die "$program: missing --dbdriver option\n" unless defined($opts->{dbdriver});
if ($opts->{dbdriver} =~ /sqlite/i) {
  $opts->{dbdriver} = 'SQLite';

} elsif ($opts->{dbdriver} =~ /mysql/i) {
  $opts->{dbdriver} = 'mysql';

} elsif ($opts->{dbdriver} =~ /postgres/i) {
  $opts->{dbdriver} = 'Pg';
}

die "$program: missing --dbname option\n" unless defined($opts->{dbname});

# We need a database handle.
my ($dbname, $dbkey, $dsn);

# SQLite, unlike other databases, does not require server/user/pass options.
if ($opts->{dbdriver} =~ /sqlite/i) {
  $dbname = "$opts->{dbname}";
  $dbkey = 'dbname';
  $dsn = "DBI:$opts->{dbdriver}:$dbkey=$opts->{dbname}";

} else {
  die "$program: missing --dbpass option\n" unless defined($opts->{dbpass});
  die "$program: missing --dbserver option\n" unless defined($opts->{dbserver});
  die "$program: missing --dbuser option\n" unless defined($opts->{dbuser});

  $dbname = "$opts->{dbname}\@$opts->{dbserver}";

  # MySQL driver prefers 'database', Postgres likes 'dbname'
  $dbkey = ($opts->{dbdriver} =~ /mysql/i) ? 'database' : 'dbname';
  $dsn = "DBI:$opts->{dbdriver}:$dbkey=$opts->{dbname};host=$opts->{dbserver}";
}

my $dbi_opts = {
  RaiseError => 1,
  AutoCommit => 1,
};

my $dbh;
unless ($dbh = DBI->connect($dsn, $opts->{dbuser}, $opts->{dbpass},
    $dbi_opts)) {
  die "$program: unable to connect to $dbname: $DBI::errstr\n";
}

# Given a context ID, find all directives that map to this ID, then
# find all the contexts for which this context is the parent.  For each
# of those contexts, find all directives, etc....

my $conf = get_ctx();

show_conf($conf);

exit 0;

# ---------------------------------------------------------------------------
sub dbi_prep_stmt {
  my ($stmt) = @_;
  my $sth;

  unless ($sth = $dbh->prepare($stmt)) {
    warn "$program: unable to prepare '$stmt': $DBI::errstr\n";
    return;
  }

  return $sth;
}

sub dbi_exec_stmt {
  my ($sth) = @_;

  if ($opts->{'show-sql'}) {
    print "$program: executing: $sth->{Statement}\n";
  }

  unless ($sth->execute()) {
    warn "$program: error executing '$sth->{Statement}', $DBI::errstr\n";
    return;
  }

  return 1;
}

sub dbi_free_stmt {
  my ($sth) = @_;
  $sth->finish();
}

sub get_ctx {
  my ($id) = @_;
  my $ctx;

  # If no context ID is given, look up the default/"server config" context.
  # It will be the one that has no parent (i.e. parent_id is NULL).

  my $ctx_tab = $opts->{'ctx-tab'};

  unless ($id) {
    my $stmt = "SELECT id FROM $ctx_tab WHERE parent_id IS NULL";
    my $sth = dbi_prep_stmt($stmt);
    dbi_exec_stmt($sth);
    $id = ($sth->fetchrow_array())[0];
    dbi_free_stmt($sth);
  }

  my $stmt = "SELECT type, value FROM $ctx_tab WHERE id = ?";
  my $sth = dbi_prep_stmt($stmt);
  $sth->bind_param(1, $id);
  dbi_exec_stmt($sth);

  $ctx->{id} = $id;
  ($ctx->{type}, $ctx->{value}) = ($sth->fetchrow_array())[0, 1];
  dbi_free_stmt($sth);

  $ctx->{directives} = get_ctx_directives($id);

  my $ctxs = get_ctx_ctxs($id);

  foreach $id (@$ctxs) {
    push(@{ $ctx->{contexts} }, get_ctx($id));
  }

  return $ctx;
}

sub get_ctx_ctxs {
  my ($ctx_id) = @_;

  my $ctx_tab = $opts->{'ctx-tab'};

  my $stmt = "SELECT id FROM $ctx_tab WHERE parent_id = ?";
  my $sth = dbi_prep_stmt($stmt);
  $sth->bind_param(1, $ctx_id);
  dbi_exec_stmt($sth);

  my $ctxs;
  while (my @row = $sth->fetchrow_array()) {
    my ($id) = @row;
    push(@$ctxs, $id);
  }

  dbi_free_stmt($sth);
  return $ctxs;
}

sub get_ctx_directives {
  my ($ctx_id) = @_;

  my $dir_tab = $opts->{'conf-tab'};
  my $map_tab = $opts->{'map-tab'};

  my $stmt = "SELECT id, name, value FROM $dir_tab INNER JOIN $map_tab " .
             " ON $dir_tab.id = $map_tab.conf_id" .
             " WHERE $map_tab.ctx_id = ?";
  my $sth = dbi_prep_stmt($stmt);
  $sth->bind_param(1, $ctx_id);
  dbi_exec_stmt($sth);

  my $directives;
  while (my @row = $sth->fetchrow_array()) {
    my ($id, $name, $value) = @row;
    push(@$directives, { id => $id, name => $name, value => $value });
  }

  dbi_free_stmt($sth);
  return $directives;
}

sub show_conf {
  my ($ctx) = @_;

  show_directives($ctx->{directives}, 0);
  show_ctxs($ctx->{contexts}, 0);
}

sub show_ctxs {
  my ($ctxs, $indent) = @_;

  foreach my $ctx (@$ctxs) {
    print STDOUT "\n";
    print STDOUT ' ' x $indent, "<$ctx->{type}",
      $ctx->{value} ? " $ctx->{value}" : '', ">";

    if ($opts->{'show-tags'}) {
      print STDOUT " ($opts->{'ctx-tab'}, id $ctx->{'id'})";
    }

    print STDOUT "\n";

    show_directives($ctx->{directives}, $indent + 2);
    show_ctxs($ctx->{contexts}, $indent + 2);

    print STDOUT ' ' x $indent, "</$ctx->{type}>\n";
  }
}

sub show_directives {
  my ($directives, $indent) = @_;

  foreach my $directive (@$directives) {
    print STDOUT ' ' x $indent, "$directive->{name} $directive->{value}";

    if ($opts->{'show-tags'}) {
      print STDOUT " ($opts->{'conf-tab'}, id $directive->{id})";
    }

    print STDOUT "\n";
  }
}

sub usage {

  print STDOUT <<END_OF_USAGE;

usage: $program [options]

 Database Options:

  --dbdriver
  --dbname
  --dbpass
  --dbserver
  --dbuser

 Table Options:

  --conf-tab                   Default: $opts->{'conf-tab'}
  --ctx-tab                    Default: $opts->{'ctx-tab'}
  --map-tab                    Default: $opts->{'map-tab'}

 General Options:

  --help
  --show-sql
  --show-tags
  --verbose

END_OF_USAGE

  exit 0;
}
