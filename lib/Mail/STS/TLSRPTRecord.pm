package Mail::STS::TLSRPTRecord;

use Moose;

# VERSION
# ABSTRACT: a TLSRPT record string

has 'fields' => (
  is => 'ro',
  default => sub { [ 'v', 'rua' ] },
);

with 'Mail::STS::SSKV';

has 'v' => (
  is => 'rw',
  isa => 'Str',
  default => 'TLSRPTv1',
);

has 'rua' => (
  is => 'rw',
  isa => 'Str',
  required => 1,
);

1;

