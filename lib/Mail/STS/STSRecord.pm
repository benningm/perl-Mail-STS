package Mail::STS::STSRecord;

use Moose;

# VERSION
# ABSTRACT: a STS DNS TXT record string

has 'fields' => (
  is => 'ro',
  default => sub { [ 'v', 'id' ] },
);

with 'Mail::STS::SSKV';

has 'v' => (
  is => 'rw',
  isa => 'Str',
  default => 'STSv1',
);

has 'id' => (
  is => 'rw',
  isa => 'Str',
  required => 1,
);

1;

