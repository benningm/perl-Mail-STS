package Mail::STS::Domain;

use Moose;

# VERSION
# ABSTRACT: class for MTA-STS domain lookups

use Time::Piece;
use Time::Seconds;

use Mail::STS::STSRecord;
use Mail::STS::TLSRPTRecord;
use Mail::STS::Policy;

=head1 SYNOPSIS

  my $domain = $sts->domain('example.com');
  # or construct it yourself
  my $domain = Mail::STS::Domain(
    resolver => $resolver, # Net::DNS::Resolver
    agent => $agent, # LWP::UserAgent
    domain => 'example.com',
  );

  $domain->mx;
  # [ 'mta1.example.com', ... ]
  $domain->tlsa;
  # undef or Net::DNS::RR:TLSA
  $domain->primary
  # mta1.example.com
  $domain->tlsrpt;
  # undef or Mail::STS::TLSRPTRecord
  $domain->sts;
  # undef or Mail::STS::STSRecord
  $domain->policy;
  # Mail::STS::Policy or will die()

=head1 ATTRIBUTES

=head2 domain (required)

The domain to lookup.

=head2 resolver (required)

A Net::DNS::Resolver object to use for DNS lookups.

=head2 agent (required)

A LWP::UserAgent object to use for retrieving policy
documents by https.

=head2 max_policy_size(default: 65536)

Maximum size allowed for STS policy document.

=cut

has 'domain' => (
  is => 'ro',
  isa => 'Str',
  required => 1,
);

has 'resolver' => (
  is => 'ro',
  isa => 'Net::DNS::Resolver',
  required => 1,
);

has 'agent' => (
  is => 'ro',
  isa => 'LWP::UserAgent',
  required => 1,
);

has 'max_policy_size' => (
  is => 'rw',
  isa => 'Maybe[Int]',
  default => 65536,
);

my $RECORDS = {
  'mx' => {
    type => 'MX',
  },
  'a' => {
    type => ['AAAA', 'A'],
  },
  'tlsa' => {
    type => 'TLSA',
    name => sub { '_25._tcp.'.shift },
    from => 'primary',
  },
  'sts' => {
    type => 'TXT',
    name => sub { '_mta-sts.'.shift },
  },
  'tlsrpt' => {
    type => 'TXT',
    name => sub { '_smtp._tls.'.shift },
  },
};

foreach my $record (keys %$RECORDS) {
  my $is_secure = "is_${record}_secure";
  my $accessor = "_${record}";
  my $type = $RECORDS->{$record}->{'type'};
  my $name = $RECORDS->{$record}->{'name'} || sub { shift };
  my $from = $RECORDS->{$record}->{'from'} || 'domain';

  has $is_secure => (
    is => 'ro',
    isa => 'Bool',
    lazy => 1,
    default => sub {
      my $self = shift;
      return 0 unless defined $self->$accessor;
      return $self->$accessor->header->ad ? 1 : 0;
    },
  );

  has $accessor => (
    is => 'ro',
    isa => 'Maybe[Net::DNS::Packet]',
    lazy => 1,
    default => sub {
      my $self = shift;
      my $domainname = $name->($self->$from);
      my $cur_domainname = $domainname;
      my $answer = undef;
      my $depth = 0;
      my $max_depth = 20;
      # for CNAMEs retry query with cname target aka follow CNAMEs
      while (1) {
        $answer = $self->resolver->query($cur_domainname, $type);
        if (! $answer) {
          last;
        }
        my @rr = $answer->answer;
        if ($rr[0]->type ne 'CNAME') {
          last;
        }
        # answer IS a CNAME, increase depth count
        $depth += 1;
        if ($depth > $max_depth) {
          $answer = undef;
          last;
        }
        $cur_domainname = $rr[0]->cname;
        # now loop to next query
      }
      return $answer;
    },
    clearer => "_reset_${accessor}",
  );
}

=head1 METHODS

=head2 mx()

Retrieves MX hostnames from DNS and returns a array reference.

List is sorted by priority.

  $domain->mx;
  # [ 'mta1.example.com', 'backup-mta1.example.com' ]

=cut

has 'mx' => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  lazy => 1,
  default => sub {
    my $self = shift;
    return [] unless defined $self->_mx;
    my @mx;
    if( $self->_mx->answer ) {
      my @rr = grep { $_->type eq 'MX' } $self->_mx->answer;
      @rr = sort { $a->preference <=> $b->preference } @rr;
      @mx = map { $_->exchange } @rr;
    }
    return \@mx;
  },
  traits => ['Array'],
  handles => {
    'mx_count' => 'count',
  },
);

=head2 a()

Returns the domainname if a AAAA or A record exists for the domain.

  $domain->a;
  # "example.com"

=cut

has 'a' => (
  is => 'ro',
  isa => 'Maybe[Str]',
  lazy => 1,
  default => sub {
    my $self = shift;
    if( my @rr = $self->_a->answer ) {
      return $self->domain;
    }
    return;
  },
);

=head2 record_type()

Returns the type of record the domain resolves to:

=over

=item "mx"

If domain has MX records.

=item "a"

If domain has an AAAA or A record.

=item "non-existent"

If the domain does not exist.

=back

=cut

has 'record_type' => (
  is => 'ro',
  isa => 'Str',
  lazy => 1,
  default => sub {
    my $self = shift;
    return 'mx' if $self->mx_count;
    return 'a' if defined $self->a;
    return 'non-existent';
  },
);

=head2 primary()

Returns the hostname of the primary MTA for this domain.

In case of MX records the first element of mx().

In case of an AAAA or A record the domainname.

Or undef if the domain does not resolve at all.

=cut

has 'primary' => (
  is => 'ro',
  isa => 'Maybe[Str]',
  lazy => 1,
  default => sub {
    my $self = shift;
    return $self->mx->[0] if $self->record_type eq 'mx';
    return $self->a if $self->record_type eq 'a';
    return;
  },
);

=head2 is_primary_secure()

Returns 1 if resolver signaled successfull DNSSEC validation
for the hostname returned by primary().

Otherwise returns 0.

=cut

has 'is_primary_secure' => (
  is => 'ro',
  isa => 'Bool',
  lazy => 1,
  default => sub {
    my $self = shift;
    return $self->is_mx_secure if $self->record_type eq 'mx';
    return $self->is_a_secure if $self->record_type eq 'a';
    return 0;
  },
);


=head2 tlsa()

Returns a Net::DNS::RR in case an TLSA record exists
for the hostname returned by primary() otherwise undef.

=cut

has 'tlsa' => (
  is => 'ro',
  isa => 'Maybe[Net::DNS::RR]',
  lazy => 1,
  default => sub {
    my $self = shift;
    return unless defined $self->_tlsa;
    if( my @rr = $self->_tlsa->answer ) {
      return $rr[0];
    }
    return;
  },
);

=head2 tlsrpt()

Returns an Mail::STS::TLSRPTRecord if a TLSRPT TXT
record for the domain could be lookup.

=cut

has 'tlsrpt' => (
  is => 'ro',
  isa => 'Maybe[Mail::STS::TLSRPTRecord]',
  lazy => 1,
  default => sub {
    my $self = shift;
    return unless defined $self->_tlsrpt;
    if( my @rr = $self->_tlsrpt->answer ) {
      return Mail::STS::TLSRPTRecord->new_from_string($rr[0]->txtdata);
    }
    return;
  },
);

=head2 sts()

Returns an Mail::STS::STSRecord if a STS TXT
record for the domain could be lookup.

=cut

has 'sts' => (
  is => 'ro',
  isa => 'Maybe[Mail::STS::STSRecord]',
  lazy => 1,
  default => sub {
    my $self = shift;
    return unless defined $self->_sts;
    if( my @rr = $self->_sts->answer ) {
      return Mail::STS::STSRecord->new_from_string($rr[0]->txtdata);
    }
    return;
  },
  clearer => '_reset_sts',
);

=head2 policy()

Returns a Mail::STS::Policy object if a policy for the domain
could be retrieved by the well known URL.

Otherwise will die with an error.

=cut

has 'policy_id' => ( is => 'rw', isa => 'Maybe[Str]');
has 'policy_expires_at' => ( is => 'rw', isa => 'Maybe[Time::Piece]');

sub set_policy_expire {
  my ($self, $max_age) = @_;
  return Time::Piece->new + Time::Seconds->new($max_age)
}

sub is_policy_expired {
  my $self = shift;
  return 1 if Time::Piece->new > $self->policy_expires_at;
  return 0;
}

has 'policy' => (
  is => 'ro',
  isa => 'Mail::STS::Policy',
  lazy => 1,
  default => sub {
    my $self = shift;
    die('could not retrieve _mta_sts record') unless defined $self->sts;
    $self->policy_id( $self->sts->id );
    my $policy = $self->retrieve_policy();
    $self->set_policy_expire($policy->max_age);
    return $policy;
  },
  clearer => '_reset_policy',
);

sub retrieve_policy {
    my $self = shift;
    my $url = 'https://mta-sts.'.$self->domain.'/.well-known/mta-sts.txt';
    my $response = $self->agent->get($url);
    my $content = $response->decoded_content;
    if(defined $self->max_policy_size && length($content) > $self->max_policy_size) {
      die('policy exceeding maximum policy size limit');
    }
    die('could not retrieve policy: '.$response->status_line) unless $response->is_success;
    return Mail::STS::Policy->new_from_string($content);
}

=head2 check_policy_update()

Checks if a new version of the policy is available.

First checks if the policy max_age has expired.
Then checks if the _mta_sts record lists a new policy version.

If there is a new policy the current policy will be resettet
so the next call to ->policy() will return the new policy.

Returns 1 if new policy was found otherwise 0.

=cut

sub check_policy_update {
  my $self = shift;
  return 0 unless $self->is_policy_expired;

  $self->_reset__sts;
  $self->_reset_sts;
  die('could not retrieve _mta_sts record') unless $self->sts;
  my $new_id = $self->sts->id;
  if($self->policy_id eq $new_id) {
    $self->set_policy_expire($self->policy->max_age);
    return 0;
  }

  $self->_reset_policy;
  return 1;
}

=head2 is_mx_secure()
=head2 is_a_secure()
=head2 is_tlsa_secure()
=head2 is_sts_secure()
=head2 is_tlsrpt_secure()

Returns 1 if resolver signaled successfull DNSSEC validation
(ad flag) for returned record otherwise returns 0.

=cut


1;

