package Mail::STS::SSKV;

use Moose::Role;

# VERSION
# ABSTRACT: role for semicolon-separated key/value pairs

requires 'fields';

sub new_from_string {
  my ($class, $string) = @_;
  my @assignments = split(/\s*;\s*/, $string);
  my %kv;
  foreach my $assignment (@assignments) {
    if ($assignment !~ /=/) {
      next;
    }
    my ($key, $value) = split(/=/, $assignment, 2);
    $kv{$key} = $value;
  }
  if (! keys(%kv)) {
    return;
  }
  return $class->new(%kv);
}

sub as_string {
  my $self = shift;
  return join(' ',
    map { $_."=".$self->$_.";" } grep { defined $self->$_ } @{$self->fields}
  );
}

1;

