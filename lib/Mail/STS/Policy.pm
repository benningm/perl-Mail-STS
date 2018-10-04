package Mail::STS::Policy;

use Moose;

# VERSION
# ABSTRACT: class to parse and generate RFC8461 policies

has 'version' => (
  is => 'rw',
  isa => 'Str',
  default => 'STSv1',
);

has 'mode' => (
  is => 'rw',
  isa => 'Str',
  default => 'none',
);

has 'max_age' => (
  is => 'rw',
  isa => 'Maybe[Int]',
);

has 'mx' => (
  is => 'ro',
  isa => 'ArrayRef[Str]',
  default => sub { [] },
);

sub as_hash {
  return {
    'version' => $self->version,
    'mode' => $self->mode,
    'max_age' => $self->max_age,
    'mx' => $self->mx,
  };
}

sub as_string {
  my $hash = $self->as_hash;
  return join map {
    _sprint_key_value($_, $hash->{$_});
  } keys %$hash;
}

sub _sprint_key_value {
  my ($key, $value) = @_;
  return unless defined $value;
  unless(ref $value) {
    return("${key}: ${value}\n");
  }
  if(ref($value) eq 'ARRAY') {
    return join("\n", map { "${key}: $_" } @{$self->mx})."\n";
  } else {
    die('invalid data type for policy');
  }
}

1;

