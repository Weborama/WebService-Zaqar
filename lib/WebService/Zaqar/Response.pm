package WebService::Zaqar::Response;

use strict;
use warnings;
use 5.010;
use Carp;
use autodie;
use utf8;

use Moo;
use Try::Tiny;

extends 'Net::HTTP::Spore::Response';

sub rebless_vanilla_response {
    my ($class, $vanilla) = @_;
    bless($vanilla, $class);
}

sub parameters_for_following_link {
    my ($self, $rel_name) = @_;
    my $body = $self->body or return;
    my $followup = try {
        # usually an array of { rel => REL-NAME, href => HREF }
        my $links = $body->{links};
        foreach my $link (@{$links}) {
            if ($link->{rel} eq $rel_name) {
                my $href = URI->new($link->{href});
                return [ $href->query_form ];
            }
        }
        return;
    };
    if ($followup) {
        return $followup;
    }
    return;
}

1;
