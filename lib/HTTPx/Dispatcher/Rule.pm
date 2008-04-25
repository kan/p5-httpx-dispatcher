package HTTPx::Dispatcher::Rule;
use strict;
use warnings;
use base qw/Class::Accessor::Fast/;
use Scalar::Util qw/blessed/;
use Carp;

__PACKAGE__->mk_accessors(qw/re pattern controller action capture requirements conditions name/);

sub new {
    my ($class, $pattern, $args) = @_;
    $args ||= {};
    $args->{conditions} ||= {};

    my $self = bless { %$args }, $class;

    $self->compile($pattern);
    $self;
}

# compile url pattern to regex.
#   articles/:year/:month => qr{articles/(.+)/(.+)}
sub compile {
    my ($self, $pattern) = @_;

    $self->pattern( $pattern );

    # emulate named capture
    my @capture;
    $pattern =~ s{:([a-z0-9_]+)}{
        push @capture, $1;
        '(.+)'
    }ge;
    $self->re( qr{^$pattern$} );
    $self->capture( \@capture );
}

sub match {
    my ($self, $req) = @_;
    croak "request required" unless blessed $req;
    my $uri = $req->uri;
    $uri =~ s!^/+!!;
    $uri =~ s!\?.+!!;

    return unless $self->condition_check( $req );

    if ($uri =~ $self->re) {
        my @last_match_start = @-; # backup perlre vars
        my @last_match_end   = @+;

        my $response = {};
        for my $key (qw/action controller/) {
            $response->{$key} = $self->{$key} if $self->{$key};
        }
        my $requirements = $self->requirements;
        my $cnt      = 1;
        for my $key (@{ $self->capture }) {
            $response->{$key} = substr($uri, $last_match_start[$cnt], $last_match_end[$cnt] - $last_match_start[$cnt]);

            # validate
            # XXX this function needs test.
            if ( exists( $requirements->{$key} )
                && !( $response->{$key} =~ $requirements->{$key} ) )
            {
                die "invalid args: $response->{$key} ( $key ) does not matched $requirements->{$key}";
            }

            $cnt++;
        }
        return $self->_filter_response( $response );
    } else {
        return;
    }
}

sub _filter_response {
    my ($self, $input) = @_;
    my $output = {};
    for my $key (qw/controller action/) {
        $output->{$key} = delete $input->{$key} or croak "missing $key";
    }
    $output->{args} = $input;
    return $output;
}

sub condition_check {
    my ($self, $req) = @_;

    $self->condition_check_method($req) && $self->condition_check_function($req);
}

sub condition_check_method {
    my ($self, $req) = @_;
    croak "request required" unless blessed $req;

    my $method = $self->conditions->{method};
    return 1 unless $method;

    $method = [ $method ] unless ref $method;

    if (grep { uc $req->method eq uc $_} @$method) {
        return 1;
    } else {
        return 0;
    }
}

sub condition_check_function {
    my ($self, $req) = @_;
    croak "request required" unless blessed $req;

    my $function = $self->conditions->{function};
    return 1 unless $function;

    local $_ = $req;
    if ( $function->( $req ) ) {
        return 1;
    } else {
        return 0;
    }
}

sub uri_for {
    my ($self, $args) = @_;

    if (join(' ', sort keys %$args) eq join(' ', sort @{ $self->capture }) ) {
        my $uri = $self->pattern;
        $uri =~ s{:([a-z0-9A-Z]+)}{
            $args->{ $1 }
        }ge;
        "/$uri";
    }
}

1;

