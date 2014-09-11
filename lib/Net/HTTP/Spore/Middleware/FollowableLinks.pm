package Net::HTTP::Spore::Middleware::FollowableLinks;

# ABSTRACT: middleware to follow hrefs in "links" objects

use WebService::Zaqar::Response;

use Moose;
extends 'Net::HTTP::Spore::Middleware';

sub call {
    my ($self, $response) = @_;
    return $self->response_cb(sub {
        my $res = shift;
        WebService::Zaqar::Response->rebless_vanilla_response($res);
                              });
}

1;
