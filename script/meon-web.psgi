use strict;
use warnings;

use meon::Web;

my $app = meon::Web->apply_default_middlewares(meon::Web->psgi_app);
$app = meon::Web->apply_session_middleware($app);
$app;
