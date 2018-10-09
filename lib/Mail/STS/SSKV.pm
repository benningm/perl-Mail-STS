package Mail::STS::SSKV;

use Moose::Role;

# VERSION
# ABSTRACT: role for semicolon-separated key/value pairs

requires 'fields';

sub new_from_string {
  my ($class, $string) = @_;
  my %kv = map { split(/=/,$_,2) } split(/\s*;\s*/, $string);
  return $class->new(%kv);
}

sub as_string {
  my $self = shift;
  return join(' ',
    map { $_."=".$self->$_.";" } grep { defined $self->$_ } @{$self->fields}
  );
}

1;

